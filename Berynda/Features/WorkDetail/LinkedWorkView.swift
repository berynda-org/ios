import BeryndaCore
import Combine
import SwiftUI

struct LinkedWorkView: View {
    @StateObject private var model: LinkedWorkViewModel
    private let repository: any CatalogRepository

    init(identifier: String, repository: any CatalogRepository) {
        self.repository = repository
        _model = StateObject(
            wrappedValue: LinkedWorkViewModel(
                identifier: identifier,
                repository: repository
            )
        )
    }

    var body: some View {
        Group {
            switch model.state {
            case .loading:
                ProgressView("Відкриваємо твір…")
            case let .loaded(work):
                WorkDetailView(work: work, repository: repository)
            case let .failed(message):
                ContentUnavailableView {
                    Label("Твір недоступний", systemImage: "book.closed")
                } description: {
                    Text(message)
                } actions: {
                    Button("Спробувати ще раз") {
                        Task { await model.load() }
                    }
                }
            }
        }
        .task { await model.loadIfNeeded() }
        .accessibilityIdentifier("linked-work.\(model.identifier)")
    }
}

@MainActor
private final class LinkedWorkViewModel: ObservableObject {
    enum State {
        case loading
        case loaded(WorkSummary)
        case failed(String)
    }

    @Published private(set) var state: State = .loading
    let identifier: String
    private let repository: any CatalogRepository
    private var hasLoaded = false

    init(identifier: String, repository: any CatalogRepository) {
        self.identifier = identifier
        self.repository = repository
    }

    func loadIfNeeded() async {
        guard !hasLoaded else { return }
        await load()
    }

    func load() async {
        hasLoaded = true
        state = .loading
        do {
            state = .loaded(try await repository.work(identifier: identifier))
        } catch is CancellationError {
            return
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}
