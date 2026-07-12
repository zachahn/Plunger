//
//  HTTPServer.swift
//  Plunger
//
//  A dependency-free HTTP/1.1 server that drives launches programmatically. It
//  is strictly launch-only: it exposes read-only views of the saved lists plus
//  Launcher.launch, and reaches no mutation method on the store. The listener
//  binds every interface (0.0.0.0) on the configured port (default 54175; dev
//  builds always bind 54176, ignoring the stored port), so
//  the launch API is reachable from the LAN. Two guards sit in front: a peer
//  filter (see PeerFilter) drops any connection whose source IP is not in an
//  allowed network — loopback, Tailscale (100.64.0.0/10), LAN, or any — and the
//  bearer token guards every authed route on top. The token travels over
//  plaintext HTTP. The app runs without the App Sandbox, so binding the socket
//  needs no entitlement. Changing the port calls restart() to rebind without
//  relaunching; network changes take effect on the next connection.
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
struct HTTPResponse: Equatable {
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
        body: HTMLPage.unauthorized,
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
    /// A terminal launch: open `command` in `terminal` at `path`.
    case launch(path: String, command: String, terminal: Terminal, success: HTTPResponse)
    /// A raw launch: run the already-interpolated `command` directly at `path`,
    /// no terminal window.
    case launchRaw(path: String, command: String, success: HTTPResponse)
}

/// Pure routing: maps a request plus a read-only store view to an outcome. It
/// performs no I/O, so tests drive it directly.
enum Router {
    /// A read-only view of the store, captured on the main actor before routing.
    struct StoreView {
        var token: String
        var authEnabled: Bool
        var paths: [String]
        var commands: [String]
        var rawCommands: [String]
        var terminal: Terminal
        var hasPath: (String) -> Bool
        var hasCommand: (String) -> Bool
        var hasRawCommand: (String) -> Bool
    }

    /// The fixed username both auth styles must carry.
    static let username = "plunger"

