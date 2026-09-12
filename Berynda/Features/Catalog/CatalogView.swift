import BeryndaCore
import SwiftUI

struct CatalogView: View {
    @EnvironmentObject private var environment: AppEnvironment

    var body: some View {
        CatalogLoadedView(
            repository: environment.catalogRepository,
            recentlyViewed: environment.recentlyViewed
        )
    }
}

private struct CatalogLoadedView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @StateObject private var model: CatalogViewModel

    init(repository: any CatalogRepository, recentlyViewed: RecentlyViewedStore) {
        _model = StateObject(
            wrappedValue: CatalogViewModel(
                repository: repository,
                recentlyViewed: recentlyViewed
            )
        )
    }

    var body: some View {
        Group {
            switch model.state {
            case .idle, .loading:
                BeryndaLoadingState(message: "Завантажуємо каталог…")
            case let .loaded(works, _) where works.isEmpty:
                BeryndaEmptyState(
                    title: "Нічого не знайдено",
                    message: model.query.isEmpty
                        ? "У каталозі поки немає доступних творів."
                        : "Спробуйте скоротити або змінити запит.",
                    systemImage: "text.magnifyingglass"
                )
            case let .loaded(works, totalCount):
                WorkList(
                    works: works,
                    totalCount: totalCount,
                    collections: model.query.isEmpty ? environment.library.publicCollections : [],
                    model: model
                )
            case let .failed(message):
                BeryndaErrorState(
                    title: "Не вдалося завантажити",
                    message: message,
                    retry: { Task { await model.load() } }
                )
            case let .offlineFallback(recent):
                RecentlyViewedList(works: recent) {
                    Task { await model.load() }
                }
            }
        }
            .background(BeryndaColor.paper)
            .navigationTitle("Каталог")
            .searchable(text: $model.query, prompt: "Назва або автор")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu("Фільтри", systemImage: "line.3.horizontal.decrease.circle") {
                        Toggle("Лише доступні для читання", isOn: $model.readableOnly)
                        Picker("Мова", selection: $model.languageFilter) {
                            Text("Усі мови").tag(String?.none)
                            Text("Українська").tag(String?.some("uk"))
                            Text("English").tag(String?.some("en"))
                        }
                    }
                }
            }
            .accessibilityIdentifier("catalog_screen")
            .onChange(of: model.query) { _, _ in model.searchChanged() }
            .onChange(of: model.readableOnly) { _, _ in model.searchChanged() }
            .onChange(of: model.languageFilter) { _, _ in model.searchChanged() }
            .task {
                if case .idle = model.state { await model.load() }
                await model.loadRecommendedIfNeeded()
                if environment.library.publicCollections.isEmpty {
                    await environment.library.loadPublicCollections()
                }
            }
    }
}

struct TabletCatalogColumn: View {
    @StateObject private var model: CatalogViewModel
    @Binding var selection: CatalogDestination?

    init(
        repository: any CatalogRepository,
        recentlyViewed: RecentlyViewedStore,
        selection: Binding<CatalogDestination?>
    ) {
        _model = StateObject(
            wrappedValue: CatalogViewModel(
                repository: repository,
                recentlyViewed: recentlyViewed
            )
        )
        _selection = selection
    }

    var body: some View {
        Group {
            switch model.state {
            case .idle, .loading:
                BeryndaLoadingState(message: "Завантажуємо каталог…")
            case let .loaded(works, _) where works.isEmpty:
                BeryndaEmptyState(
                    title: "Нічого не знайдено",
                    message: "Спробуйте змінити запит або фільтри.",
                    systemImage: "text.magnifyingglass"
                )
            case let .loaded(works, _):
                List(works, selection: $selection) { work in
                    WorkRow(work: work)
                        .tag(CatalogDestination.work(work))
                        .task { await model.loadNextPageIfNeeded(after: work) }
                }
                .listStyle(.plain)
                .refreshable { await model.load() }
            case let .failed(message):
                BeryndaErrorState(
                    title: "Не вдалося завантажити",
                    message: message,
                    retry: { Task { await model.load() } }
                )
            case let .offlineFallback(recent):
                RecentlyViewedList(works: recent) {
                    Task { await model.load() }
                }
            }
        }
        .navigationTitle("Каталог")
        .searchable(text: $model.query, prompt: "Назва або автор")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu("Фільтри", systemImage: "line.3.horizontal.decrease.circle") {
                    Toggle("Лише доступні для читання", isOn: $model.readableOnly)
                    Picker("Мова", selection: $model.languageFilter) {
                        Text("Усі мови").tag(String?.none)
                        Text("Українська").tag(String?.some("uk"))
                        Text("English").tag(String?.some("en"))
                    }
                }
            }
        }
        .onChange(of: model.query) { _, _ in model.searchChanged() }
        .onChange(of: model.readableOnly) { _, _ in model.searchChanged() }
        .onChange(of: model.languageFilter) { _, _ in model.searchChanged() }
        // No recommended shelf here: the iPad master column is a narrow list
        // that does not render one, so fetching it would be a request whose
        // result is never shown.
        .task { if case .idle = model.state { await model.load() } }
    }
}

