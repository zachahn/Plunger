import Foundation
import Testing
@testable import Plunger

struct HTTPRequestParserTests {
    private func data(_ string: String) -> Data { Data(string.utf8) }

    @Test func parsesMethodTargetHeadersAndBody() throws {
        let raw = data("POST / HTTP/1.1\r\nHost: localhost\r\nContent-Length: 4\r\n\r\nbody")
        let request = try #require(HTTPRequestParser.parse(raw))

        #expect(request.method == "POST")
        #expect(request.target == "/")
        #expect(request.headers["host"] == "localhost")
        #expect(request.headers["content-length"] == "4")
        #expect(request.body == data("body"))
    }

    @Test func lowercasesHeaderNamesAndTrimsValues() throws {
        let raw = data("GET /paths HTTP/1.1\r\nAuthorization:  Bearer plunger:abc \r\n\r\n")
        let request = try #require(HTTPRequestParser.parse(raw))

        #expect(request.headers["authorization"] == "Bearer plunger:abc")
        let credentials = try #require(request.credentials)
        #expect(credentials.username == "plunger")
        #expect(credentials.password == "abc")
    }

    @Test func bearerCredentialsSplitOnFirstColon() throws {
        let raw = data("GET /paths HTTP/1.1\r\nAuthorization: Bearer plunger:a:b\r\n\r\n")
        let request = try #require(HTTPRequestParser.parse(raw))
        let credentials = try #require(request.credentials)
        #expect(credentials.username == "plunger")
        #expect(credentials.password == "a:b")
    }

    @Test func bearerWithoutColonHasNoCredentials() throws {
        let raw = data("GET /paths HTTP/1.1\r\nAuthorization: Bearer abc\r\n\r\n")
        let request = try #require(HTTPRequestParser.parse(raw))
        #expect(request.credentials == nil)
    }

    @Test func basicCredentialsDecodeBase64() throws {
        let encoded = Data("plunger:secret-token".utf8).base64EncodedString()
        let raw = data("GET /paths HTTP/1.1\r\nAuthorization: Basic \(encoded)\r\n\r\n")
        let request = try #require(HTTPRequestParser.parse(raw))
        let credentials = try #require(request.credentials)
        #expect(credentials.username == "plunger")
        #expect(credentials.password == "secret-token")
    }

    @Test func credentialsNilForUnknownScheme() throws {
        let raw = data("GET /paths HTTP/1.1\r\nAuthorization: Token abc\r\n\r\n")
        let request = try #require(HTTPRequestParser.parse(raw))
        #expect(request.credentials == nil)
    }

    @Test func returnsNilWhenHeadIncomplete() {
        let raw = data("GET / HTTP/1.1\r\nHost: localhost")
        #expect(HTTPRequestParser.parse(raw) == nil)
    }

    @Test func returnsNilForMalformedRequestLine() {
        let raw = data("GET /\r\n\r\n")
        #expect(HTTPRequestParser.parse(raw) == nil)
    }

    @Test func returnsNilForHeaderWithoutColon() {
        let raw = data("GET / HTTP/1.1\r\nBadHeader\r\n\r\n")
        #expect(HTTPRequestParser.parse(raw) == nil)
    }

    @Test func contentLengthDefaultsToZeroWhenAbsent() {
        #expect(HTTPRequestParser.contentLength([:]) == 0)
    }

    @Test func contentLengthRejectsNonNumeric() {
        #expect(HTTPRequestParser.contentLength(["content-length": "abc"]) == nil)
    }

    @Test func contentLengthRejectsNegative() {
        #expect(HTTPRequestParser.contentLength(["content-length": "-1"]) == nil)
    }
}

struct RouterTests {
    private let token = "secret-token"

    private func storeView(
        paths: [String] = ["/work"],
        commands: [String] = ["/bin/zsh"],
        rawCommands: [String] = [],
        terminal: Terminal = .ghostty,
        authEnabled: Bool = true
    ) -> Router.StoreView {
        Router.StoreView(
            token: token,
            authEnabled: authEnabled,
            paths: paths,
            commands: commands,
            rawCommands: rawCommands,
            terminal: terminal,
            hasPath: { paths.contains($0) },
            hasCommand: { commands.contains($0) },
            hasRawCommand: { rawCommands.contains($0) }
        )
    }

