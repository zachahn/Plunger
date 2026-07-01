//
//  PlungerTests.swift
//  PlungerTests
//
//  Covers the HTTP request parser and the pure routing logic. Routing stops at
//  the decision point: a valid /launch yields a `.launch` outcome rather than
//  spawning Ghostty, so these tests never touch the launcher.
//

import Foundation
import Testing
@testable import Plunger

// MARK: - Request parser

struct HTTPRequestParserTests {
    private func data(_ string: String) -> Data { Data(string.utf8) }

    @Test func parsesMethodTargetHeadersAndBody() throws {
        let raw = data("POST /launch HTTP/1.1\r\nHost: localhost\r\nContent-Length: 4\r\n\r\nbody")
        let request = try #require(HTTPRequestParser.parse(raw))

        #expect(request.method == "POST")
        #expect(request.target == "/launch")
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
        let raw = data("GET /health HTTP/1.1\r\nHost: localhost")
        #expect(HTTPRequestParser.parse(raw) == nil)
    }

    @Test func returnsNilForMalformedRequestLine() {
        let raw = data("GET /health\r\n\r\n")
        #expect(HTTPRequestParser.parse(raw) == nil)
    }

    @Test func returnsNilForHeaderWithoutColon() {
        let raw = data("GET /health HTTP/1.1\r\nBadHeader\r\n\r\n")
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

// MARK: - Router

struct RouterTests {
    private let token = "secret-token"

    private func storeView(
        paths: [String] = ["/work"],
        commands: [String] = ["/bin/zsh"],
        authEnabled: Bool = true
    ) -> Router.StoreView {
        Router.StoreView(
            token: token,
            authEnabled: authEnabled,
            paths: paths,
            commands: commands,
            hasPath: { paths.contains($0) },
            hasCommand: { commands.contains($0) }
        )
    }

    private func request(
        method: String,
        target: String,
        token: String? = nil,
        username: String = "plunger",
        contentType: String? = nil,
        body: String = ""
    ) -> HTTPRequest {
        var headers: [String: String] = [:]
        if let token { headers["authorization"] = "Bearer \(username):\(token)" }
        if let contentType { headers["content-type"] = contentType }
        return HTTPRequest(method: method, target: target, headers: headers, body: Data(body.utf8))
    }

    private func basicAuth(_ token: String, username: String = "plunger") -> [String: String] {
        let encoded = Data("\(username):\(token)".utf8).base64EncodedString()
        return ["authorization": "Basic \(encoded)"]
    }

    @Test func healthNeedsNoAuth() {
        let outcome = Router.route(request(method: "GET", target: "/health"), store: storeView())
        #expect(outcome == .respond(.ok))
    }

    @Test func pathsWithoutTokenIsForbidden() {
        let outcome = Router.route(request(method: "GET", target: "/paths"), store: storeView())
        #expect(outcome == .respond(.forbidden))
    }

    @Test func pathsWithWrongTokenIsForbidden() {
        let outcome = Router.route(
            request(method: "GET", target: "/paths", token: "nope"),
            store: storeView()
        )
        #expect(outcome == .respond(.forbidden))
    }

    @Test func pathsWithWrongUsernameIsForbidden() {
        let outcome = Router.route(
            request(method: "GET", target: "/paths", token: token, username: "intruder"),
            store: storeView()
        )
        #expect(outcome == .respond(.forbidden))
    }

    @Test func pathsAcceptBasicAuth() {
        let req = HTTPRequest(method: "GET", target: "/paths", headers: basicAuth(token), body: Data())
        let outcome = Router.route(req, store: storeView(paths: ["/a"], commands: ["/b"]))
        guard case let .respond(response) = outcome else {
            Issue.record("expected a response outcome")
            return
        }
        #expect(response.status == 200)
    }

    @Test func pathsWithTokenListsSavedLists() throws {
        let outcome = Router.route(
            request(method: "GET", target: "/paths", token: token),
            store: storeView(paths: ["/a"], commands: ["/b"])
        )
        guard case let .respond(response) = outcome else {
            Issue.record("expected a response outcome")
            return
        }
        #expect(response.status == 200)
        #expect(response.body.contains("\"/a\""))
        #expect(response.body.contains("\"/b\""))
    }

    @Test func pathsWithoutTokenSucceedsWhenAuthDisabled() {
        let outcome = Router.route(
            request(method: "GET", target: "/paths"),
            store: storeView(paths: ["/a"], commands: ["/b"], authEnabled: false)
        )
        guard case let .respond(response) = outcome else {
            Issue.record("expected a response outcome")
            return
        }
        #expect(response.status == 200)
    }

    @Test func rootWithoutTokenServesFormWhenAuthDisabled() {
        let outcome = Router.route(
            request(method: "GET", target: "/"),
            store: storeView(paths: ["/a"], commands: ["/b"], authEnabled: false)
        )
        guard case let .respond(response) = outcome else {
            Issue.record("expected a response outcome")
            return
        }
        #expect(response.status == 200)
    }

    @Test func launchWithoutTokenIsForbidden() {
        let outcome = Router.route(
            request(method: "POST", target: "/launch", body: #"{"path":"/work","command":"/bin/zsh"}"#),
            store: storeView()
        )
        #expect(outcome == .respond(.forbidden))
    }

    @Test func launchWithMalformedBodyIsBadRequest() {
        let outcome = Router.route(
            request(method: "POST", target: "/launch", token: token, body: "not json"),
            store: storeView()
        )
        #expect(outcome == .respond(.badRequest))
    }

    @Test func launchWithUnknownPathIsNotFound() {
        let outcome = Router.route(
            request(method: "POST", target: "/launch", token: token,
                    body: #"{"path":"/missing","command":"/bin/zsh"}"#),
            store: storeView()
        )
        #expect(outcome == .respond(.notFound))
    }

    @Test func launchWithUnknownCommandIsNotFound() {
        let outcome = Router.route(
            request(method: "POST", target: "/launch", token: token,
                    body: #"{"path":"/work","command":"/missing"}"#),
            store: storeView()
        )
        #expect(outcome == .respond(.notFound))
    }

    @Test func validJSONLaunchYieldsLaunchOutcome() {
        let outcome = Router.route(
            request(method: "POST", target: "/launch", token: token,
                    body: #"{"path":"/work","command":"/bin/zsh"}"#),
            store: storeView()
        )
        #expect(outcome == .launch(path: "/work", command: "/bin/zsh", success: .launched))
    }

    @Test func wrongMethodOnKnownRouteIsMethodNotAllowed() {
        let outcome = Router.route(request(method: "DELETE", target: "/launch"), store: storeView())
        #expect(outcome == .respond(.methodNotAllowed))
    }

    @Test func unknownRouteIsNotFound() {
        let outcome = Router.route(request(method: "GET", target: "/nope"), store: storeView())
        #expect(outcome == .respond(.notFound))
    }

    // MARK: HTML page and form launch

    @Test func rootWithoutAuthChallenges() {
        let outcome = Router.route(request(method: "GET", target: "/"), store: storeView())
        guard case let .respond(response) = outcome else {
            Issue.record("expected a response outcome")
            return
        }
        #expect(response.status == 401)
        #expect(response.headers["WWW-Authenticate"]?.hasPrefix("Basic") == true)
    }

    @Test func rootWithAuthServesForm() {
        let outcome = Router.route(
            request(method: "GET", target: "/", token: token),
            store: storeView(paths: ["/a"], commands: ["/b"])
        )
        guard case let .respond(response) = outcome else {
            Issue.record("expected a response outcome")
            return
        }
        #expect(response.status == 200)
        #expect(response.contentType.hasPrefix("text/html"))
        #expect(response.body.contains(#"<option value="/a">"#))
        #expect(response.body.contains(#"<option value="/b">"#))
    }

    @Test func rootEscapesHTMLInOptions() {
        let outcome = Router.route(
            request(method: "GET", target: "/", token: token),
            store: storeView(paths: ["/a&<b>"], commands: ["c\"d"])
        )
        guard case let .respond(response) = outcome else {
            Issue.record("expected a response outcome")
            return
        }
        #expect(response.body.contains("/a&amp;&lt;b&gt;"))
        #expect(response.body.contains("c&quot;d"))
        #expect(!response.body.contains("<b>"))
    }

    @Test func rootWithEmptyListsShowsNote() {
        let outcome = Router.route(
            request(method: "GET", target: "/", token: token),
            store: storeView(paths: [], commands: [])
        )
        guard case let .respond(response) = outcome else {
            Issue.record("expected a response outcome")
            return
        }
        #expect(response.status == 200)
        #expect(response.body.contains("No saved paths or commands"))
    }

    @Test func formLaunchYieldsHTMLSuccess() {
        let outcome = Router.route(
            request(method: "POST", target: "/launch", token: token,
                    contentType: "application/x-www-form-urlencoded",
                    body: "path=%2Fwork&command=%2Fbin%2Fzsh"),
            store: storeView()
        )
        guard case let .launch(path, command, success) = outcome else {
            Issue.record("expected a launch outcome")
            return
        }
        #expect(path == "/work")
        #expect(command == "/bin/zsh")
        #expect(success.contentType.hasPrefix("text/html"))
        #expect(success.body.contains("Launched"))
    }

    @Test func formLaunchWithoutAuthChallenges() {
        let outcome = Router.route(
            request(method: "POST", target: "/launch",
                    contentType: "application/x-www-form-urlencoded",
                    body: "path=%2Fwork&command=%2Fbin%2Fzsh"),
            store: storeView()
        )
        guard case let .respond(response) = outcome else {
            Issue.record("expected a response outcome")
            return
        }
        #expect(response.status == 401)
    }

    @Test func formLaunchWithUnknownPathShowsHTML() {
        let outcome = Router.route(
            request(method: "POST", target: "/launch", token: token,
                    contentType: "application/x-www-form-urlencoded",
                    body: "path=%2Fmissing&command=%2Fbin%2Fzsh"),
            store: storeView()
        )
        guard case let .respond(response) = outcome else {
            Issue.record("expected a response outcome")
            return
        }
        #expect(response.status == 404)
        #expect(response.contentType.hasPrefix("text/html"))
    }
}

// MARK: - Form decoding

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

// MARK: - HTML escaping

struct HTMLPageTests {
    @Test func escapesEntities() {
        #expect(HTMLPage.escape(#"<a> & "b""#) == "&lt;a&gt; &amp; &quot;b&quot;")
    }
}

// MARK: - Peer IP parsing

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
        // ::ffff:100.64.0.1 should reduce to the 4-byte IPv4 form.
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

// MARK: - Peer filtering

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
        // Just outside the range.
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
