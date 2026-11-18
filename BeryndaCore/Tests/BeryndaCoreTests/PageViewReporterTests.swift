import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import XCTest
@testable import BeryndaCore

private actor PageViewTransportStub: HTTPTransport {
    enum Outcome: Sendable {
        case status(Int, headers: [String: String])
        case failure
    }

    private let outcome: Outcome
    private(set) var requests: [URLRequest] = []

    init(_ outcome: Outcome) {
        self.outcome = outcome
    }

    func data(for request: URLRequest, maximumBytes: Int) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        switch outcome {
        case let .status(status, headers):
            return (
                Data(),
                HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: headers)!
            )
        case .failure:
            throw URLError(.notConnectedToInternet)
        }
    }
}

private final class MemoryPageViewStorage: PageViewStorage, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: String] = [:]

    func string(forKey key: String) -> String? {
        lock.lock(); defer { lock.unlock() }
        return values[key]
    }

    func set(_ value: String, forKey key: String) {
        lock.lock(); defer { lock.unlock() }
        values[key] = value
    }
}

private final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current = Date(timeIntervalSince1970: 1_800_000_000)

    func now() -> Date {
        lock.lock(); defer { lock.unlock() }
        return current
    }

    func advance(_ seconds: TimeInterval) {
        lock.lock(); defer { lock.unlock() }
        current = current.addingTimeInterval(seconds)
    }
}

private actor SleepCounter {
    private(set) var count = 0
    func record() { count += 1 }
}

/// Screen views for the site's analytics: what `POST pv/` carries, how the
/// visitor and session ids live, and that a failure stays silent.
final class PageViewReporterTests: XCTestCase {
    private let baseURL = URL(string: "https://berynda.org/api/v1/")!

    private func makeReporter(
        transport: PageViewTransportStub,
        storage: MemoryPageViewStorage = MemoryPageViewStorage(),
        clock: TestClock = TestClock(),
        sleeps: SleepCounter = SleepCounter()
    ) -> PageViewReporter {
        let client = BeryndaAPIClient(
            baseURL: baseURL,
            transport: transport,
            language: { "uk" },
            sleeper: { _ in await sleeps.record() },
            clientIdentity: ClientIdentity(version: "1.0.1", build: "7", systemVersion: "26.1")
        )
        return PageViewReporter(client: client, storage: storage, now: { clock.now() })
    }

    private func body(_ request: URLRequest) throws -> [String: Any] {
        let data = try XCTUnwrap(request.httpBody)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func testPostsTheWebBeaconBody() async throws {
        let transport = PageViewTransportStub(.status(204, headers: [:]))
        let reporter = makeReporter(transport: transport)

        await reporter.send(path: "/works/kobzar", language: "en")

        let requests = await transport.requests
        XCTAssertEqual(requests.count, 1)
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.absoluteString, "https://berynda.org/api/v1/pv/")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(request.value(forHTTPHeaderField: ClientIdentity.headerName), "ios/1.0.1")

        let json = try body(request)
        XCTAssertEqual(Set(json.keys), ["visitor_id", "session_id", "page_path", "interface_lang"])
        XCTAssertNotNil(UUID(uuidString: try XCTUnwrap(json["visitor_id"] as? String)))
        XCTAssertNotNil(UUID(uuidString: try XCTUnwrap(json["session_id"] as? String)))
        XCTAssertEqual(json["page_path"] as? String, "/works/kobzar")
        XCTAssertEqual(json["interface_lang"] as? String, "en")
        XCTAssertNil(json["referrer"])
        XCTAssertNil(json["utm_source"])
    }