    private func request(
        method: String,
        target: String,
        token: String? = nil,
        username: String = "plunger",
        body: String = ""
    ) -> HTTPRequest {
        var headers: [String: String] = [:]
        if let token { headers["authorization"] = "Bearer \(username):\(token)" }
        return HTTPRequest(method: method, target: target, headers: headers, body: Data(body.utf8))
    }

    private func basicAuth(_ token: String, username: String = "plunger") -> [String: String] {
        let encoded = Data("\(username):\(token)".utf8).base64EncodedString()
        return ["authorization": "Basic \(encoded)"]
    }

    private func response(_ outcome: RouteOutcome) throws -> HTTPResponse {
        guard case let .respond(response) = outcome else {
            Issue.record("expected a response outcome")
            throw RouteExpectationError.wrongOutcome
        }
        return response
    }

    private enum RouteExpectationError: Error {
        case wrongOutcome
    }

    @Test func rootWithoutTokenChallenges() throws {
        let page = try response(Router.route(request(method: "GET", target: "/"), store: storeView()))
        #expect(page.status == 401)
        #expect(page.headers["WWW-Authenticate"]?.hasPrefix("Basic") == true)
    }

    @Test func rootWithWrongTokenChallenges() throws {
        let page = try response(Router.route(
            request(method: "GET", target: "/", token: "nope"),
            store: storeView()
        ))
        #expect(page.status == 401)
    }

    @Test func rootWithWrongUsernameChallenges() throws {
        let page = try response(Router.route(
            request(method: "GET", target: "/", token: token, username: "intruder"),
            store: storeView()
        ))
        #expect(page.status == 401)
    }

    @Test func rootAcceptsBasicAuth() throws {
        let request = HTTPRequest(method: "GET", target: "/", headers: basicAuth(token), body: Data())
        let page = try response(Router.route(request, store: storeView()))
        #expect(page.status == 200)
    }

    @Test func rootWithoutTokenServesFormWhenAuthDisabled() throws {
        let page = try response(Router.route(
            request(method: "GET", target: "/"),
            store: storeView(authEnabled: false)
        ))
        #expect(page.status == 200)
    }

    @Test func launchWithoutTokenChallenges() throws {
        let page = try response(Router.route(
            request(method: "POST", target: "/", body: "path=%2Fwork&command=%2Fbin%2Fzsh"),
            store: storeView()
        ))
        #expect(page.status == 401)
    }

    @Test func wrongMethodOnKnownRouteIsMethodNotAllowed() {
        let outcome = Router.route(request(method: "DELETE", target: "/"), store: storeView())
        #expect(outcome == .respond(.methodNotAllowed))
    }

    @Test func unknownRouteIsNotFound() {
        let outcome = Router.route(request(method: "GET", target: "/nope"), store: storeView())
        #expect(outcome == .respond(.notFound))
    }

    @Test func rootServesTheFormPostingToItself() throws {
        let page = try response(Router.route(
            request(method: "GET", target: "/", token: token),
            store: storeView(paths: ["/a"], commands: ["/b"])
        ))
        #expect(page.status == 200)
        #expect(page.contentType.hasPrefix("text/html"))
        #expect(page.body.contains(#"action="/""#))
        #expect(page.body.contains(#"<option value="/a">"#))
        #expect(page.body.contains(#"<option value="/b">"#))
    }

    @Test func rootEscapesHTMLInOptions() throws {
        let page = try response(Router.route(
            request(method: "GET", target: "/", token: token),
            store: storeView(paths: ["/a&<b>"], commands: ["c\"d"])
        ))
        #expect(page.body.contains("/a&amp;&lt;b&gt;"))
        #expect(page.body.contains("c&quot;d"))
        #expect(!page.body.contains("<b>"))
    }

    @Test func rootWithEmptyListsShowsNote() throws {
        let page = try response(Router.route(
            request(method: "GET", target: "/", token: token),
            store: storeView(paths: [], commands: [])
        ))
        #expect(page.status == 200)
        #expect(page.body.contains("No saved paths or commands"))
    }

