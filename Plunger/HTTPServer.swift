//
//  HTTPServer.swift
//  Plunger
//
//  A dependency-free HTTP/1.1 server that drives launches programmatically. It
//  is strictly launch-only: it exposes read-only views of the saved lists plus
//  Launcher.launch, and reaches no mutation method on the store. The listener
//  binds every interface (0.0.0.0), so the launch API is reachable from the
//  LAN; the bearer token is the only guard, and it travels over plaintext HTTP.
//  The app runs without the App Sandbox, so binding the socket needs no
//  entitlement.
//
//  Routes (one request per connection, no keep-alive):
//    GET  /health  -> 200 {"ok":true}                       (no auth)
//    GET  /paths   -> 200 {"paths":[...],"commands":[...]}   (auth)
//    POST /launch  -> 200 {"launched":true}                  (auth)
//

import Foundation
import Network

// MARK: - Request parsing

/// A parsed HTTP/1.1 request: method, target, lowercased header map, and body.
struct HTTPRequest: Equatable {
    var method: String
    var target: String
    var headers: [String: String]
    var body: Data

    /// The bearer token from the Authorization header, if present.
    var bearerToken: String? {
        guard let value = headers["authorization"] else { return nil }
        let prefix = "Bearer "
        guard value.hasPrefix(prefix) else { return nil }
        return String(value.dropFirst(prefix.count))
    }
}

enum HTTPRequestParser {
    /// Parses a complete request from `data`. Returns nil when the head is
    /// malformed; callers answer nil with a 400. The head must be fully present
    /// (terminated by CRLFCRLF); body length is taken from Content-Length.
    static func parse(_ data: Data) -> HTTPRequest? {
        let separator = Data("\r\n\r\n".utf8)
        guard let headEnd = data.range(of: separator) else { return nil }

        let headData = data[data.startIndex..<headEnd.lowerBound]
        guard let head = String(data: headData, encoding: .utf8) else { return nil }

        var lines = head.components(separatedBy: "\r\n")
        guard !lines.isEmpty else { return nil }

        let requestLine = lines.removeFirst().split(separator: " ", omittingEmptySubsequences: false)
        guard requestLine.count == 3 else { return nil }
        let method = String(requestLine[0])
        let target = String(requestLine[1])
        guard !method.isEmpty, !target.isEmpty else { return nil }

        var headers: [String: String] = [:]
        for line in lines where !line.isEmpty {
            guard let colon = line.firstIndex(of: ":") else { return nil }
            let name = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { return nil }
            headers[name] = value
        }

        let body = Data(data[headEnd.upperBound...])
        return HTTPRequest(method: method, target: target, headers: headers, body: body)
    }

    /// The Content-Length value, or 0 when absent. Returns nil when the header
    /// is present but not a non-negative integer.
    static func contentLength(_ headers: [String: String]) -> Int? {
        guard let raw = headers["content-length"] else { return 0 }
        guard let length = Int(raw), length >= 0 else { return nil }
        return length
    }
}

// MARK: - Responses

/// A minimal HTTP response: status, reason phrase, and a JSON body.
struct HTTPResponse {
    var status: Int
    var reason: String
    var json: String

    func serialized() -> Data {
        let body = Data(json.utf8)
        let head = """
        HTTP/1.1 \(status) \(reason)\r
        Content-Type: application/json\r
        Content-Length: \(body.count)\r
        Connection: close\r
        \r

        """
        return Data(head.utf8) + body
    }

