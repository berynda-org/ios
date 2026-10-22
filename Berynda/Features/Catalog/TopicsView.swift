import BeryndaCore
import SwiftUI

/// «Теми»: the root topics, or a search across every topic. Each row opens
/// the topic page, where its subtopics and works are listed.
struct TopicListView: View {
    @EnvironmentObject private var environment: AppEnvironment
    private let readableOnly: Bool

    init(readableOnly: Bool = false) {
        self.readableOnly = readableOnly
    }

    var body: some View {
        TopicListContent(repository: environment.catalogRepository, readableOnly: readableOnly)
    }
}

private struct TopicListContent: View {
    @StateObject private var model: TopicListViewModel
    private let repository: any CatalogRepository
    private let readableOnly: Bool

    init(repository: any CatalogRepository, readableOnly: Bool) {
        self.repository = repository
        self.readableOnly = readableOnly
        _model = StateObject(wrappedValue: TopicListViewModel(repository: repository))
    }

    var body: some View {
        Group {
            switch model.state {
            case .loading:
                BeryndaLoadingState(message: "Завантажуємо теми…")
            case let .failed(message):
                BeryndaErrorState(title: "Не вдалося завантажити теми", message: message) {
                    Task { await model.load() }
                }
            case .loaded where model.topics.isEmpty:
                BeryndaEmptyState(
                    title: "Тем не знайдено",
                    message: model.isSearching ? "Спробуйте інший запит." : "Теми ще не додано.",
                    systemImage: "square.grid.2x2"
                )
            case .loaded:
                List {
                    ForEach(model.topics) { topic in
                        NavigationLink {
                            TopicView(reference: topic.reference, readableOnly: readableOnly, repository: repository)
                        } label: {
                            TopicRow(
                                name: topic.name,
                                detail: detail(for: topic)
                            )
                        }
                        .accessibilityIdentifier("topics.topic.\(topic.slug)")
                        .task { await model.loadNextPage(after: topic) }
                    }
                    if model.isLoadingNextPage {
                        ProgressView("Завантажуємо ще…").frame(maxWidth: .infinity)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .refreshable { await model.load() }
            }
        }
        .accessibilityIdentifier("topics.screen")
        .background(BeryndaColor.paper)
        .navigationTitle("Теми")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $model.query, prompt: "Назва теми")
        .onChange(of: model.query) { _, _ in model.searchChanged() }
        .task { if case .loading = model.state { await model.load() } }
    }

    /// While searching, a subtopic is placed by its parent; otherwise a root
    /// says how much is inside it.
    private func detail(for topic: TopicSummary) -> String? {
        if model.isSearching, let parent = topic.parentName, !parent.isEmpty {
            return parent
        }
        var parts: [String] = []
        if let count = topic.workCount, count > 0 { parts.append(Self.worksLabel(count)) }
        if !topic.children.isEmpty { parts.append(Self.subtopicsLabel(topic.children.count)) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    static func worksLabel(_ count: Int) -> String {
        L("\(count) творів")
    }

    private static func subtopicsLabel(_ count: Int) -> String {
        L("\(count) підтем")
    }
}

/// A topic's page: what it is, its subtopics, and its works under the
/// reader's own readable switch.
struct TopicView: View {
    @StateObject private var model: TopicViewModel
    private let repository: any CatalogRepository

    init(reference: TopicReference, readableOnly: Bool = false, repository: any CatalogRepository) {
        self.repository = repository
        _model = StateObject(
            wrappedValue: TopicViewModel(reference: reference, readableOnly: readableOnly, repository: repository)
        )
    }

    var body: some View {
        Group {
            if model.isLoading && model.works.isEmpty {
                BeryndaLoadingState(message: "Завантажуємо тему…")
            } else if let message = model.errorMessage {
                BeryndaErrorState(title: "Не вдалося завантажити тему", message: message) {
                    Task { await model.load() }
                }
            } else {
                List {
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(model.title)
                                .font(.system(.title, design: .serif, weight: .bold))
                                .foregroundStyle(BeryndaColor.ink)
                                .accessibilityIdentifier("topic.name")
                                .accessibilityAddTraits(.isHeader)
                            if let parent = model.topic?.parentName, !parent.isEmpty {
                                Text(parent)
                                    .font(.subheadline)
                                    .foregroundStyle(BeryndaColor.mutedInk)
                            }
                            if let years = yearsLabel {
                                Text(years)
                                    .font(.subheadline)
                                    .foregroundStyle(BeryndaColor.mutedInk)
                            }
                            if let description = model.topic?.description?.trimmingCharacters(in: .whitespacesAndNewlines),
                               !description.isEmpty {
                                Text(description).font(.body)
                            }
                        }
                        .padding(.vertical, 8)
                    }

                    if let children = model.topic?.children, !children.isEmpty {
                        Section("Підтеми") {
                            ForEach(children) { child in
                                NavigationLink {
                                    TopicView(
                                        reference: child.reference,
                                        readableOnly: model.readableOnly,
                                        repository: repository
                                    )
                                } label: {
                                    Text(child.name)
                                }
                                .accessibilityIdentifier("topic.child.\(child.slug)")
                            }
                        }
                    }

                    Section("Твори · \(model.totalCount.formatted())") {
                        if model.works.isEmpty {
                            (model.readableOnly
                                 ? Text("Наразі немає творів, доступних для читання.")
                                 : Text("У цій темі ще немає творів."))
                                .foregroundStyle(BeryndaColor.mutedInk)
                        }
                        ForEach(model.works) { work in
                            NavigationLink {
                                WorkDetailView(work: work, repository: repository)
                            } label: {
                                WorkRow(work: work)
                            }
                            .accessibilityIdentifier("topic.work.\(work.id)")
                            .task { await model.loadNextPage(after: work) }
                        }
                        if model.isLoadingNextPage { ProgressView("Завантажуємо ще…") }
                        if model.nextPageError != nil {
                            Button("Спробувати завантажити ще раз") {
                                Task { await model.retryNextPage() }
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .refreshable { await model.load() }
            }
        }
        .accessibilityIdentifier("topic.screen")
        .background(BeryndaColor.paper)
        .navigationTitle("Тема")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .top, spacing: 0) {
            CatalogReadingFilter(readableOnly: $model.readableOnly)
        }
        .task(id: model.readableOnly) { await model.load() }
    }

    private var yearsLabel: String? {
        switch (model.topic?.yearMin, model.topic?.yearMax) {
        case let (from?, to?): from == to ? String(from) : "\(String(from))–\(String(to))"
        default: nil
        }
    }
}

/// A topic on the work page, opening the topic's own page.
struct TopicLink: View {
    @EnvironmentObject private var environment: AppEnvironment
    let reference: TopicReference

    var body: some View {
        NavigationLink {
            TopicView(reference: reference, repository: environment.catalogRepository)
        } label: {
            Text(reference.name)
                .foregroundStyle(BeryndaColor.accent)
                .multilineTextAlignment(.trailing)
        }
        .accessibilityIdentifier("work.topic.\(reference.slug)")
    }
}

private struct TopicRow: View {
    let name: String
    let detail: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(name)
                .font(.headline)
                .foregroundStyle(BeryndaColor.ink)
            if let detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(BeryndaColor.mutedInk)
            }
        }
        .padding(.vertical, 4)
    }
}

/// Ukrainian count agreement: 1 твір, 2–4 твори, 5+ творів (11–14 always many).
enum UkrainianPlural {
    static func form(_ count: Int, one: String, few: String, many: String) -> String {
        let lastTwo = abs(count) % 100
        let last = abs(count) % 10
        if (11...14).contains(lastTwo) { return many }
        switch last {
        case 1: return one
        case 2...4: return few
        default: return many
        }
    }
}