    @Test func launchRedisplaysTheFormWithAFlash() {
        let outcome = Router.route(
            request(method: "POST", target: "/", token: token,
                    body: "path=%2Fwork&command=%2Fbin%2Fzsh"),
            store: storeView()
        )
        guard case let .launch(path, command, _, success) = outcome else {
            Issue.record("expected a launch outcome")
            return
        }
        #expect(path == "/work")
        #expect(command == "/bin/zsh")
        #expect(success.contentType.hasPrefix("text/html"))
        #expect(success.body.contains(#"<p class="flash">Launched"#))
        #expect(success.body.contains(#"<option value="/work">"#))
    }

    @Test func launchCarriesConfiguredTerminal() {
        let outcome = Router.route(
            request(method: "POST", target: "/", token: token,
                    body: "path=%2Fwork&command=%2Fbin%2Fzsh"),
            store: storeView(terminal: .iterm)
        )
        guard case let .launch(_, _, terminal, _) = outcome else {
            Issue.record("expected a launch outcome")
            return
        }
        #expect(terminal == .iterm)
    }

    @Test func rawCommandYieldsInterpolatedRawLaunch() {
        let outcome = Router.route(
            request(method: "POST", target: "/", token: token,
                    body: "path=%2Fwork&command=echo+%7B%7Bpath%7D%7D"),
            store: storeView(commands: [], rawCommands: ["echo {{path}}"])
        )
        guard case let .launchRaw(path, command, _) = outcome else {
            Issue.record("expected a raw launch outcome")
            return
        }
        #expect(path == "/work")
        #expect(command == "echo /work")
    }

    @Test func flashEscapesTheLaunchedPair() {
        let outcome = Router.route(
            request(method: "POST", target: "/", token: token,
                    body: "path=%2Fa%26%3Cb%3E&command=c%22d"),
            store: storeView(paths: ["/a&<b>"], commands: ["c\"d"])
        )
        guard case let .launch(_, _, _, success) = outcome else {
            Issue.record("expected a launch outcome")
            return
        }
        #expect(success.body.contains("/a&amp;&lt;b&gt;"))
        #expect(!success.body.contains("<b>"))
    }

    @Test func launchWithMissingFieldIsBadRequest() {
        let outcome = Router.route(
            request(method: "POST", target: "/", token: token, body: "path=%2Fwork"),
            store: storeView()
        )
        #expect(outcome == .respond(.badRequest))
    }

    @Test func launchWithUnknownPathRedisplaysTheFormWithAnError() throws {
        let page = try response(Router.route(
            request(method: "POST", target: "/", token: token,
                    body: "path=%2Fmissing&command=%2Fbin%2Fzsh"),
            store: storeView()
        ))
        #expect(page.status == 404)
        #expect(page.contentType.hasPrefix("text/html"))
        #expect(page.body.contains(#"<p class="flash error">"#))
        #expect(page.body.contains(#"<option value="/work">"#))
    }

    @Test func launchWithUnknownCommandRedisplaysTheFormWithAnError() throws {
        let page = try response(Router.route(
            request(method: "POST", target: "/", token: token,
                    body: "path=%2Fwork&command=%2Fmissing"),
            store: storeView()
        ))
        #expect(page.status == 404)
        #expect(page.body.contains(#"<p class="flash error">"#))
    }

    @Test func unknownRawCommandRedisplaysTheFormWithAnError() throws {
        let page = try response(Router.route(
            request(method: "POST", target: "/", token: token,
                    body: "path=%2Fwork&command=echo+hi"),
            store: storeView(commands: [], rawCommands: [])
        ))
        #expect(page.status == 404)
        #expect(page.body.contains(#"<p class="flash error">"#))
    }
}

@Suite("PathExpansion")
struct PathExpansionTests {
    private func makeTree(_ entries: [String]) throws -> String {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("plunger-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        for entry in entries {
            let url = root.appendingPathComponent(entry)
            if entry.hasSuffix("/") {
                try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            } else {
                try Data().write(to: url)
            }
        }
        return root.path
    }

    @Test func listsFoldersInsideSorted() throws {
        let root = try makeTree(["beta/", "Alpha/", "notes.txt"])
        let folders = PathExpansion.foldersInside(root)
        #expect(folders == [root + "/Alpha", root + "/beta"])
    }