    static let ok = HTTPResponse(status: 200, reason: "OK", json: #"{"ok":true}"#)
    static let launched = HTTPResponse(status: 200, reason: "OK", json: #"{"launched":true}"#)
    static let badRequest = HTTPResponse(status: 400, reason: "Bad Request", json: #"{"error":"bad request"}"#)
    static let forbidden = HTTPResponse(status: 403, reason: "Forbidden", json: #"{"error":"forbidden"}"#)
    static let notFound = HTTPResponse(status: 404, reason: "Not Found", json: #"{"error":"not found"}"#)
    static let methodNotAllowed = HTTPResponse(status: 405, reason: "Method Not Allowed", json: #"{"error":"method not allowed"}"#)
}

// MARK: - Routing

/// The body of a /launch request.
private struct LaunchBody: Decodable {
    var path: String
    var command: String
}

/// What the router decided a valid /launch request should do. The router stops
/// here so its decisions are testable without spawning Ghostty.
enum RouteOutcome: Equatable {
    case respond(HTTPResponse)
    case launch(Entry)

    static func == (lhs: RouteOutcome, rhs: RouteOutcome) -> Bool {
        switch (lhs, rhs) {
        case let (.respond(a), .respond(b)):
            return a.status == b.status && a.json == b.json
        case let (.launch(a), .launch(b)):
            return a == b
        default:
            return false
        }
    }
}

/// Pure routing: maps a request plus a read-only store view to an outcome. It
/// performs no I/O, so tests drive it directly.
enum Router {
    /// A read-only view of the store, captured on the main actor before routing.
    struct StoreView {
        var token: String
        var paths: [String]
        var commands: [String]
        var hasPath: (String) -> Bool
        var hasCommand: (String) -> Bool
    }

    static func route(_ request: HTTPRequest, store: StoreView) -> RouteOutcome {
        switch (request.method, request.target) {
        case ("GET", "/health"):
            return .respond(.ok)

        case ("GET", "/paths"):
            guard authorized(request, token: store.token) else { return .respond(.forbidden) }
            return .respond(pathsResponse(store))

        case ("POST", "/launch"):
            guard authorized(request, token: store.token) else { return .respond(.forbidden) }
            return launch(request, store: store)

        case (_, "/health"), (_, "/paths"), (_, "/launch"):
            return .respond(.methodNotAllowed)

        default:
            return .respond(.notFound)
        }
    }

    private static func authorized(_ request: HTTPRequest, token: String) -> Bool {
        guard let presented = request.bearerToken, !presented.isEmpty else { return false }
        return presented == token
    }

    private static func pathsResponse(_ store: Router.StoreView) -> HTTPResponse {
        let payload = ["paths": store.paths, "commands": store.commands]
        let encoder = JSONEncoder()
        encoder.outputFormatting = .withoutEscapingSlashes
        guard let data = try? encoder.encode(payload),
              let json = String(data: data, encoding: .utf8) else {
            return HTTPResponse(status: 500, reason: "Internal Server Error", json: #"{"error":"encode failed"}"#)
        }
        return HTTPResponse(status: 200, reason: "OK", json: json)
    }

    private static func launch(_ request: HTTPRequest, store: Router.StoreView) -> RouteOutcome {
        guard let body = try? JSONDecoder().decode(LaunchBody.self, from: request.body) else {
            return .respond(.badRequest)
        }
        guard store.hasPath(body.path), store.hasCommand(body.command) else {
            return .respond(.notFound)
        }
        return .launch(Entry(path: body.path, command: body.command))
    }
}

// MARK: - Server

final class HTTPServer: @unchecked Sendable {
    static let port: UInt16 = 8765

    /// The address shown in the menu. The listener binds every interface, so a
    /// LAN client reaches it at this host's name; the loopback form still works
    /// locally.
    static var url: String {
        let host = ProcessInfo.processInfo.hostName
        return "http://\(host):\(port)"
    }

    /// A read-only snapshot taken on the main actor before routing, so the
    /// off-actor connection handlers never touch the @MainActor store directly.
    private let snapshot: @MainActor () -> Router.StoreView
    private let queue = DispatchQueue(label: "com.zachahn.Plunger.http")
    private var listener: NWListener?

    @MainActor
    init(store: ConfigStore) {
        self.snapshot = {
            Router.StoreView(
                token: store.token,
                paths: store.config.paths,
                commands: store.config.commands,
                hasPath: { store.hasPath($0) },
                hasCommand: { store.hasCommand($0) }
            )
        }
    }

    /// Binds 0.0.0.0:8765 (every interface) and begins accepting connections.
    /// Failures are logged; the app keeps running without the server.
    func start() {
        guard listener == nil else { return }
        let parameters = NWParameters.tcp

        guard let port = NWEndpoint.Port(rawValue: Self.port),
              let listener = try? NWListener(using: parameters, on: port) else {
            NSLog("Plunger: failed to create HTTP listener on port \(Self.port)")
            return
        }
        self.listener = listener

        listener.newConnectionHandler = { [weak self] connection in
            self?.handle(connection)
        }
        listener.start(queue: queue)
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        receive(connection, accumulated: Data())
    }

    /// Reads until the head and the declared body are both present, then routes.
    private func receive(_ connection: NWConnection, accumulated: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] chunk, _, isComplete, error in
            guard let self else { return }

            var data = accumulated
            if let chunk { data.append(chunk) }

            if error != nil {
                connection.cancel()
                return
            }

            if let request = HTTPRequestParser.parse(data) {
                guard let declared = HTTPRequestParser.contentLength(request.headers) else {
                    HTTPServer.respond(connection, with: .badRequest)
                    return
                }
                if request.body.count >= declared {
                    self.dispatch(request, on: connection)
                    return
                }
            }

            if isComplete {
                // Connection closed before a full request arrived.
                if HTTPRequestParser.parse(data) == nil {
                    HTTPServer.respond(connection, with: .badRequest)
                } else {
                    connection.cancel()
                }
                return
            }

            self.receive(connection, accumulated: data)
        }
    }

    /// Hops to the main actor to snapshot the store, routes, and either writes a
    /// response or launches and then writes the success response.
    private func dispatch(_ request: HTTPRequest, on connection: NWConnection) {
        Task { @MainActor [snapshot] in
            let view = snapshot()
            switch Router.route(request, store: view) {
            case let .respond(response):
                HTTPServer.respond(connection, with: response)
            case let .launch(entry):
                Launcher.launch(entry)
                HTTPServer.respond(connection, with: .launched)
            }
        }
    }

    private static func respond(_ connection: NWConnection, with response: HTTPResponse) {
        connection.send(content: response.serialized(), completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}
