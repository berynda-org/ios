import BeryndaCore
import SwiftUI

struct LibraryView: View {
    @EnvironmentObject private var environment: AppEnvironment

    var body: some View {
        LibraryContent(model: environment.library)
        .navigationTitle("Бібліотека")
        .accessibilityIdentifier("library_screen")
    }
}

private struct LibraryContent: View {
    @EnvironmentObject private var environment: AppEnvironment
    @ObservedObject var model: LibraryViewModel
    @ObservedObject private var account: AccountViewModel
    @State private var showsNewList = false
    @State private var renamingList: BibliographyList?
    @State private var deletingList: BibliographyList?
    @State private var failure: LibraryFailure?

    init(model: LibraryViewModel) {
        self.model = model
        _account = ObservedObject(wrappedValue: model.accountForObservation)
    }

    var body: some View {
        Group {
            switch model.state {
            case .signedOut:
                BeryndaEmptyState(
                    title: "Увійдіть до бібліотеки",
                    message: "Після входу тут з’являться продовження читання, списки та збережені колекції.",
                    systemImage: "bookmark"
                )
                .overlay(alignment: .bottom) {
                    Button("Перейти до профілю") { environment.selectedTab = .profile }
                        .buttonStyle(.borderedProminent)
                        .padding(.bottom, 48)
                }
            case .loading:
                BeryndaLoadingState(message: "Завантажуємо бібліотеку…")
            case let .failed(message):
                BeryndaErrorState(
                    title: "Не вдалося завантажити бібліотеку",
                    message: message,
                    retry: { Task { await model.load() } }
                )
            case let .loaded(recent, lists, saved):
                loadedContent(recent: recent, lists: lists, saved: saved)
            }
        }
        .background(BeryndaColor.paper)
        .toolbar {
            if account.state == .authenticated {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Новий список", systemImage: "plus") { showsNewList = true }
                }
            }
        }
        .sheet(isPresented: $showsNewList) { NewListView(model: model) }
        // Presented from here rather than from the list itself, which is
        // swapped out whenever the library leaves its loaded state.
        .sheet(item: $renamingList) { list in RenameListView(model: model, list: list) }
        .confirmationDialog(
            deletingList.map { "Видалити список «\($0.title)»?" } ?? "Видалити список?",
            isPresented: Binding(
                get: { deletingList != nil },
                set: { if !$0 { deletingList = nil } }
            ),
            titleVisibility: .visible,
            presenting: deletingList
        ) { list in
            Button("Видалити", role: .destructive) {
                Task { await delete(list) }
            }
            .accessibilityIdentifier("library.list.delete.confirm.\(Self.identifier(list.id))")
            Button("Скасувати", role: .cancel) {}
        } message: { _ in
            Text("Список і всі записи в ньому буде видалено. Цю дію не можна скасувати.")
        }
        .alert(
            failure?.title ?? "",
            isPresented: Binding(
                get: { failure != nil },
                set: { if !$0 { failure = nil } }
            )
        ) {
            Button("Гаразд", role: .cancel) {}
        } message: {
            Text(failure?.message ?? "")
        }
        .task { await model.load() }
        .onChange(of: account.state) { _, _ in Task { await model.load() } }
    }

    private func loadedContent(
        recent: ContinueReadingResponse,
        lists: [BibliographyList],
        saved: [PublicCollectionSummary]
    ) -> some View {
        List {
            Section("Продовжити читання") {
                if !recent.historyEnabled {
                    Label("Історію читання вимкнено в профілі", systemImage: "eye.slash")
                        .foregroundStyle(BeryndaColor.mutedInk)
                } else if recent.recentlyRead.isEmpty {
                    Text("Відкрийте видання — воно з’явиться тут.")
                        .foregroundStyle(BeryndaColor.mutedInk)
                } else {
                    ForEach(recent.recentlyRead) { item in
                        Button {
                            environment.presentReader(
                                fileID: item.fileID,
                                fallbackTitle: item.workTitle ?? "Видання",
                                initialPage: item.positionType == "page" ? Int(item.positionValue) : nil
                            )
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.workTitle ?? "Видання").foregroundStyle(BeryndaColor.ink)
                                if let progress = item.progressPercent {
                                    ProgressView(value: Double(progress), total: 100)
                                        .accessibilityLabel("Прочитано \(progress) відсотків")
                                }
                            }
                        }
                    }
                }
            }

            Section("Бібліографічні списки") {
                if lists.isEmpty {
                    Text("Списків ще немає.").foregroundStyle(BeryndaColor.mutedInk)
                }
                ForEach(lists) { list in
                    DisclosureGroup {
                        if list.items.isEmpty {
                            Text("Список порожній").foregroundStyle(BeryndaColor.mutedInk)
                        }
                        ForEach(list.items) { item in
                            Button {
                                if let fileID = item.file {
                                    environment.presentReader(
                                        fileID: fileID,
                                        fallbackTitle: item.workTitle ?? list.title,
                                        initialPage: item.pageNumber
                                    )
                                } else if let slug = item.workSlug {
                                    environment.selectedTab = .catalog
                                    environment.catalogPath = [.linkedWork(identifier: slug)]
                                }
                            } label: {
                                Text(item.workTitle ?? item.editionTitle ?? "Запис")
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                removeItemButton(item, from: list)
                            }
                            .contextMenu {
                                removeItemButton(item, from: list)
                            }
                        }
                    } label: {
                        HStack {
                            Text(list.title)
                            Spacer()
                            Text("\(list.workCount)").foregroundStyle(BeryndaColor.mutedInk)
                            // A visible way in: a long press alone is easy to
                            // miss.
                            Menu {
                                listActions(for: list)
                            } label: {
                                Image(systemName: "ellipsis.circle")
                                    .foregroundStyle(BeryndaColor.accent)
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Дії зі списком «\(list.title)»")
                            .accessibilityIdentifier("library.list.actions.\(Self.identifier(list.id))")
                        }
                        .contentShape(Rectangle())
                        .contextMenu {
                            listActions(for: list)
                        }
                    }
                }
            }

            Section("Збережені колекції") {
                if saved.isEmpty {
                    Text("Збережених колекцій ще немає.")
                        .foregroundStyle(BeryndaColor.mutedInk)
                }
                ForEach(saved) { collection in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(collection.name)
                        Text("\(collection.workCount) творів")
                            .font(.caption)
                            .foregroundStyle(BeryndaColor.mutedInk)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .accessibilityIdentifier("library.collection.\(collection.slug)")
                    // Saving is offered on the catalog; this list is the only
                    // place the reader can take a collection back out.
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        unsaveButton(for: collection)
                    }
                    .contextMenu {
                        unsaveButton(for: collection)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .refreshable { await model.load() }
    }

    @ViewBuilder
    private func listActions(for list: BibliographyList) -> some View {
        Button("Перейменувати", systemImage: "pencil") { renamingList = list }
            .disabled(model.isMutating)
            .accessibilityIdentifier("library.list.rename.\(Self.identifier(list.id))")
        Button("Видалити список", systemImage: "trash", role: .destructive) { deletingList = list }
            .disabled(model.isMutating)
            .accessibilityIdentifier("library.list.delete.\(Self.identifier(list.id))")
    }

    private func removeItemButton(_ item: BibliographyItem, from list: BibliographyList) -> some View {
        Button("Прибрати", systemImage: "minus.circle", role: .destructive) {
            Task {
                let result = await model.removeItem(listID: list.id, itemID: item.id)
                report(result, title: "Бібліографічний список")
            }
        }
        .disabled(model.isMutating)
        .accessibilityIdentifier("library.item.remove.\(Self.identifier(item.id))")
    }

    private func unsaveButton(for collection: PublicCollectionSummary) -> some View {
        Button("Прибрати", systemImage: "bookmark.slash", role: .destructive) {
            Task {
                let result = await model.setCollectionSaved(collection, saved: false)
                if case let .failed(message) = result {
                    failure = LibraryFailure(title: "Колекція", message: message)
                }
            }
        }
        .disabled(model.isMutating)
        .accessibilityIdentifier("library.collection.unsave.\(collection.slug)")
    }

    private func delete(_ list: BibliographyList) async {
        let result = await model.deleteList(id: list.id)
        report(result, title: "Бібліографічний список")
    }

    private func report(_ result: LibraryViewModel.SaveResult, title: String) {
        guard let message = result.listEditFailure else { return }
        failure = LibraryFailure(title: title, message: message)
    }

    /// Ids appear lower-cased, as they do in the API paths.
    private static func identifier(_ id: UUID) -> String {
        id.uuidString.lowercased()
    }
}

private struct LibraryFailure {
    let title: String
    let message: String
}

private extension LibraryViewModel.SaveResult {
    /// What to tell the reader when an edit to a list did not go through;
    /// nil when it did.
    var listEditFailure: String? {
        switch self {
        case .saved, .removed, .alreadySaved:
            return nil
        case .inProgress:
            return "Інша зміна бібліотеки ще виконується. Спробуйте ще раз."
        case .signInRequired:
            return "Сеанс завершився. Увійдіть у профілі й повторіть дію."
        case let .failed(message):
            return message
        }
    }
}

private struct NewListView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var model: LibraryViewModel
    @State private var title = ""

    var body: some View {
        NavigationStack {
            Form { TextField("Назва списку", text: $title) }
                .navigationTitle("Новий список")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Скасувати") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Створити") {
                            Task { if await model.createList(title: title) { dismiss() } }
                        }
                        .disabled(LibraryViewModel.validListTitle(title) == nil)
                    }
                }
        }
    }
}

