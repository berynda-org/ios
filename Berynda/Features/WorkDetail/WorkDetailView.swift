import BeryndaCore
import SwiftUI

struct WorkDetailView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @StateObject private var model: WorkDetailViewModel
    @State private var saveMessage: String?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(work: WorkSummary, repository: any CatalogRepository) {
        _model = StateObject(
            wrappedValue: WorkDetailViewModel(work: work, repository: repository)
        )
    }

    private var work: WorkSummary { model.work }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                header
                summaryText
                BibliographyPanel(work: work, isEnriching: model.isEnriching)
                if !model.periodicalLinks.isEmpty {
                    PublishedInPanel(links: model.periodicalLinks)
                }
                RightsPanel(work: work)
                if !model.collections.isEmpty {
                    CollectionsPanel(collections: model.collections)
                }

                Text("Видання")
                    .font(.title2.bold())
                    .accessibilityAddTraits(.isHeader)

                editionsSection
            }
            .padding(20)
        }
        .background(BeryndaColor.paper)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                AddToListControl(library: environment.library, workID: work.id) { result in
                    if result == .signInRequired {
                        environment.requireAuthentication(for: .addWork(work.id))
                    } else {
                        saveMessage = result.message
                    }
                }
            }
        }
        .task { await environment.library.loadIfNeeded() }
        .alert("Бібліотека", isPresented: Binding(
            get: { saveMessage != nil },
            set: { if !$0 { saveMessage = nil } }
        )) {
            Button("Гаразд", role: .cancel) {}
        } message: {
            Text(saveMessage ?? "")
        }
        .task { await model.load() }
        .task {
            // Reading history is a privacy setting, so a reader who turned it
            // off leaves no trace here either.
            guard environment.account.profile?.readingHistoryEnabled != false else {
                await environment.recentlyViewed.clear()
                return
            }
            await environment.recentlyViewed.record(work)
        }
    }

    private var linkedAuthors: [WorkAuthor] {
        var seen = Set<UUID>()
        return work.authors.filter { seen.insert($0.id).inserted }
    }

    /// Side by side normally; at the accessibility text sizes the title gets
    /// the full width under the cover instead of a narrow column beside it.
    private var headerLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: BeryndaSpacing.standard))
            : AnyLayout(HStackLayout(alignment: .top, spacing: BeryndaSpacing.standard))
    }

    private var header: some View {
        headerLayout {
            BeryndaBookCover(
                title: work.title,
                imageURL: work.coverImageURL,
                design: work.coverDesign,
                width: 88,
                height: 128
            )

            VStack(alignment: .leading, spacing: 8) {
                Text(work.title)
                    .font(.system(.largeTitle, design: .serif, weight: .bold))
                    .foregroundStyle(BeryndaColor.ink)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("work.title")
                if let subtitle = work.subtitle {
                    Text(subtitle).font(.title3).foregroundStyle(BeryndaColor.mutedInk)
                }
                if !work.authors.isEmpty {
                    ForEach(linkedAuthors) { author in
                        AuthorLink(id: author.id, name: author.displayName)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// The catalog description, falling back to the scholarly abstract when a
    /// work has only the latter.
    @ViewBuilder
    private var summaryText: some View {
        if let text = work.description?.nilIfBlank ?? work.abstract?.nilIfBlank {
            Text(text)
                .font(.body)
                .foregroundStyle(BeryndaColor.ink)
        }
    }

    @ViewBuilder
    private var editionsSection: some View {
        switch model.editions {
        case .loading:
            BeryndaLoadingState(message: "Завантажуємо видання…")
                .frame(minHeight: 180)
        case let .loaded(editions) where editions.isEmpty:
            BeryndaEmptyState(
                title: "Видань ще немає",
                message: work.editionsCount > 0
                    ? "Видання цього твору зараз недоступні."
                    : "Для цього твору поки немає окремого видання.",
                systemImage: "books.vertical"
            )
            .accessibilityIdentifier("work.editions-empty")
        case let .loaded(editions):
            ForEach(editions) { edition in
                EditionRow(edition: edition) { fileID in
                    environment.presentReader(
                        fileID: fileID,
                        fallbackTitle: edition.displayTitle
                    )
                }
            }
        case let .failed(message):
            BeryndaErrorState(
                title: "Не вдалося завантажити видання",
                message: message,
                retry: { Task { await model.loadEditions() } }
            )
            .frame(minHeight: 240)
            .accessibilityIdentifier("work.editions-error")
        }
    }
}

extension LibraryViewModel.SaveResult {
    var message: String {
        switch self {
        case .saved: L("Додано до бібліографічного списку.")
        case .removed: L("Прибрано з бібліотеки.")
        case .alreadySaved: L("Цей твір уже є у вашому списку.")
        case .inProgress: L("Збереження вже виконується.")
        case .signInRequired: L("Увійдіть у профілі, щоб зберігати твори.")
        case .queued: Self.queuedMessage
        case let .failed(message): message
        }
    }
}

// MARK: - Bibliography

private struct BibliographyPanel: View {
    let work: WorkSummary
    let isEnriching: Bool
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// Label and value side by side, or stacked at the accessibility text
    /// sizes, where two columns would leave a word per line.
    private var rowLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 12))
    }

    private var isStacked: Bool { dynamicTypeSize.isAccessibilitySize }

    var body: some View {
        BeryndaPanel {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("Бібліографічні відомості", systemImage: "text.book.closed")
                        .font(.headline)
                        .accessibilityAddTraits(.isHeader)
                    Spacer()
                    if isEnriching {
                        ProgressView()
                            .controlSize(.small)
                            .accessibilityLabel("Завантажуємо відомості")
                    }
                }

                ForEach(work.contributorsByRole) { entry in
                    detailRow(
                        Self.roleLabel(entry.role, count: entry.names.count),
                        key: entry.role,
                        value: entry.names.joined(separator: ", ")
                    )
                }

                detailRow(L("Оригінальна назва"), key: "original-title", value: originalTitle)
                detailRow(L("Вид"), key: "kind", value: kindLabel)
                detailRow(L("Мова"), key: "language", value: languageLabel)
                detailRow(
                    L("Перша публікація"),
                    key: "first-published",
                    value: work.firstPublishedYear.map(String.init)
                )
                detailRow(L("Обсяг"), key: "extent", value: work.pages.map { L("\($0) с.") })
                topicsRow
                detailRow(
                    L("Жанри"),
                    key: "genres",
                    value: work.genres.map { $0.name }.joined(separator: ", ")
                )
            }
        }
    }

    /// Two plain `Text`s rather than `LabeledContent`, which merges its label
    /// and value into a single accessibility element and so leaves neither
    /// half queryable. The value carries a stable identifier so tests assert
    /// on structure rather than on Ukrainian display strings.
    @ViewBuilder
    private func detailRow(_ label: String, key: String, value: String?) -> some View {
        if let value, !value.isEmpty {
            rowLayout {
                Text(label)
                    .foregroundStyle(BeryndaColor.mutedInk)
                if !isStacked { Spacer(minLength: 12) }
                Text(value)
                    .foregroundStyle(BeryndaColor.ink)
                    .multilineTextAlignment(isStacked ? .leading : .trailing)
                    .accessibilityIdentifier("work.bibliography.\(key)")
            }
            .font(.subheadline)
        }
    }

    /// Each topic with a slug opens its topic page; one without (an older
    /// API) is still listed, just not as a link.
    @ViewBuilder
    private var topicsRow: some View {
        if !work.topics.isEmpty {
            rowLayout {
                Text("Тематика")
                    .foregroundStyle(BeryndaColor.mutedInk)
                if !isStacked { Spacer(minLength: 12) }
                VStack(alignment: isStacked ? .leading : .trailing, spacing: 6) {
                    ForEach(work.topics) { topic in
                        if let slug = topic.slug {
                            TopicLink(reference: TopicReference(slug: slug, name: topic.name))
                        } else {
                            Text(topic.name)
                                .foregroundStyle(BeryndaColor.ink)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                }
            }
            .font(.subheadline)
        }
    }

    /// Only worth a row when it actually differs from the displayed title.
    private var originalTitle: String? {
        guard let original = work.originalTitle?.nilIfBlank, original != work.title else {
            return nil
        }
        return original
    }

    /// The literary form is what identifies a work; `work_type` is only its
    /// carrier, and «книга» says nothing about the work itself.
    private var kindLabel: String? {
        var parts: [String] = []
        if let form = work.literaryForm?.name { parts.append(form) }
        if work.isCollection { parts.append(L("збірка")) }
        if parts.isEmpty, let workType = work.workType?.nilIfBlank {
            parts.append(workType)
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private var languageLabel: String? {
        let all = ([work.language] + work.additionalLanguages.map { Optional($0) })
            .compactMap { $0?.nilIfBlank }
            .map { $0.uppercased() }
        var seen = Set<String>()
        let unique = all.filter { seen.insert($0).inserted }
        return unique.isEmpty ? nil : unique.joined(separator: ", ")
    }

    static func roleLabel(_ role: String, count: Int) -> String {
        switch role {
        case "author": count == 1 ? L("Автор") : L("Автори")
        case "translator": L("Переклад")
        case "compiler": count == 1 ? L("Упорядник") : L("Упорядники")
        case "editor": count == 1 ? L("Редактор") : L("Редактори")
        case "illustrator": L("Ілюстрації")
        default: role
        }
    }
}

// MARK: - Collections

/// The public collections a work appears in.
///
/// Names only, with the save action the catalog shelves already offer. There
/// is no collection screen in the app yet, so tapping a row would have to lead
/// nowhere — better to show the membership plainly than to imply navigation
/// that does not exist.
private struct CollectionsPanel: View {
    @EnvironmentObject private var environment: AppEnvironment
    let collections: [PublicCollectionSummary]
    @State private var message: String?

    var body: some View {
        BeryndaPanel {
            VStack(alignment: .leading, spacing: 10) {
                Label("У колекціях", systemImage: "square.stack")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                    .foregroundStyle(BeryndaColor.ink)

                ForEach(collections) { collection in
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(collection.name)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(BeryndaColor.ink)
                            if !collection.description.isEmpty {
                                Text(collection.description)
                                    .font(.caption)
                                    .foregroundStyle(BeryndaColor.mutedInk)
                                    .lineLimit(2)
                            }
                        }
                        Spacer(minLength: 12)
                        CollectionSaveButton(
                            library: environment.library,
                            collection: collection
                        ) { result in
                            message = result.collectionMessage
                        }
                        .font(.footnote.weight(.semibold))
                    }
                    .accessibilityIdentifier("work.collection.\(collection.slug)")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .alert("Колекція", isPresented: Binding(
            get: { message != nil },
            set: { if !$0 { message = nil } }
        )) {
            Button("Гаразд", role: .cancel) {}
        } message: {
            Text(message ?? "")
        }
    }
}

// MARK: - Rights

private struct RightsPanel: View {
    let work: WorkSummary

    var body: some View {
        if let summary = work.rightsClaim {
            BeryndaPanel {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Image(systemName: summary.symbol)
                            .accessibilityHidden(true)
                        Text(summary.title)
                            .accessibilityAddTraits(.isHeader)
                            .accessibilityIdentifier("work.rights.title")
                    }
                    .font(.headline)
                    .foregroundStyle(BeryndaColor.ink)
                    Text(summary.explanation)
                        .font(.subheadline)
                        .foregroundStyle(BeryndaColor.mutedInk)
                        .accessibilityIdentifier("work.rights.explanation")
                    Text("Доступність окремих файлів визначається для кожного видання окремо.")
                        .font(.caption)
                        .foregroundStyle(BeryndaColor.mutedInk)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

// MARK: - Editions

private struct EditionRow: View {
    @EnvironmentObject private var environment: AppEnvironment
    let edition: EditionSummary
    let onRead: (UUID) -> Void

    var body: some View {
        BeryndaPanel {
            VStack(alignment: .leading, spacing: 8) {
                // One VoiceOver stop for the edition ("title, year · publisher,
                // pages"), then its read or restriction line on its own.
                VStack(alignment: .leading, spacing: 8) {
                    Text(edition.displayTitle)
                        .font(.headline)
                        .foregroundStyle(BeryndaColor.ink)
                    if !metadata.isEmpty {
                        Text(metadata)
                            .font(.subheadline)
                            .foregroundStyle(BeryndaColor.mutedInk)
                    }
                    if let extent {
                        Text(extent)
                            .font(.caption)
                            .foregroundStyle(BeryndaColor.mutedInk)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("work.edition.\(edition.id)")

                if let fileID = edition.readableFileID, edition.canRead {
                    Button {
                        onRead(fileID)
                    } label: {
                        Label("Читати видання", systemImage: "book.pages")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("edition.read.\(edition.id)")
                    if edition.canSaveOffline == true {
                        OfflineSaveControl(fileID: fileID, editionID: edition.id, offline: environment.offline)
                    }
                } else if edition.isAwaitingPages {
                    Label(
                        edition.restrictionReason ?? L("Сторінки ще готуються. Спробуйте трохи згодом."),
                        systemImage: "hourglass"
                    )
                    .font(.footnote)
                    .foregroundStyle(BeryndaColor.mutedInk)
                    .accessibilityIdentifier("edition.pages-not-ready.\(edition.id)")
                } else {
                    Label(
                        edition.restrictionReason ?? L("Файл для читання недоступний"),
                        systemImage: "lock"
                    )
                    .font(.footnote)
                    .foregroundStyle(BeryndaColor.mutedInk)
                    .accessibilityIdentifier("edition.restricted.\(edition.id)")
                }
            }
        }
    }

    private var metadata: String {
        [edition.year.map(String.init), edition.publisherName, edition.publicationPlace]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    private var extent: String? {
        let parts = [
            edition.pageCount.map { L("\($0) сторінок") },
            edition.language.nilIfBlank.map { $0.uppercased() },
        ].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

private extension String {
    var nilIfBlank: String? {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self
    }
}

/// "До списку" on a work page. With lists loaded it is a menu of them plus a
/// new list; without any (signed out, or no list yet) it quick-adds, which
/// signs the reader in or creates the server's default list.
private struct AddToListControl: View {
    @ObservedObject var library: LibraryViewModel
    let workID: UUID
    let onResult: (LibraryViewModel.SaveResult) -> Void
    @State private var asksNewListTitle = false
    @State private var newListTitle = ""

    var body: some View {
        Group {
            if library.lists.isEmpty {
                Button("До списку", systemImage: "bookmark") {
                    run { await library.quickAdd(workID: workID) }
                }
            } else {
                Menu {
                    Section("Додати до списку") {
                        ForEach(library.lists) { list in
                            Button(list.title) {
                                run { await library.addWork(workID, toList: list.id) }
                            }
                        }
                    }
                    Button("Новий список…", systemImage: "plus") {
                        newListTitle = ""
                        asksNewListTitle = true
                    }
                } label: {
                    Label("До списку", systemImage: "bookmark")
                }
            }
        }
        .disabled(library.isMutating)
        .accessibilityHint("Додає твір до бібліографічного списку")
        .accessibilityIdentifier("work.quick-add")
        .alert("Новий список", isPresented: $asksNewListTitle) {
            TextField("Назва списку", text: $newListTitle)
            Button("Створити") {
                let title = newListTitle
                run { await library.addWork(workID, toNewListTitled: title) }
            }
            Button("Скасувати", role: .cancel) {}
        }
    }

    private func run(_ action: @escaping () async -> LibraryViewModel.SaveResult) {
        Task { onResult(await action()) }
    }
}