    func testDropsQueryAndFragmentAndBoundsFields() async throws {
        let transport = PageViewTransportStub(.status(204, headers: [:]))
        let reporter = makeReporter(transport: transport)

        await reporter.send(path: "search?q=Шевченко#top", language: "  ")
        await reporter.send(path: "/" + String(repeating: "a", count: 3_000), language: "en-US-x-something")

        let requests = await transport.requests
        let first = try body(requests[0])
        XCTAssertEqual(first["page_path"] as? String, "/search")
        XCTAssertNil(first["interface_lang"])
        let second = try body(requests[1])
        XCTAssertEqual((second["page_path"] as? String)?.count, PageViewReporter.maximumPathLength)
        XCTAssertEqual(second["interface_lang"] as? String, "en-US-x-so")
    }

    func testVisitorIDIsMadeOnceAndKept() async throws {
        let storage = MemoryPageViewStorage()
        let transport = PageViewTransportStub(.status(204, headers: [:]))
        let clock = TestClock()

        await makeReporter(transport: transport, storage: storage, clock: clock).send(path: "/", language: "uk")
        clock.advance(3 * 24 * 60 * 60)
        // A new reporter over the same storage is the app's next launch.
        await makeReporter(transport: transport, storage: storage, clock: clock).send(path: "/", language: "uk")
        // Another install has its own storage.
        await makeReporter(transport: transport).send(path: "/", language: "uk")

        let visitors = try await transport.requests.map { try body($0)["visitor_id"] as? String }
        XCTAssertEqual(visitors[0], visitors[1])
        XCTAssertEqual(visitors[0], storage.string(forKey: PageViewReporter.visitorKey))
        XCTAssertNotEqual(visitors[0], visitors[2])
    }

    func testReplacesAStoredVisitorIDThatIsNotAUUID() async throws {
        let storage = MemoryPageViewStorage()
        storage.set("not-a-uuid", forKey: PageViewReporter.visitorKey)
        let transport = PageViewTransportStub(.status(204, headers: [:]))

        await makeReporter(transport: transport, storage: storage).send(path: "/", language: "uk")

        let visitor = try await body(transport.requests[0])["visitor_id"] as? String
        XCTAssertNotNil(UUID(uuidString: try XCTUnwrap(visitor)))
        XCTAssertEqual(storage.string(forKey: PageViewReporter.visitorKey), visitor)
    }

    func testSessionRotatesAfterThirtyIdleMinutes() async throws {
        let storage = MemoryPageViewStorage()
        let clock = TestClock()
        let transport = PageViewTransportStub(.status(204, headers: [:]))
        let reporter = makeReporter(transport: transport, storage: storage, clock: clock)

        await reporter.send(path: "/", language: "uk")
        // Activity keeps the session alive past 30 minutes in total…
        clock.advance(20 * 60)
        await reporter.send(path: "/search", language: "uk")
        clock.advance(20 * 60)
        await reporter.send(path: "/topics", language: "uk")
        // …and exactly 30 idle minutes is still the same session, as on the web.
        clock.advance(PageViewReporter.sessionTimeout)
        await reporter.send(path: "/periodicals", language: "uk")
        // One second more is a new session.
        clock.advance(PageViewReporter.sessionTimeout + 1)
        await reporter.send(path: "/app/library", language: "uk")
        // A relaunch inside the window keeps the session.
        clock.advance(60)
        await makeReporter(transport: transport, storage: storage, clock: clock).send(path: "/", language: "uk")

        let sessions = try await transport.requests.map { try body($0)["session_id"] as? String }
        XCTAssertEqual(sessions.count, 6)
        XCTAssertEqual(Set(sessions[0...3]).count, 1)
        XCTAssertNotEqual(sessions[3], sessions[4])
        XCTAssertEqual(sessions[4], sessions[5])
        let visitors = try await Set(transport.requests.map { try body($0)["visitor_id"] as? String })
        XCTAssertEqual(visitors.count, 1)
    }