private struct WorkList: View {
    let works: [WorkSummary]
    let totalCount: Int
    let collections: [PublicCollectionSummary]
    @ObservedObject var model: CatalogViewModel

    var body: some View {
        List {
            if !collections.isEmpty {
                Section("Вибрані колекції") {
                    ForEach(collections.filter(\.isFeatured)) { collection in
                        CollectionShelf(collection: collection)
                    }
                }
            }
            // Only above an unfiltered catalog: a shelf that ignores the
            // reader's query would be noise next to their own search.
            if model.query.isEmpty, !model.recommended.isEmpty {
                Section("Рекомендовані") {
                    RecommendedShelf(works: model.recommended)
                }
            }
            Section {
                ForEach(works) { work in
                    NavigationLink(value: CatalogDestination.work(work)) {
                        WorkRow(work: work)
                    }
                    .accessibilityIdentifier("catalog.work.\(work.id)")
                    .task { await model.loadNextPageIfNeeded(after: work) }
                }
            } footer: {
                paginationFooter
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(BeryndaColor.paper)
        .refreshable { await model.load() }
        .accessibilityLabel("Каталог, показано \(works.count) із \(totalCount)")
    }

    @ViewBuilder
    private var paginationFooter: some View {
        if model.isLoadingNextPage {
            HStack {
                Spacer()
                ProgressView("Завантажуємо ще…")
                Spacer()
            }
            .padding(.vertical, BeryndaSpacing.standard)
        } else if let message = model.nextPageError {
            VStack(spacing: BeryndaSpacing.compact) {
                Text("Не вдалося завантажити наступні твори")
                    .font(.footnote.weight(.semibold))
                Text(message)
                    .font(.caption)
                    .foregroundStyle(BeryndaColor.mutedInk)
                    .multilineTextAlignment(.center)
                Button("Повторити") { Task { await model.retryNextPage() } }
                    .buttonStyle(.bordered)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, BeryndaSpacing.standard)
        } else if works.count < totalCount {
            Text("Показано \(works.count) із \(totalCount)")
                .font(.caption)
                .foregroundStyle(BeryndaColor.mutedInk)
                .frame(maxWidth: .infinity)
                .padding(.vertical, BeryndaSpacing.compact)
        }
    }
}

private struct CollectionShelf: View {
    @EnvironmentObject private var environment: AppEnvironment
    let collection: PublicCollectionSummary
    @State private var saveMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(collection.name).font(.headline)
                    if !collection.description.isEmpty {
                        Text(collection.description)
                            .font(.caption)
                            .foregroundStyle(BeryndaColor.mutedInk)
                            .lineLimit(2)
                    }
                }
                Spacer()
                CollectionSaveButton(library: environment.library, collection: collection) { result in
                    saveMessage = result.collectionMessage
                }
                .labelStyle(.iconOnly)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 14) {
                    ForEach(collection.featuredWorks) { work in
                        Button {
                            environment.catalogPath.append(.linkedWork(identifier: work.slug))
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                BeryndaBookCover(
                                    title: work.title,
                                    imageURL: nil,
                                    design: work.coverDesign,
                                    width: 64,
                                    height: 92
                                )
                                Text(work.title)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(BeryndaColor.ink)
                                    .lineLimit(2)
                                    .frame(width: 96, alignment: .leading)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(.vertical, 6)
        .alert("Колекція", isPresented: Binding(
            get: { saveMessage != nil },
            set: { if !$0 { saveMessage = nil } }
        )) {
            Button("Гаразд", role: .cancel) {}
        } message: { Text(saveMessage ?? "") }
    }
}

/// Shown when the catalog could not be reached at all. These rows carry only
/// what was stored on the device, so they route to the work and nothing more —
/// no availability or rights claims are made offline.
private struct RecentlyViewedList: View {
    @EnvironmentObject private var environment: AppEnvironment
    let works: [RecentlyViewedWork]
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Label("Немає з’єднання — показано нещодавно переглянуті", systemImage: "wifi.slash")
                    .font(.footnote)
                    .foregroundStyle(BeryndaColor.mutedInk)
                Spacer()
                Button("Оновити", action: retry)
                    .font(.footnote.weight(.semibold))
                    .accessibilityIdentifier("catalog.offline-retry")
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(BeryndaColor.surface)

            List(works) { work in
                Button {
                    environment.catalogPath.append(.linkedWork(identifier: work.slug))
                } label: {
                    HStack(alignment: .top, spacing: 14) {
                        BeryndaBookCover(
                            title: work.title,
                            imageURL: nil,
                            design: work.coverDesign
                        )
                        VStack(alignment: .leading, spacing: 5) {
                            Text(work.title)
                                .font(.headline)
                                .foregroundStyle(BeryndaColor.ink)
                            if !work.authorNames.isEmpty {
                                Text(work.authorNames.joined(separator: ", "))
                                    .font(.subheadline)
                                    .foregroundStyle(BeryndaColor.mutedInk)
                            }
                        }
                    }
                    .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("catalog.recent.\(work.id)")
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(BeryndaColor.paper)
        }
        .accessibilityIdentifier("catalog.offline-fallback")
    }
}

/// Horizontal shelf of server-ranked works.
///
/// Nothing here is personalised: the server ranks only the work, so this shows
/// every reader the same shelf and reveals nothing about what anyone has read.
private struct RecommendedShelf: View {
    let works: [WorkSummary]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(alignment: .top, spacing: 14) {
                ForEach(works) { work in
                    NavigationLink(value: CatalogDestination.work(work)) {
                        VStack(alignment: .leading, spacing: 6) {
                            BeryndaBookCover(
                                title: work.title,
                                imageURL: work.coverImageURL,
                                design: work.coverDesign,
                                width: 64,
                                height: 92
                            )
                            Text(work.title)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(BeryndaColor.ink)
                                .lineLimit(2)
                                .frame(width: 96, alignment: .leading)
                            if let author = work.authors.first?.displayName {
                                Text(author)
                                    .font(.caption2)
                                    .foregroundStyle(BeryndaColor.mutedInk)
                                    .lineLimit(1)
                                    .frame(width: 96, alignment: .leading)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("catalog.recommended.\(work.id)")
                }
            }
            .padding(.vertical, 4)
        }
        .accessibilityIdentifier("catalog.recommended")
    }
}

private struct WorkRow: View {
    let work: WorkSummary

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            BeryndaBookCover(
                title: work.title,
                imageURL: work.coverImageURL,
                design: work.coverDesign
            )

            VStack(alignment: .leading, spacing: 5) {
                Text(work.title)
                    .font(.headline)
                    .foregroundStyle(BeryndaColor.ink)
                if !work.authors.isEmpty {
                    Text(work.authors.map(\.displayName).joined(separator: ", "))
                        .font(.subheadline)
                        .foregroundStyle(BeryndaColor.mutedInk)
                }
                Text(editionsLabel)
                    .font(.caption)
                    .foregroundStyle(BeryndaColor.mutedInk)
                if let rights = work.rightsClaim {
                    Label(rights.title, systemImage: rights.symbol)
                        .font(.caption2)
                        .foregroundStyle(BeryndaColor.accent)
                        .accessibilityIdentifier("catalog.rights.\(work.id)")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 6)
    }

    private var editionsLabel: String {
        switch work.editionsCount {
        case 0: "Бібліографічний запис"
        case 1: "1 видання"
        default: "\(work.editionsCount) видань"
        }
    }
}