    static func route(_ request: HTTPRequest, store: StoreView) -> RouteOutcome {
        switch (request.method, request.target) {
        case ("GET", "/"):
            guard authorized(request, store: store) else { return .respond(.unauthorized) }
            return .respond(.html(HTMLPage.form(
                paths: store.paths,
                commands: store.commands,
                rawCommands: store.rawCommands
            )))

        case ("GET", "/style.css"):
            return .respond(.css(HTMLPage.stylesheet))

        case ("GET", "/health"):
            return .respond(.ok)

        case ("GET", "/paths"):
            guard authorized(request, store: store) else { return .respond(.forbidden) }
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
    /// must equal `plunger` and the password must equal the live token. The token
    /// check is constant-time so a network attacker can't recover it byte by byte
    /// from response-timing differences. When auth is turned off, every request
    /// passes without checking credentials.
    private static func authorized(_ request: HTTPRequest, store: Router.StoreView) -> Bool {
        guard store.authEnabled else { return true }
        guard let credentials = request.credentials else { return false }
        guard !credentials.password.isEmpty else { return false }
        // Compare both fields unconditionally, then combine, so neither the
        // username nor the token short-circuits the other. A wrong username must
        // not skip the token comparison, or response timing would reveal whether
        // the username alone was correct.
        let usernameOK = constantTimeEqual(credentials.username, username)
        let tokenOK = constantTimeEqual(credentials.password, store.token)
        return usernameOK && tokenOK
    }

    /// Compares two strings in time that depends only on the token's length, not
    /// on where the first differing byte falls, so token comparison leaks nothing
    /// through timing. A length mismatch folds into the result rather than
    /// returning early. Empty tokens never match.
    private static func constantTimeEqual(_ candidate: String, _ token: String) -> Bool {
        let a = Array(candidate.utf8)
        let b = Array(token.utf8)
        guard !b.isEmpty else { return false }

        var diff = a.count ^ b.count
        for i in 0..<b.count {
            // Index candidate modulo its length so a shorter candidate doesn't
            // shorten the loop; the length mismatch already forced diff != 0.
            let byte = a.isEmpty ? 0 : a[i % a.count]
            diff |= Int(byte ^ b[i])
        }
        return diff == 0
    }

    private static func pathsResponse(_ store: Router.StoreView) -> HTTPResponse {
        let payload = ["paths": store.paths.sortedForDisplay(), "commands": store.commands.sortedForDisplay()]
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

        guard authorized(request, store: store) else {
            return .respond(isForm ? .unauthorized : .forbidden)
        }

        guard let parsed = parse(request, isForm: isForm) else {
            return .respond(.badRequest)
        }
        let isRaw = store.hasRawCommand(parsed.command)
        guard store.hasPath(parsed.path), store.hasCommand(parsed.command) || isRaw else {
            return .respond(isForm ? .html(HTMLPage.unknown, status: 404, reason: "Not Found") : .notFound)
        }

        let success = isForm
            ? HTTPResponse.html(HTMLPage.launched(path: parsed.path, command: parsed.command))
            : HTTPResponse.launched
        if isRaw {
            let rendered = Interpolation.render(
                parsed.command,
                values: ["path": parsed.path, "command": parsed.command]
            )
            return .launchRaw(path: parsed.path, command: rendered, success: success)
        }
        return .launch(path: parsed.path, command: parsed.command, terminal: store.terminal, success: success)
    }

    /// Reads (path, command) from the body in whichever encoding the request used.
    private static func parse(_ request: HTTPRequest, isForm: Bool) -> (path: String, command: String)? {
        if isForm {
            let fields = FormDecoder.decode(request.body)
            guard let path = fields["path"], let command = fields["command"] else { return nil }
            return (path, command)
        }
        guard let body = try? JSONDecoder().decode(LaunchBody.self, from: request.body) else {
            return nil
        }
        return (body.path, body.command)
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

    /// Page templates, read from the bundle once at first use rather than per
    /// request.
    private static let formTemplate = Template.load("form.html")
    private static let launchedTemplate = Template.load("launched.html")

    /// HTML-escapes text interpolated into markup or an attribute value.
    static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    /// The launch form: two dropdowns posting to /launch. Regular commands open a
    /// terminal; raw commands run directly. The two kinds are split into separate
    /// `<optgroup>` sections. An empty list renders an empty select plus a note
    /// pointing to the menu bar.
    static func form(paths: [String], commands: [String], rawCommands: [String]) -> String {
        let hasAnyCommand = !commands.isEmpty || !rawCommands.isEmpty
        let note = (paths.isEmpty || !hasAnyCommand)
            ? "<p>No saved paths or commands yet — add them from the menu bar.</p>"
            : ""

        let commandOptions = optgroup("Commands", options(commands.sortedForDisplay(), label: { $0 }))
            + optgroup("Raw commands", options(rawCommands.sortedForDisplay(), label: { $0 }))

        return Template.render(formTemplate, [
            "note": note,
            "path_options": options(paths.sortedForDisplay(), label: displayPath),
            "command_options": commandOptions,
        ])
    }

    /// The success page after a launch.
    static func launched(path: String, command: String) -> String {
        Template.render(launchedTemplate, [
            "command": escape(command),
            "path": escape(displayPath(path)),
        ])
    }

    /// The page shown when the submitted path or command is no longer saved.
    static let unknown = Template.load("unknown.html")

    /// The body of the 401 challenge, shown before the browser's login prompt.
    static let unauthorized = Template.load("unauthorized.html")

    /// Renders `<option value="…">label</option>` for each value. The value is the
    /// stored string the router validates against; the label is for display.
    private static func options(_ values: [String], label: @escaping (String) -> String) -> String {
        values.map { value in
            "<option value=\"\(escape(value))\">\(escape(label(value)))</option>"
        }.joined()
    }

    /// Wraps rendered options in an `<optgroup>` with `label`. Returns an empty
    /// string when there are no options, so an empty command list adds no group.
    private static func optgroup(_ label: String, _ options: String) -> String {
        options.isEmpty ? "" : "<optgroup label=\"\(escape(label))\">\(options)</optgroup>"
    }
}

// MARK: - Server

@MainActor
@Observable
final class HTTPServer {
    /// This host's name, resolved once. The value never changes for the process,
    /// and `hostName` does a system lookup, so callers on view-render paths reuse
    /// this rather than resolving per render.
    private nonisolated static let hostName = ProcessInfo.processInfo.hostName

    /// The address for a given port. The listener binds every interface, so a
    /// LAN client reaches it at this host's name; the loopback form still works
    /// locally.
    nonisolated static func url(port: UInt16) -> String {
        "http://\(hostName):\(port)"
    }

    /// Whether the listener is bound. `.failed` carries the port that could not
    /// be bound, so the UI can explain what went wrong (usually a port in use).
    enum Status: Equatable {
        case stopped
        case running
        case failed(port: UInt16)
    }

    /// The current bind state, updated from the listener's state handler. UI
    /// observes this to show a bind failure.
    private(set) var status: Status = .stopped

    /// A read-only snapshot taken on the main actor before routing, so the
    /// off-actor connection handlers never touch the @MainActor store directly.
    private let snapshot: @MainActor () -> Router.StoreView
    /// Reads the configured port on the main actor at bind time.
    private let portProvider: @MainActor () -> UInt16
    /// Reads the allowed source networks on the main actor per connection.
    private let filterProvider: @MainActor () -> PeerFilter
    private let queue = DispatchQueue(label: "com.zachahn.Plunger.http")
    private var listener: NWListener?

    init(store: ConfigStore) {
        self.snapshot = {
            Router.StoreView(
                token: store.token,
                authEnabled: store.config.authEnabled,
                paths: store.config.paths,
                commands: store.config.commands,
                rawCommands: store.config.rawCommands,
                terminal: store.config.terminal,
                hasPath: { store.hasPath($0) },
                hasCommand: { store.hasCommand($0) },
                hasRawCommand: { store.hasRawCommand($0) }
            )
        }
        self.portProvider = { store.config.boundPort }
        self.filterProvider = { PeerFilter(allowed: store.config.allowedPeers) }
    }

    /// Binds 0.0.0.0 on the configured port (every interface) and begins
    /// accepting connections. Bind failures set `status` to `.failed`; the app
    /// keeps running without the server.
    func start() {
        guard listener == nil else { return }
        let configuredPort = portProvider()
        let parameters = NWParameters.tcp

        guard let port = NWEndpoint.Port(rawValue: configuredPort),
              let listener = try? NWListener(using: parameters, on: port) else {
            NSLog("Plunger: failed to create HTTP listener on port \(configuredPort)")
            status = .failed(port: configuredPort)
            return
        }
        self.listener = listener

        listener.stateUpdateHandler = { [weak self] state in
            self?.listenerStateChanged(state, port: configuredPort)
        }
        listener.newConnectionHandler = { [weak self] connection in
            self?.handle(connection)
        }
        listener.start(queue: queue)
    }

    /// Tears down the current listener and rebinds on the configured port. Call
    /// after changing the port so the change takes effect without relaunching.
    func restart() {
        listener?.cancel()
        listener = nil
        status = .stopped
        start()
    }

    /// Mirrors the listener's state into `status` on the main actor. `.ready`
    /// means the bind succeeded; `.failed` usually means the port is in use.
    private nonisolated func listenerStateChanged(_ state: NWListener.State, port: UInt16) {
        switch state {
        case .ready:
            Task { @MainActor in self.status = .running }
        case .failed:
            Task { @MainActor in
                self.listener?.cancel()
                self.listener = nil
                self.status = .failed(port: port)
            }
        default:
            break
        }
    }

    private nonisolated func handle(_ connection: NWConnection) {
        // Drop the connection unless its source IP is in an allowed category.
        // Filtering here, before any bytes are read, keeps a blocked peer from
        // reaching the router or the token check.
        let peer = Self.peerIP(of: connection)
        Task { @MainActor in
            let filter = filterProvider()
            guard let peer, filter.allows(peer) else {
                connection.cancel()
                return
            }
            connection.start(queue: queue)
            receive(connection, accumulated: Data())
        }
    }

    /// Extracts the remote peer's IP from a connection's endpoint, or nil when
    /// it can't be read (in which case the caller drops the connection).
    private nonisolated static func peerIP(of connection: NWConnection) -> PeerIP? {
        switch connection.endpoint {
        case let .hostPort(host, _):
            switch host {
            case let .ipv4(address):
                return PeerIP(rawBytes: address.rawValue)
            case let .ipv6(address):
                return PeerIP(rawBytes: address.rawValue)
            case let .name(name, _):
                return PeerIP(name)
            @unknown default:
                return nil
            }
        default:
            return nil
        }
    }

    /// Reads until the head and the declared body are both present, then routes.
    private nonisolated func receive(_ connection: NWConnection, accumulated: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] chunk, _, isComplete, error in
            guard let self else { return }

            var data = accumulated
            if let chunk { data.append(chunk) }

            if error != nil {
                connection.cancel()
                return
            }

            let parsed = HTTPRequestParser.parse(data)
            if var request = parsed {
                guard let declared = HTTPRequestParser.contentLength(request.headers) else {
                    HTTPServer.respond(connection, with: .badRequest)
                    return
                }
                if request.body.count >= declared {
                    // Trim any bytes past the declared length (a lying client or a
                    // pipelined second request) so the JSON/form decoder sees only
                    // this request's body.
                    request.body = request.body.prefix(declared)
                    self.dispatch(request, on: connection)
                    return
                }
            }

            if isComplete {
                // Connection closed before a full request arrived.
                if parsed == nil {
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
    private nonisolated func dispatch(_ request: HTTPRequest, on connection: NWConnection) {
        Task { @MainActor [snapshot] in
            let view = snapshot()
            switch Router.route(request, store: view) {
            case let .respond(response):
                HTTPServer.respond(connection, with: response)
            case let .launch(path, command, terminal, success):
                Launcher.launch(path: path, command: command, terminal: terminal)
                HTTPServer.respond(connection, with: success)
            case let .launchRaw(path, command, success):
                Launcher.launchRaw(path: path, command: command)
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
