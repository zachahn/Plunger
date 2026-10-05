import Foundation
import Network

struct HTTPRequest: Equatable {
    var method: String
    var target: String
    var headers: [String: String]
    var body: Data

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

    private static func split(_ pair: String) -> (username: String, password: String)? {
        guard let colon = pair.firstIndex(of: ":") else { return nil }
        let username = String(pair[..<colon])
        let password = String(pair[pair.index(after: colon)...])
        return (username, password)
    }
}

enum HTTPRequestParser {
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

    static func contentLength(_ headers: [String: String]) -> Int? {
        guard let raw = headers["content-length"] else { return 0 }
        guard let length = Int(raw), length >= 0 else { return nil }
        return length
    }
}

struct HTTPResponse: Equatable {
    var status: Int
    var reason: String
    var contentType: String = "text/plain; charset=utf-8"
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

    static func html(_ markup: String, status: Int = 200, reason: String = "OK") -> HTTPResponse {
        HTTPResponse(status: status, reason: reason, contentType: "text/html; charset=utf-8", body: markup)
    }

    static func css(_ source: String, status: Int = 200, reason: String = "OK") -> HTTPResponse {
        HTTPResponse(status: status, reason: reason, contentType: "text/css; charset=utf-8", body: source)
    }

    static let badRequest = HTTPResponse(status: 400, reason: "Bad Request", body: "bad request")
    static let notFound = HTTPResponse(status: 404, reason: "Not Found", body: "not found")
    static let methodNotAllowed = HTTPResponse(status: 405, reason: "Method Not Allowed", body: "method not allowed")

    static let unauthorized = HTTPResponse(
        status: 401,
        reason: "Unauthorized",
        contentType: "text/html; charset=utf-8",
        body: HTMLPage.unauthorized,
        headers: ["WWW-Authenticate": #"Basic realm="Plunger""#]
    )
}

enum RouteOutcome: Equatable {
    case respond(HTTPResponse)
    case launch(path: String, command: String, terminal: Terminal, success: HTTPResponse)
    case launchRaw(path: String, command: String, success: HTTPResponse)
}

enum Router {
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

    static let username = "plunger"

    static func route(_ request: HTTPRequest, store: StoreView) -> RouteOutcome {
        switch (request.method, request.target) {
        case ("GET", "/"):
            guard authorized(request, store: store) else { return .respond(.unauthorized) }
            return .respond(.html(formPage(store)))

        case ("POST", "/"):
            return launch(request, store: store)

        case ("GET", "/style.css"):
            return .respond(.css(HTMLPage.stylesheet))

        case (_, "/"), (_, "/style.css"):
            return .respond(.methodNotAllowed)

        default:
            return .respond(.notFound)
        }
    }

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

    private static func launch(_ request: HTTPRequest, store: Router.StoreView) -> RouteOutcome {
        guard authorized(request, store: store) else { return .respond(.unauthorized) }

        let fields = FormDecoder.decode(request.body)
        guard let path = fields["path"], let command = fields["command"] else {
            return .respond(.badRequest)
        }

        let isRaw = store.hasRawCommand(command)
        guard store.hasPath(path), store.hasCommand(command) || isRaw else {
            return .respond(.html(formPage(store, flash: .unknown), status: 404, reason: "Not Found"))
        }

        let success = HTTPResponse.html(formPage(store, flash: .launched(path: path, command: command)))
        if isRaw {
            let rendered = Interpolation.render(command, values: ["path": path, "command": command])
            return .launchRaw(path: path, command: rendered, success: success)
        }
        return .launch(path: path, command: command, terminal: store.terminal, success: success)
    }

    private static func formPage(_ store: Router.StoreView, flash: HTMLPage.Flash? = nil) -> String {
        HTMLPage.form(
            paths: store.paths,
            commands: store.commands,
            rawCommands: store.rawCommands,
            flash: flash
        )
    }
}

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

enum Template {
    static func load(_ name: String) -> String {
        let parts = name.split(separator: ".", maxSplits: 1)
        guard let url = Bundle.main.url(forResource: String(parts[0]), withExtension: String(parts[1])),
              let contents = try? String(contentsOf: url, encoding: .utf8) else {
            fatalError("Plunger: missing bundled resource \(name)")
        }
        return contents
    }

    static func render(_ template: String, _ values: [String: String]) -> String {
        var result = template
        for (key, value) in values {
            result = result.replacingOccurrences(of: "{{\(key)}}", with: value)
        }
        return result
    }
}

enum HTMLPage {
    enum Flash: Equatable {
        case launched(path: String, command: String)
        case unknown

        var markup: String {
            switch self {
            case let .launched(path, command):
                "<p class=\"flash\">Launched <code>\(escape(command))</code> in <code>\(escape(displayPath(path)))</code>.</p>"
            case .unknown:
                "<p class=\"flash error\">That path or command is no longer saved.</p>"
            }
        }
    }

    static let stylesheet = Template.load("style.css")

    private static let formTemplate = Template.load("form.html")

    static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    static func form(
        paths: [String],
        commands: [String],
        rawCommands: [String],
        flash: Flash? = nil
    ) -> String {
        let hasAnyCommand = !commands.isEmpty || !rawCommands.isEmpty
        let note = (paths.isEmpty || !hasAnyCommand)
            ? "<p>No saved paths or commands yet — add them from the menu bar.</p>"
            : ""

        let commandOptions = optgroup("Commands", options(commands.sortedForDisplay(), label: { $0 }))
            + optgroup("Raw commands", options(rawCommands.sortedForDisplay(), label: { $0 }))

        return Template.render(formTemplate, [
            "flash": flash?.markup ?? "",
            "note": note,
            "path_options": options(paths.sortedForDisplay(), label: displayPath),
            "command_options": commandOptions,
        ])
    }

    static let unauthorized = Template.load("unauthorized.html")

    private static func options(_ values: [String], label: @escaping (String) -> String) -> String {
        values.map { value in
            "<option value=\"\(escape(value))\">\(escape(label(value)))</option>"
        }.joined()
    }

    private static func optgroup(_ label: String, _ options: String) -> String {
        options.isEmpty ? "" : "<optgroup label=\"\(escape(label))\">\(options)</optgroup>"
    }
}

@MainActor
@Observable
final class HTTPServer {
    private nonisolated static let hostName = ProcessInfo.processInfo.hostName

    nonisolated static func url(port: UInt16) -> String {
        "http://\(hostName):\(port)"
    }

    enum Status: Equatable {
        case stopped
        case running
        case failed(port: UInt16)
    }

    private(set) var status: Status = .stopped

    private let snapshot: @MainActor () -> Router.StoreView
    private let portProvider: @MainActor () -> UInt16
    private let filterProvider: @MainActor () -> PeerFilter
    private let queue = DispatchQueue(label: "com.zachahn.Plunger.http")
    private var listener: NWListener?

    init(store: ConfigStore) {
        self.snapshot = {
            Router.StoreView(
                token: store.token,
                authEnabled: store.config.authEnabled,
                paths: store.launchablePaths,
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

    func restart() {
        listener?.cancel()
        listener = nil
        status = .stopped
        start()
    }

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
                    request.body = request.body.prefix(declared)
                    self.dispatch(request, on: connection)
                    return
                }
            }

            if isComplete {
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