    @Test func skipsHiddenEntries() throws {
        let root = try makeTree([".git/", "src/"])
        #expect(PathExpansion.foldersInside(root) == [root + "/src"])
    }

    @Test func onlyGoesOneLevelDeep() throws {
        let root = try makeTree(["outer/", "outer/inner/"])
        #expect(PathExpansion.foldersInside(root) == [root + "/outer"])
    }

    @Test func missingDirectoryHasNoFolders() {
        #expect(PathExpansion.foldersInside("/nope/does/not/exist").isEmpty)
    }

    @Test func plainPathStandsForItself() {
        let launchable = PathExpansion.launchable(
            paths: ["/work"],
            launchFoldersInside: [],
            folders: { _ in ["/work/a"] }
        )
        #expect(launchable == ["/work"])
    }

    @Test func pathIsReplacedByTheFoldersInsideIt() {
        let launchable = PathExpansion.launchable(
            paths: ["/work", "/solo"],
            launchFoldersInside: ["/work"],
            folders: { _ in ["/work/a", "/work/b"] }
        )
        #expect(launchable == ["/work/a", "/work/b", "/solo"])
    }

    @Test func pathWithNoFoldersInsideContributesNothing() {
        let launchable = PathExpansion.launchable(
            paths: ["/work"],
            launchFoldersInside: ["/work"],
            folders: { _ in [] }
        )
        #expect(launchable.isEmpty)
    }

    @Test func folderAlsoSavedOnItsOwnAppearsOnce() {
        let launchable = PathExpansion.launchable(
            paths: ["/work", "/work/a"],
            launchFoldersInside: ["/work"],
            folders: { _ in ["/work/a"] }
        )
        #expect(launchable == ["/work/a"])
    }
}

struct FormDecoderTests {
    @Test func decodesAndPercentDecodes() {
        let fields = FormDecoder.decode(Data("path=%2Fwork&command=ls+-la".utf8))
        #expect(fields["path"] == "/work")
        #expect(fields["command"] == "ls -la")
    }

    @Test func missingValueIsEmpty() {
        let fields = FormDecoder.decode(Data("path=&command".utf8))
        #expect(fields["path"] == "")
        #expect(fields["command"] == "")
    }
}

@Suite("Launcher.loginShellWrapped")
struct LoginShellWrappedTests {
    @Test func wrapsPlainCommandInLoginInteractiveZsh() {
        #expect(Launcher.loginShellWrapped("/usr/bin/irb") == "/bin/zsh -lic '/usr/bin/irb'")
    }

    @Test func keepsArgumentsInsideSingleQuotes() {
        #expect(Launcher.loginShellWrapped("/bin/ls -la /tmp") == "/bin/zsh -lic '/bin/ls -la /tmp'")
    }

    @Test func escapesEmbeddedSingleQuote() {
        // A single quote closes, escapes a literal quote, and reopens: '\''.
        #expect(
            Launcher.loginShellWrapped("git commit -m 'wip'")
                == #"/bin/zsh -lic 'git commit -m '\''wip'\'''"#
        )
    }

    @Test func leavesDoubleQuotesUntouched() {
        #expect(
            Launcher.loginShellWrapped(#"echo "a b""#)
                == #"/bin/zsh -lic 'echo "a b"'"#
        )
    }
}

struct HTMLPageTests {
    @Test func escapesEntities() {
        #expect(HTMLPage.escape(#"<a> & "b""#) == "&lt;a&gt; &amp; &quot;b&quot;")
    }
}

@Suite("PeerIP")
struct PeerIPTests {
    @Test func parsesIPv4() {
        #expect(PeerIP("100.64.0.1")?.bytes == [100, 64, 0, 1])
        #expect(PeerIP("127.0.0.1")?.isIPv4 == true)
    }

    @Test func parsesIPv6Loopback() {
        #expect(PeerIP("::1")?.bytes == [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1])
    }

    @Test func collapsesIPv4MappedIPv6() {
        let ip = PeerIP("::ffff:100.64.0.1")
        #expect(ip?.isIPv4 == true)
        #expect(ip?.bytes == [100, 64, 0, 1])
    }

