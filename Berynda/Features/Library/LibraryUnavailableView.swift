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
    @State private var unsaveError: String?

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
                        }
                    } label: {
                        HStack {
                            Text(list.title)
                            Spacer()
                            Text("\(list.workCount)").foregroundStyle(BeryndaColor.mutedInk)
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
        .alert("Колекція", isPresented: Binding(
            get: { unsaveError != nil },
            set: { if !$0 { unsaveError = nil } }
        )) {
            Button("Гаразд", role: .cancel) {}
        } message: {
            Text(unsaveError ?? "")
        }
    }

    private func unsaveButton(for collection: PublicCollectionSummary) -> some View {
        Button("Прибрати", systemImage: "bookmark.slash", role: .destructive) {
            Task {
                let result = await model.setCollectionSaved(collection, saved: false)
                if case let .failed(message) = result { unsaveError = message }
            }
        }
        .disabled(model.isMutating)
        .accessibilityIdentifier("library.collection.unsave.\(collection.slug)")
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
                        .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
        }
    }
}