    func testEmptyNoContentAnswerIsAccepted() async throws {
        // No Content-Type at all: the JSON checks of `request` would reject it.
        let transport = PageViewTransportStub(.status(204, headers: [:]))
        let client = BeryndaAPIClient(baseURL: baseURL, transport: transport)

        let payload = try await client.send(
            .pageView,
            method: .post,
            body: PageViewEvent(visitorID: "v", sessionID: "s", pagePath: "/", interfaceLanguage: nil)
        )

        XCTAssertTrue(payload.data.isEmpty)
        XCTAssertNil(payload.contentType)
    }

    func testServerErrorIsSwallowedAndNotRetried() async throws {
        for status in [429, 500, 503] {
            let transport = PageViewTransportStub(.status(status, headers: ["Retry-After": "1"]))
            let sleeps = SleepCounter()
            let reporter = makeReporter(transport: transport, sleeps: sleeps)

            await reporter.send(path: "/", language: "uk")

            let count = await transport.requests.count
            XCTAssertEqual(count, 1, "status \(status)")
            let slept = await sleeps.count
            XCTAssertEqual(slept, 0, "status \(status)")
        }
    }

    func testTransportFailureIsSwallowedAndNotRetried() async throws {
        let transport = PageViewTransportStub(.failure)
        let reporter = makeReporter(transport: transport)

        await reporter.send(path: "/", language: "uk")
        await reporter.send(path: "/search", language: "uk")

        let count = await transport.requests.count
        XCTAssertEqual(count, 2)
    }

    func testFireAndForgetReportReachesTheServer() async throws {
        let transport = PageViewTransportStub(.status(204, headers: [:]))
        let reporter = makeReporter(transport: transport)

        reporter.report(path: "/app/profile", language: "uk")

        for _ in 0..<200 {
            if await transport.requests.isEmpty == false { break }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        let requests = await transport.requests
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(try body(requests[0])["page_path"] as? String, "/app/profile")
    }

    func testWebEquivalentPaths() {
        let id = UUID(uuidString: "0F2A80AA-A6A6-5D8C-9E49-EE48D857B28E")!
        let lower = "0f2a80aa-a6a6-5d8c-9e49-ee48d857b28e"
        XCTAssertEqual(PageViewPath.catalog, "/")
        XCTAssertEqual(PageViewPath.search, "/search")
        XCTAssertEqual(PageViewPath.work(slug: "lisova-pisnia", id: id), "/works/lisova-pisnia")
        XCTAssertEqual(PageViewPath.work(slug: " ", id: id), "/works/\(lower)")
        XCTAssertEqual(PageViewPath.work(slug: nil, id: id), "/works/\(lower)")
        XCTAssertEqual(PageViewPath.person(id: id), "/persons/\(lower)")
        XCTAssertEqual(PageViewPath.reader(fileID: id), "/read/\(lower)")
        XCTAssertEqual(PageViewPath.topic(slug: "poeziia"), "/topics/poeziia")
        XCTAssertEqual(PageViewPath.topic(slug: "a/b?c"), "/topics/a%2Fb%3Fc")
        XCTAssertEqual(PageViewPath.periodicals, "/periodicals")
        XCTAssertEqual(PageViewPath.periodical(identifier: id.uuidString), "/periodicals/\(lower)")
        XCTAssertEqual(
            PageViewPath.periodicalIssue(periodicalIdentifier: "dzvin", issueID: id),
            "/periodicals/dzvin/issues/\(lower)"
        )
        XCTAssertEqual(
            PageViewPath.periodicalIssue(periodicalIdentifier: nil, issueID: id),
            "/app/periodical-issues/\(lower)"
        )
        XCTAssertEqual(PageViewPath.collection(slug: "klasyka"), "/collections/klasyka")
        XCTAssertEqual(PageViewPath.app("library"), "/app/library")
    }

    func testPageViewEndpoint() {
        XCTAssertEqual(
            APIEndpoint.pageView.url(relativeTo: baseURL)?.absoluteString,
            "https://berynda.org/api/v1/pv/"
        )
    }
}