    @Test func stripsZoneID() {
        #expect(PeerIP("fe80::1%en0") != nil)
    }

    @Test func rejectsGarbage() {
        #expect(PeerIP("not-an-ip") == nil)
        #expect(PeerIP("") == nil)
    }
}

@Suite("PeerFilter")
struct PeerFilterTests {
    private func ip(_ s: String) -> PeerIP { PeerIP(s)! }

    @Test func emptySetAllowsNothing() {
        let filter = PeerFilter(allowed: [])
        #expect(filter.allows(ip("127.0.0.1")) == false)
        #expect(filter.allows(ip("100.64.0.1")) == false)
    }

    @Test func loopbackCategory() {
        let filter = PeerFilter(allowed: [.loopback])
        #expect(filter.allows(ip("127.0.0.1")))
        #expect(filter.allows(ip("::1")))
        #expect(filter.allows(ip("100.64.0.1")) == false)
        #expect(filter.allows(ip("192.168.1.5")) == false)
    }

    @Test func tailscaleCategory() {
        let filter = PeerFilter(allowed: [.tailscale])
        // 100.64.0.0/10 spans 100.64.x through 100.127.x.
        #expect(filter.allows(ip("100.64.0.1")))
        #expect(filter.allows(ip("100.100.50.2")))
        #expect(filter.allows(ip("100.127.255.254")))
        #expect(filter.allows(ip("100.63.255.255")) == false)
        #expect(filter.allows(ip("100.128.0.0")) == false)
        #expect(filter.allows(ip("127.0.0.1")) == false)
    }

    @Test func localNetworkCategory() {
        let filter = PeerFilter(allowed: [.localNetwork])
        #expect(filter.allows(ip("10.0.0.1")))
        #expect(filter.allows(ip("172.16.5.5")))
        #expect(filter.allows(ip("172.31.0.1")))
        #expect(filter.allows(ip("192.168.1.1")))
        #expect(filter.allows(ip("169.254.1.1")))
        // 172.32 is outside 172.16/12.
        #expect(filter.allows(ip("172.32.0.1")) == false)
        #expect(filter.allows(ip("100.64.0.1")) == false)
    }

    @Test func anyCategoryAllowsEverything() {
        let filter = PeerFilter(allowed: [.any])
        #expect(filter.allows(ip("8.8.8.8")))
        #expect(filter.allows(ip("100.64.0.1")))
        #expect(filter.allows(ip("127.0.0.1")))
    }

    @Test func categoriesCombine() {
        let filter = PeerFilter(allowed: [.loopback, .tailscale])
        #expect(filter.allows(ip("127.0.0.1")))
        #expect(filter.allows(ip("100.64.0.1")))
        #expect(filter.allows(ip("192.168.1.1")) == false)
    }
}

struct InterpolationTests {
    @Test func basicSingleSubstitution() {
        let result = Interpolation.render("hello {{name}}", values: ["name": "world"])
        #expect(result == "hello world")
    }

    @Test func multiplePlaceholders() {
        let result = Interpolation.render("{{greeting}}, {{name}}!", values: ["greeting": "hi", "name": "bob"])
        #expect(result == "hi, bob!")
    }

    @Test func whitespaceInsideBraces() {
        let result = Interpolation.render("{{ path }}", values: ["path": "/usr/bin"])
        #expect(result == "/usr/bin")
    }

    @Test func unknownKeyLeftVerbatim() {
        let result = Interpolation.render("{{missing}}", values: [:])
        #expect(result == "{{missing}}")
    }

    @Test func unmatchedOpenBraceEmittedVerbatim() {
        let result = Interpolation.render("before {{unclosed rest", values: ["unclosed": "x"])
        #expect(result == "before {{unclosed rest")
    }

    @Test func emptyTemplateReturnsEmpty() {
        #expect(Interpolation.render("", values: ["name": "world"]) == "")
    }

    @Test func noPlaceholderPassesThroughUnchanged() {
        let result = Interpolation.render("plain text", values: ["name": "world"])
        #expect(result == "plain text")
    }

    @Test func adjacentPlaceholders() {
        let result = Interpolation.render("{{a}}{{b}}", values: ["a": "1", "b": "2"])
        #expect(result == "12")
    }
}
