//
//  PlungerTests.swift
//  PlungerTests
//
//  Covers the HTTP request parser and the pure routing logic. Routing stops at
//  the decision point: a valid /launch yields a `.launch(Entry)` outcome rather
//  than spawning Ghostty, so these tests never touch the launcher.
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
        let raw = data("GET /paths HTTP/1.1\r\nAuthorization:  Bearer abc \r\n\r\n")
        let request = try #require(HTTPRequestParser.parse(raw))

        #expect(request.headers["authorization"] == "Bearer abc")
        #expect(request.bearerToken == "abc")
    }

    @Test func bearerTokenIsNilWithoutBearerPrefix() throws {
        let raw = data("GET /paths HTTP/1.1\r\nAuthorization: Token abc\r\n\r\n")
        let request = try #require(HTTPRequestParser.parse(raw))
        #expect(request.bearerToken == nil)
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
        commands: [String] = ["/bin/zsh"]
    ) -> Router.StoreView {
        Router.StoreView(
            token: token,
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
        body: String = ""
    ) -> HTTPRequest {
        var headers: [String: String] = [:]
        if let token { headers["authorization"] = "Bearer \(token)" }
        return HTTPRequest(method: method, target: target, headers: headers, body: Data(body.utf8))
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
        #expect(response.json.contains("\"/a\""))
        #expect(response.json.contains("\"/b\""))
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

    @Test func validLaunchYieldsLaunchOutcome() {
        let outcome = Router.route(
            request(method: "POST", target: "/launch", token: token,
                    body: #"{"path":"/work","command":"/bin/zsh"}"#),
            store: storeView()
        )
        #expect(outcome == .launch(Entry(path: "/work", command: "/bin/zsh")))
    }

    @Test func wrongMethodOnKnownRouteIsMethodNotAllowed() {
        let outcome = Router.route(request(method: "DELETE", target: "/launch"), store: storeView())
        #expect(outcome == .respond(.methodNotAllowed))
    }

    @Test func unknownRouteIsNotFound() {
        let outcome = Router.route(request(method: "GET", target: "/nope"), store: storeView())
        #expect(outcome == .respond(.notFound))
    }
}
