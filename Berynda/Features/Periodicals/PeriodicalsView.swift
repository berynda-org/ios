import BeryndaCore
import SwiftUI

/// «Періодика»: journals and other periodicals, searchable by name or ISSN.
struct PeriodicalListView: View {
    @EnvironmentObject private var environment: AppEnvironment
    private let readableOnly: Bool

    init(readableOnly: Bool = false) {
        self.readableOnly = readableOnly
    }

    var body: some View {
        PeriodicalListContent(repository: environment.catalogRepository, readableOnly: readableOnly)
    }
}

private struct PeriodicalListContent: View {
    @StateObject private var model: PeriodicalListViewModel
    private let repository: any CatalogRepository
    private let readableOnly: Bool

    init(repository: any CatalogRepository, readableOnly: Bool) {
        self.repository = repository
        self.readableOnly = readableOnly
        _model = StateObject(wrappedValue: PeriodicalListViewModel(repository: repository))
    }

    var body: some View {
        Group {
            switch model.state {
            case .loading:
                BeryndaLoadingState(message: "Завантажуємо періодику…")
            case let .failed(message):
                BeryndaErrorState(title: "Не вдалося завантажити періодику", message: message) {
                    Task { await model.load() }
                }
            case .loaded where model.periodicals.isEmpty:
                BeryndaEmptyState(
                    title: "Нічого не знайдено",
                    message: model.isSearching ? "Спробуйте іншу назву або ISSN." : "Періодику ще не додано.",
                    systemImage: "newspaper"
                )
            case .loaded:
                List {
                    ForEach(model.periodicals) { periodical in
                        NavigationLink {
                            PeriodicalView(
                                periodical: periodical,
                                readableOnly: readableOnly,
                                repository: repository
                            )
                        } label: {
                            PeriodicalRow(periodical: periodical)
                        }
                        .accessibilityIdentifier("periodicals.periodical.\(periodical.id)")
                        .task { await model.loadNextPage(after: periodical) }
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
        .accessibilityIdentifier("periodicals.screen")
        .background(BeryndaColor.paper)
        .navigationTitle("Періодика")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $model.query, prompt: "Назва або ISSN")
        .onChange(of: model.query) { _, _ in model.searchChanged() }
        .task { if case .loading = model.state { await model.load() } }
    }
}

private struct PeriodicalRow: View {
    let periodical: PeriodicalSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(periodical.name)
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

    private var detail: String? {
        var parts: [String] = []
        if let years = periodical.yearsLabel { parts.append(years) }
        if periodical.issuesCount > 0 {
            parts.append(L("\(periodical.issuesCount) випусків"))
        }
        if periodical.worksCount > 0 {
            parts.append(L("\(periodical.worksCount) творів"))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

/// A periodical: what it is, then its years, each opening onto its issues.
struct PeriodicalView: View {
    @StateObject private var model: PeriodicalViewModel
    private let repository: any CatalogRepository
    private let readableOnly: Bool

    init(periodical: PeriodicalSummary, readableOnly: Bool = false, repository: any CatalogRepository) {
        self.repository = repository
        self.readableOnly = readableOnly
        _model = StateObject(wrappedValue: PeriodicalViewModel(
            identifier: periodical.id.uuidString.lowercased(),
            name: periodical.name,
            known: periodical,
            repository: repository
        ))
    }

    /// From a link that knows only the periodical's id or slug and name.
    init(identifier: String, name: String, readableOnly: Bool = false, repository: any CatalogRepository) {
        self.repository = repository
        self.readableOnly = readableOnly
        _model = StateObject(wrappedValue: PeriodicalViewModel(
            identifier: identifier,
            name: name,
            repository: repository
        ))
    }

    var body: some View {
        Group {
            if model.isLoading && model.years.isEmpty {
                BeryndaLoadingState(message: "Завантажуємо періодичне видання…")
            } else if let message = model.errorMessage {
                BeryndaErrorState(title: "Не вдалося завантажити періодичне видання", message: message) {
                    Task { await model.load() }
                }
            } else {
                List {
                    Section { header }
                    Section("Роки") {
                        if model.years.isEmpty {
                            Text("Випусків ще не додано.")
                                .foregroundStyle(BeryndaColor.mutedInk)
                        }
                        ForEach(model.years) { year in
                            yearRows(year)
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .refreshable { await model.load() }
            }
        }
        .accessibilityIdentifier("periodical.screen")
        .background(BeryndaColor.paper)
        .navigationTitle("Періодичне видання")
        .navigationBarTitleDisplayMode(.inline)
        .task { if model.years.isEmpty { await model.load() } }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(model.title)
                .font(.system(.title, design: .serif, weight: .bold))
                .foregroundStyle(BeryndaColor.ink)
                .accessibilityIdentifier("periodical.name")
                .accessibilityAddTraits(.isHeader)
            if let facts {
                Text(facts)
                    .font(.subheadline)
                    .foregroundStyle(BeryndaColor.mutedInk)
            }
            if let issn = model.periodical?.issn, !issn.isEmpty {
                Text("ISSN \(issn)")
                    .font(.caption)
                    .foregroundStyle(BeryndaColor.mutedInk)
            }
            if let description = model.periodical?.description?.trimmingCharacters(in: .whitespacesAndNewlines),
               !description.isEmpty {
                Text(description).font(.body)
            }
        }
        .padding(.vertical, 8)
    }

    private var facts: String? {
        guard let periodical = model.periodical else { return nil }
        let parts = [
            periodical.yearsLabel,
            periodical.publicationPlace,
            periodical.language.map(CatalogVocabulary.languageName),
        ].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    @ViewBuilder
    private func yearRows(_ year: PeriodicalYear) -> some View {
        Button {
            Task { await model.toggle(year.year) }
        } label: {
            HStack {
                Text(String(year.year))
                    .font(.headline)
                    .foregroundStyle(BeryndaColor.ink)
                Spacer()
                Text(L("\(year.issuesCount) випусків"))
                    .font(.caption)
                    .foregroundStyle(BeryndaColor.mutedInk)
                Image(systemName: model.expandedYears.contains(year.year) ? "chevron.up" : "chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(BeryndaColor.mutedInk)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityIdentifier("periodical.year.\(year.year)")
        .accessibilityValue(model.expandedYears.contains(year.year) ? L("Розгорнуто") : L("Згорнуто"))

        if model.expandedYears.contains(year.year) {
            switch model.issuesByYear[year.year] {
            case .loading, nil:
                ProgressView().frame(maxWidth: .infinity)
            case let .failed(message):
                VStack(alignment: .leading, spacing: 6) {
                    Text(message).font(.caption).foregroundStyle(BeryndaColor.mutedInk)
                    Button("Повторити") { Task { await model.loadIssues(for: year.year) } }
                        .font(.footnote.weight(.semibold))
                }
            case let .loaded(issues):
                ForEach(issues) { issue in
                    NavigationLink {
                        PeriodicalIssueView(
                            issue: issue,
                            periodicalName: model.title,
                            readableOnly: readableOnly,
                            repository: repository
                        )
                    } label: {
                        Text(issue.displayTitle)
                            .padding(.leading, 12)
                    }
                    .accessibilityIdentifier("periodical.issue.\(issue.id)")
                }
            }
        }
    }
}

/// One issue and the works in it, each with its pages in the issue.
struct PeriodicalIssueView: View {
    @StateObject private var model: PeriodicalIssueViewModel
    private let issue: PeriodicalIssue
    private let periodicalName: String?
    private let repository: any CatalogRepository

    init(
        issue: PeriodicalIssue,
        periodicalName: String? = nil,
        readableOnly: Bool = false,
        repository: any CatalogRepository
    ) {
        self.issue = issue
        self.periodicalName = periodicalName ?? issue.periodicalName
        self.repository = repository
        _model = StateObject(wrappedValue: PeriodicalIssueViewModel(
            issueID: issue.id,
            readableOnly: readableOnly,
            repository: repository
        ))
    }

    var body: some View {
        Group {
            if model.isLoading && model.works.isEmpty {
                BeryndaLoadingState(message: "Завантажуємо випуск…")
            } else if let message = model.errorMessage {
                BeryndaErrorState(title: "Не вдалося завантажити випуск", message: message) {
                    Task { await model.load() }
                }
            } else {
                List {
                    Section {
                        VStack(alignment: .leading, spacing: 6) {
                            if let periodicalName, !periodicalName.isEmpty {
                                Text(periodicalName)
                                    .font(.subheadline)
                                    .foregroundStyle(BeryndaColor.mutedInk)
                            }
                            Text(issue.displayTitle)
                                .font(.system(.title2, design: .serif, weight: .bold))
                                .foregroundStyle(BeryndaColor.ink)
                                .accessibilityIdentifier("issue.title")
                                .accessibilityAddTraits(.isHeader)
                            if let pages = issue.pageCount {
                                Text("\(pages) с.")
                                    .font(.caption)
                                    .foregroundStyle(BeryndaColor.mutedInk)
                            }
                        }
                        .padding(.vertical, 8)
                    }
                    Section("Твори · \(model.totalCount.formatted())") {
                        if model.works.isEmpty {
                            (model.readableOnly
                                 ? Text("Наразі немає творів, доступних для читання.")
                                 : Text("У цьому випуску ще немає творів."))
                                .foregroundStyle(BeryndaColor.mutedInk)
                        }
                        ForEach(model.works) { entry in
                            NavigationLink {
                                WorkDetailView(work: entry.work, repository: repository)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    WorkRow(work: entry.work)
                                    if let pages = entry.issuePages {
                                        Text("С. \(pages)")
                                            .font(.caption)
                                            .foregroundStyle(BeryndaColor.mutedInk)
                                            .padding(.leading, 4)
                                    }
                                }
                            }
                            .accessibilityIdentifier("issue.work.\(entry.id)")
                            .task { await model.loadNextPage(after: entry) }
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
        .accessibilityIdentifier("issue.screen")
        .background(BeryndaColor.paper)
        .navigationTitle("Випуск")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .top, spacing: 0) {
            CatalogReadingFilter(readableOnly: $model.readableOnly)
        }
        .task(id: model.readableOnly) { await model.load() }
    }
}

/// «Опубліковано в» on the work page: each issue the work appeared in, and
/// the periodical it belongs to.
struct PublishedInPanel: View {
    @EnvironmentObject private var environment: AppEnvironment
    let links: [WorkPeriodicalLink]

    var body: some View {
        BeryndaPanel {
            VStack(alignment: .leading, spacing: 10) {
                Label("Опубліковано в", systemImage: "newspaper")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                ForEach(links) { link in
                    VStack(alignment: .leading, spacing: 4) {
                        if let name = link.issue.periodicalName, let identifier = periodicalIdentifier(link) {
                            NavigationLink {
                                PeriodicalView(
                                    identifier: identifier,
                                    name: name,
                                    repository: environment.catalogRepository
                                )
                            } label: {
                                Text(name)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(BeryndaColor.accent)
                            }
                            .accessibilityIdentifier("work.periodical.\(identifier)")
                        }
                        NavigationLink {
                            PeriodicalIssueView(issue: link.issue, repository: environment.catalogRepository)
                        } label: {
                            Text(issueLabel(link))
                                .font(.subheadline)
                                .foregroundStyle(BeryndaColor.accent)
                                .multilineTextAlignment(.leading)
                        }
                        .accessibilityIdentifier("work.issue.\(link.issue.id)")
                    }
                }
            }
        }
    }

    private func periodicalIdentifier(_ link: WorkPeriodicalLink) -> String? {
        if let slug = link.issue.periodicalSlug, !slug.isEmpty { return slug }
        return link.issue.periodicalID?.uuidString.lowercased()
    }

    private func issueLabel(_ link: WorkPeriodicalLink) -> String {
        var parts = [link.issue.displayTitle]
        if let column = link.columnName { parts.append(L("рубрика «\(column)»")) }
        if let pages = link.pages { parts.append(L("с. \(pages)")) }
        return parts.joined(separator: " · ")
    }
}
