import BeryndaCore
import XCTest
@testable import Berynda

/// Pull to refresh must reload in place. Switching the screen to its loading
/// state replaced the `List` that owns the refresh control mid-gesture: the
/// refresh was cancelled, the spinner never finished and the section headers
/// stayed pinned under the reading switch.
@MainActor
final class CatalogRefreshTests: XCTestCase {
    func testCatalogRefreshKeepsTheListOnScreenWhileReloading() async throws {
        let repository = RefreshStub()
        let model = CatalogViewModel(repository: repository)
        await model.load()
        XCTAssertEqual(workTitles(model), ["First"])

        await repository.holdNextRequest()
        let refresh = Task { await model.refresh() }
        await repository.waitForHeldRequest()

        XCTAssertEqual(workTitles(model), ["First"], "The list must stay while the refresh is in flight")

        await repository.release(with: .works(["Second"]))
        await refresh.value
        XCTAssertEqual(workTitles(model), ["Second"])
    }

    func testFailedCatalogRefreshKeepsTheWorksAlreadyShown() async throws {
        let repository = RefreshStub()
        let model = CatalogViewModel(repository: repository)
        await model.load()

        await repository.failNextRequest()
        await model.refresh()

        XCTAssertEqual(workTitles(model), ["First"])
    }

    func testCancelledFirstLoadDoesNotLeaveTheCatalogLoadingForever() async throws {
        let repository = RefreshStub()
        let model = CatalogViewModel(repository: repository)

        await repository.holdNextRequest()
        let load = Task { await model.load() }
        await repository.waitForHeldRequest()
        if case .loading = model.state {} else { XCTFail("Expected the first load to show loading") }

        load.cancel()
        await load.value

        guard case .idle = model.state else {
            return XCTFail("A cancelled load must hand back to .idle, got \(model.state)")
        }
    }

    func testTopicListRefreshKeepsTheTopicsOnScreen() async throws {
        let repository = RefreshStub()
        let model = TopicListViewModel(repository: repository)
        await model.load()
        XCTAssertEqual(model.topics.map(\.name), ["Поезія"])

        await repository.holdNextRequest()
        let refresh = Task { await model.refresh() }
        await repository.waitForHeldRequest()
        guard case .loaded = model.state else { return XCTFail("Topics must stay during a refresh") }
        XCTAssertEqual(model.topics.map(\.name), ["Поезія"])

        await repository.release(with: .topics)
        await refresh.value
        guard case .loaded = model.state else { return XCTFail("Expected loaded topics") }
    }

    func testPeriodicalListRefreshKeepsThePeriodicalsOnScreen() async throws {
        let repository = RefreshStub()
        let model = PeriodicalListViewModel(repository: repository)
        await model.load()
        XCTAssertEqual(model.periodicals.map(\.name), ["Вісник"])

        await repository.failNextRequest()
        await model.refresh()

        guard case .loaded = model.state else { return XCTFail("A failed refresh must keep the periodicals") }
        XCTAssertEqual(model.periodicals.map(\.name), ["Вісник"])
    }

    private func workTitles(_ model: CatalogViewModel) -> [String]? {
        guard case let .loaded(works, _) = model.state else { return nil }
        return works.map(\.title)
    }
}

private actor RefreshStub: CatalogRepository {
    enum Answer: Sendable {
        case works([String])
        case topics
    }

    private var holdNext = false
    private var failNext = false
    private var held: CheckedContinuation<Answer, Never>?
    private var heldWaiters: [CheckedContinuation<Void, Never>] = []

    func holdNextRequest() { holdNext = true }
    func failNextRequest() { failNext = true }

    func waitForHeldRequest() async {
        if held != nil { return }
        await withCheckedContinuation { heldWaiters.append($0) }
    }

    func release(with answer: Answer) {
        held?.resume(returning: answer)
        held = nil
    }

    /// Answers at once, fails once, or waits: for `release`, or until the
    /// calling task is cancelled, which then throws like a real request.
    private func answer(default value: Answer) async throws -> Answer {
        if failNext {
            failNext = false
            throw APIError.invalidResponse
        }
        guard holdNext else { return value }
        holdNext = false
        let answer = await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Answer, Never>) in
                held = continuation
                heldWaiters.forEach { $0.resume() }
                heldWaiters = []
            }
        } onCancel: {
            Task { await self.release(with: .works([])) }
        }
        try Task.checkCancellation()
        return answer
    }

    func works(search: String?, page: Int) async throws -> PaginatedResponse<WorkSummary> {
        guard case let .works(titles) = try await answer(default: .works(["First"])) else {
            throw APIError.invalidResponse
        }
        let rows = titles.enumerated().map { index, title in
            #"{"id":"\#(UUID().uuidString)","slug":"w\#(index)","title":"\#(title)","editions_count":1}"#
        }
        return try Self.decode(
            #"{"count":\#(rows.count),"next":null,"previous":null,"results":[\#(rows.joined(separator: ","))]}"#
        )
    }

    func topics(parent: String?, search: String?, page: Int) async throws -> PaginatedResponse<TopicSummary> {
        _ = try await answer(default: .topics)
        return try Self.decode(#"""
        {"count":1,"next":null,"previous":null,"results":[
          {"id":"11111111-0000-0000-0000-000000000001","name":"Поезія","slug":"poeziia","parent_slug":null,"work_count":4,"children":[]}
        ]}
        """#)
    }

    func periodicals(search: String?, page: Int) async throws -> PaginatedResponse<PeriodicalSummary> {
        _ = try await answer(default: .topics)
        return try Self.decode(#"""
        {"count":1,"next":null,"previous":null,"results":[
          {"id":"99999999-0000-0000-0000-000000000001","slug":"visnyk","name":"Вісник","issues_count":1,"works_count":1}
        ]}
        """#)
    }

    func work(identifier: String) async throws -> WorkSummary { throw APIError.invalidResponse }
    func editions(workID: UUID) async throws -> [EditionSummary] { [] }

    private static func decode<Value: Decodable>(_ json: String) throws -> Value {
        try JSONDecoder().decode(Value.self, from: Data(json.utf8))
    }
}
