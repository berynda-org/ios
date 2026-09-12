import BeryndaCore
import SwiftUI

struct AuthorView: View {
    @StateObject private var model: AuthorViewModel
    private let fallbackName: String
    private let repository: any CatalogRepository

    init(id: UUID, name: String, repository: any CatalogRepository) {
        self.fallbackName = name
        self.repository = repository
        _model = StateObject(wrappedValue: AuthorViewModel(authorID: id, repository: repository))
    }

    var body: some View {
        Group {
            if model.isLoading {
                BeryndaLoadingState(message: "Завантажуємо автора…")
            } else if let message = model.errorMessage {
                BeryndaErrorState(title: "Не вдалося завантажити автора", message: message) {
                    Task { await model.load() }
                }
            } else {
                List {
                    Section {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(model.author?.displayName ?? fallbackName)
                                .font(.system(.largeTitle, design: .serif, weight: .bold))
                                .accessibilityIdentifier("author.name")
                            if let dates = model.author?.lifeDates {
                                Text(dates).foregroundStyle(BeryndaColor.mutedInk)
                            }
                            if let legalName = model.author?.legalName,
                               !legalName.isEmpty, legalName != model.author?.displayName {
                                Text(legalName).font(.subheadline)
                            }
                            if let biography = model.author?.biography, !biography.isEmpty {
                                Text(biography).font(.body)
                            }
                        }
                        .padding(.vertical, 8)
                    }
                    Section("Твори · \(model.totalCount)") {
                        if model.works.isEmpty {
                            Text(model.readableOnly
                                 ? "Наразі немає творів, доступних для читання."
                                 : "Твори цього автора ще не додано.")
                                .foregroundStyle(BeryndaColor.mutedInk)
                        }
                        ForEach(model.works) { work in
                            NavigationLink {
                                WorkDetailView(work: work, repository: repository)
                            } label: {
                                WorkRow(work: work)
                            }
                            .accessibilityIdentifier("author.work.\(work.id)")
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
        .accessibilityIdentifier("author.screen")
        .background(BeryndaColor.paper)
        .navigationTitle("Автор")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .top, spacing: 0) {
            CatalogReadingFilter(readableOnly: $model.readableOnly)
        }
        .task(id: model.readableOnly) { await model.load() }
    }
}

struct AuthorLink: View {
    @EnvironmentObject private var environment: AppEnvironment
    let id: UUID
    let name: String

    var body: some View {
        NavigationLink {
            AuthorView(id: id, name: name, repository: environment.catalogRepository)
        } label: {
            Text(name).foregroundStyle(BeryndaColor.accent)
        }
        .accessibilityIdentifier("work.author.\(id)")
    }
}
