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
//  Auth is HTTP Basic with the fixed username "plunger" and the generated token
//  as the password, so a browser prompts once and caches it. The bearer path is
//  kept for API clients but now carries the username too, as "plunger:<token>".
//
//  Routes (one request per connection, no keep-alive):
//    GET  /          -> 200 text/html (the launch form)       (auth, 401 challenge)
//    GET  /style.css -> 200 text/css                          (no auth)
//    GET  /health    -> 200 {"ok":true}                       (no auth)
//    GET  /paths     -> 200 {"paths":[...],"commands":[...]}   (auth, 403)
//    POST /launch    -> launches; JSON or form-encoded body    (auth)
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

    /// A username/password pair carried by the Authorization header. Both auth
    /// styles encode the same pair: Basic as base64(user:pass), Bearer as the
    /// plaintext "user:token". Returns nil when no usable credentials are present.
    var credentials: (username: String, password: String)? {
        guard let value = headers["authorization"] else { return nil }

        if value.hasPrefix("Basic ") {
            let encoded = String(value.dropFirst("Basic ".count))
            guard let data = Data(base64Encoded: encoded),
                  let decoded = String(data: data, encoding: .utf8) else { return nil }
            return Self.split(decoded)
        }

        if value.hasPrefix("Bearer ") {
            return Self.split(String(value.dropFirst("Bearer ".count)))
        }

        return nil
    }

    /// Splits "username:password" on the first colon. Returns nil without a colon.
    private static func split(_ pair: String) -> (username: String, password: String)? {
        guard let colon = pair.firstIndex(of: ":") else { return nil }
        let username = String(pair[..<colon])
        let password = String(pair[pair.index(after: colon)...])
        return (username, password)
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

/// A minimal HTTP response: status, reason phrase, a content type, a body, and
/// any extra headers (the 401 challenge uses one).
struct HTTPResponse {
    var status: Int
    var reason: String
    var contentType: String = "application/json"
    var body: String
    var headers: [String: String] = [:]

    func serialized() -> Data {
        let bodyData = Data(body.utf8)
        var head = "HTTP/1.1 \(status) \(reason)\r\n"
        head += "Content-Type: \(contentType)\r\n"
        head += "Content-Length: \(bodyData.count)\r\n"
        for (name, value) in headers {
            head += "\(name): \(value)\r\n"
        }
        head += "Connection: close\r\n\r\n"
        return Data(head.utf8) + bodyData
    }

    /// An HTML response. Defaults to 200 OK.
    static func html(_ markup: String, status: Int = 200, reason: String = "OK") -> HTTPResponse {
        HTTPResponse(status: status, reason: reason, contentType: "text/html; charset=utf-8", body: markup)
    }

    /// A CSS response. Defaults to 200 OK.
    static func css(_ source: String, status: Int = 200, reason: String = "OK") -> HTTPResponse {
        HTTPResponse(status: status, reason: reason, contentType: "text/css; charset=utf-8", body: source)
    }

    static let ok = HTTPResponse(status: 200, reason: "OK", body: #"{"ok":true}"#)
    static let launched = HTTPResponse(status: 200, reason: "OK", body: #"{"launched":true}"#)
    static let badRequest = HTTPResponse(status: 400, reason: "Bad Request", body: #"{"error":"bad request"}"#)
    static let forbidden = HTTPResponse(status: 403, reason: "Forbidden", body: #"{"error":"forbidden"}"#)
    static let notFound = HTTPResponse(status: 404, reason: "Not Found", body: #"{"error":"not found"}"#)
    static let methodNotAllowed = HTTPResponse(status: 405, reason: "Method Not Allowed", body: #"{"error":"method not allowed"}"#)

    /// A 401 that makes the browser show its Basic-auth login prompt.
    static let unauthorized = HTTPResponse(
        status: 401,
        reason: "Unauthorized",
        contentType: "text/html; charset=utf-8",
        body: "<!doctype html><title>Plunger</title><link rel=\"stylesheet\" href=\"/style.css\"><p>Authentication required.</p>",
        headers: ["WWW-Authenticate": #"Basic realm="Plunger""#]
    )
}

// MARK: - Routing

/// The body of a /launch request.
private struct LaunchBody: Decodable {
    var path: String
    var command: String
}

/// What the router decided a valid /launch request should do. The router stops
/// here so its decisions are testable without spawning Ghostty. `launch` carries
/// the success response to send afterward, so a form submit gets HTML and a JSON
/// client gets JSON.
enum RouteOutcome: Equatable {
    case respond(HTTPResponse)
    case launch(Entry, success: HTTPResponse)

    static func == (lhs: RouteOutcome, rhs: RouteOutcome) -> Bool {
        switch (lhs, rhs) {
        case let (.respond(a), .respond(b)):
            return same(a, b)
        case let (.launch(a, sa), .launch(b, sb)):
            return a == b && same(sa, sb)
        default:
            return false
        }
    }

    private static func same(_ a: HTTPResponse, _ b: HTTPResponse) -> Bool {
        a.status == b.status && a.body == b.body
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

    /// The fixed username both auth styles must carry.
    static let username = "plunger"

    static func route(_ request: HTTPRequest, store: StoreView) -> RouteOutcome {
        switch (request.method, request.target) {
        case ("GET", "/"):
            guard authorized(request, token: store.token) else { return .respond(.unauthorized) }
            return .respond(.html(HTMLPage.form(paths: store.paths, commands: store.commands)))

        case ("GET", "/style.css"):
            return .respond(.css(HTMLPage.stylesheet))

        case ("GET", "/health"):
            return .respond(.ok)

        case ("GET", "/paths"):
            guard authorized(request, token: store.token) else { return .respond(.forbidden) }
            return .respond(pathsResponse(store))

        case ("POST", "/launch"):
            return launch(request, store: store)

        case (_, "/"):
            return .respond(.methodNotAllowed)

        case (_, "/style.css"), (_, "/health"), (_, "/paths"), (_, "/launch"):
            return .respond(.methodNotAllowed)

        default:
            return .respond(.notFound)
        }
    }

    /// Accepts either auth style. Both encode (username, password); the username
    /// must equal `plunger` and the password must equal the live token.
    private static func authorized(_ request: HTTPRequest, token: String) -> Bool {
        guard let credentials = request.credentials else { return false }
        guard !credentials.password.isEmpty else { return false }
        return credentials.username == username && credentials.password == token
    }

    private static func pathsResponse(_ store: Router.StoreView) -> HTTPResponse {
        let payload = ["paths": store.paths, "commands": store.commands]
        let encoder = JSONEncoder()
        encoder.outputFormatting = .withoutEscapingSlashes
        guard let data = try? encoder.encode(payload),
              let json = String(data: data, encoding: .utf8) else {
            return HTTPResponse(status: 500, reason: "Internal Server Error", body: #"{"error":"encode failed"}"#)
        }
        return HTTPResponse(status: 200, reason: "OK", body: json)
    }

    /// Decodes a launch from JSON or a form-encoded body. A form submit comes from
    /// the HTML page, so it gets a 401 challenge when unauthorized and an HTML
    /// result on success; a JSON client gets 403 and JSON.
    private static func launch(_ request: HTTPRequest, store: Router.StoreView) -> RouteOutcome {
        let isForm = (request.headers["content-type"] ?? "")
            .hasPrefix("application/x-www-form-urlencoded")

        guard authorized(request, token: store.token) else {
            return .respond(isForm ? .unauthorized : .forbidden)
        }

        guard let parsed = entry(from: request, isForm: isForm) else {
            return .respond(.badRequest)
        }
        guard store.hasPath(parsed.path), store.hasCommand(parsed.command) else {
            return .respond(isForm ? .html(HTMLPage.unknown, status: 404, reason: "Not Found") : .notFound)
        }

        let success = isForm
            ? HTTPResponse.html(HTMLPage.launched(parsed))
            : HTTPResponse.launched
        return .launch(parsed, success: success)
    }

    /// Reads (path, command) from the body in whichever encoding the request used.
    private static func entry(from request: HTTPRequest, isForm: Bool) -> Entry? {
        if isForm {
            let fields = FormDecoder.decode(request.body)
            guard let path = fields["path"], let command = fields["command"] else { return nil }
            return Entry(path: path, command: command)
        }
        guard let body = try? JSONDecoder().decode(LaunchBody.self, from: request.body) else {
            return nil
        }
        return Entry(path: body.path, command: body.command)
    }
}

// MARK: - Form decoding

/// Decodes an `application/x-www-form-urlencoded` body into fields. Splits on `&`
/// then `=`, replaces `+` with space, and percent-decodes each side.
enum FormDecoder {
    static func decode(_ body: Data) -> [String: String] {
        guard let raw = String(data: body, encoding: .utf8) else { return [:] }
        var fields: [String: String] = [:]
        for pair in raw.split(separator: "&", omittingEmptySubsequences: true) {
            let parts = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            let name = unescape(String(parts[0]))
            let value = parts.count > 1 ? unescape(String(parts[1])) : ""
            guard !name.isEmpty else { continue }
            fields[name] = value
        }
        return fields
    }

    private static func unescape(_ component: String) -> String {
        let spaced = component.replacingOccurrences(of: "+", with: " ")
        return spaced.removingPercentEncoding ?? spaced
    }
}

// MARK: - Templates

/// Loads a file from Resources/ in the app bundle and substitutes `{{token}}`
/// placeholders with caller-supplied values. No loops, no conditionals — just
/// literal replacement, since every page here is a handful of fixed slots.
enum Template {
    /// Reads `name` (e.g. "form.html") from the bundle. Traps if the resource
    /// is missing, since that's a packaging bug, not a runtime condition.
    static func load(_ name: String) -> String {
        let parts = name.split(separator: ".", maxSplits: 1)
        guard let url = Bundle.main.url(forResource: String(parts[0]), withExtension: String(parts[1])),
              let contents = try? String(contentsOf: url, encoding: .utf8) else {
            fatalError("Plunger: missing bundled resource \(name)")
        }
        return contents
    }

    /// Replaces every `{{key}}` in `template` with its value from `values`.
    static func render(_ template: String, _ values: [String: String]) -> String {
        var result = template
        for (key, value) in values {
            result = result.replacingOccurrences(of: "{{\(key)}}", with: value)
        }
        return result
    }
}

// MARK: - HTML

/// Builds the pages the browser sees: the launch form and the result of a
/// launch. Markup lives in Resources/*.html, rendered via `Template`; styled
/// via a linked stylesheet at /style.css; no JavaScript.
enum HTMLPage {
    /// Served at GET /style.css.
    static let stylesheet = Template.load("style.css")

    /// HTML-escapes text interpolated into markup or an attribute value.
    static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    /// The launch form: two dropdowns posting to /launch. An empty list renders an
    /// empty select plus a note pointing to the menu bar.
    static func form(paths: [String], commands: [String]) -> String {
        let note = (paths.isEmpty || commands.isEmpty)
            ? "<p>No saved paths or commands yet — add them from the menu bar.</p>"
            : ""

        return Template.render(Template.load("form.html"), [
            "note": note,
            "path_options": options(paths, label: displayPath),
            "command_options": options(commands, label: { $0 }),
        ])
    }

    /// The success page after a launch.
    static func launched(_ entry: Entry) -> String {
        Template.render(Template.load("launched.html"), [
            "command": escape(entry.command),
            "path": escape(displayPath(entry.path)),
        ])
    }

    /// The page shown when the submitted path or command is no longer saved.
    static let unknown = Template.load("unknown.html")

    /// Renders `<option value="…">label</option>` for each value. The value is the
    /// stored string the router validates against; the label is for display.
    private static func options(_ values: [String], label: @escaping (String) -> String) -> String {
        values.map { value in
            "<option value=\"\(escape(value))\">\(escape(label(value)))</option>"
        }.joined()
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
            case let .launch(entry, success):
                Launcher.launch(entry)
                HTTPServer.respond(connection, with: success)
            }
        }
    }

    private static func respond(_ connection: NWConnection, with response: HTTPResponse) {
        connection.send(content: response.serialized(), completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}