private struct RenameListView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var model: LibraryViewModel
    private let list: BibliographyList
    @State private var title: String
    @State private var error: String?

    init(model: LibraryViewModel, list: BibliographyList) {
        _model = ObservedObject(wrappedValue: model)
        self.list = list
        _title = State(initialValue: list.title)
    }

    private var cleanTitle: String? { LibraryViewModel.validListTitle(title) }

    private var isTooLong: Bool {
        title.trimmingCharacters(in: .whitespacesAndNewlines).unicodeScalars.count
            > LibraryViewModel.maximumListTitleLength
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Назва списку", text: $title)
                        .accessibilityIdentifier("library.list.rename.field")
                } footer: {
                    if let error {
                        Text(error).foregroundStyle(.red)
                    } else if isTooLong {
                        Text("Назва не може бути довшою за \(LibraryViewModel.maximumListTitleLength) символів.")
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Перейменувати список")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Скасувати") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Зберегти") {
                        Task { await save() }
                    }
                    .disabled(cleanTitle == nil || cleanTitle == list.title || model.isMutating)
                    .accessibilityIdentifier("library.list.rename.save")
                }
            }
            .onChange(of: title) { _, _ in error = nil }
        }
    }

    private func save() async {
        let result = await model.renameList(id: list.id, title: title)
        if let message = result.listEditFailure {
            error = message
        } else {
            dismiss()
        }
    }
}
