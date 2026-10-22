import BeryndaCore
import SwiftUI

/// Everything filter-related a catalog list carries, shared by the phone
/// stack and the iPad column so both offer the same filters the same way.
struct CatalogFiltering: ViewModifier {
    @ObservedObject var model: CatalogViewModel
    @State private var showsFilters = false

    init(model: CatalogViewModel) {
        self.model = model
    }

    func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .top, spacing: 0) {
                VStack(spacing: 0) {
                    CatalogReadingFilter(readableOnly: $model.filters.readableOnly)
                    if model.filters.hasRefinements {
                        ActiveFilterChips(filters: $model.filters)
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showsFilters = true
                    } label: {
                        Label(
                            "Фільтри",
                            systemImage: model.filters.hasRefinements
                                ? "line.3.horizontal.decrease.circle.fill"
                                : "line.3.horizontal.decrease.circle"
                        )
                    }
                    .accessibilityIdentifier("catalog.filters")
                    .accessibilityValue(
                        model.filters.hasRefinements ? L("Активних: \(model.filters.refinementCount)") : ""
                    )
                }
            }
            .sheet(isPresented: $showsFilters) {
                CatalogFilterSheet(model: model, initial: model.filters)
            }
            .onChange(of: model.query) { _, _ in model.searchChanged() }
            .onChange(of: model.filters) { _, _ in model.searchChanged() }
    }
}

/// The sheet's choices, each removable on its own, so a narrowed catalog
/// always says why it is narrowed.
struct ActiveFilterChips: View {
    @Binding var filters: WorkFilters

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                if let language = filters.language {
                    chip(CatalogVocabulary.languageName(language), key: "language") {
                        filters.language = nil
                    }
                }
                if let workType = filters.workType {
                    chip(CatalogVocabulary.workTypeName(workType), key: "work-type") {
                        filters.workType = nil
                    }
                }
                if let years = yearsLabel {
                    chip(years, key: "years") {
                        filters.yearFrom = nil
                        filters.yearTo = nil
                    }
                }
                if let topic = filters.topic {
                    chip(topic.name, key: "topic") { filters.topic = nil }
                }
                Button {
                    filters = filters.clearingRefinements()
                } label: {
                    Text("Скинути все").minimumHitTarget()
                }
                .font(.footnote.weight(.semibold))
                .tint(BeryndaColor.accent)
                .accessibilityIdentifier("catalog.filters.clear")
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
        }
        .background(.bar)
        .accessibilityIdentifier("catalog.active-filters")
    }

    private var yearsLabel: String? {
        switch filters.normalizedYears {
        case let (from?, to?): from == to ? "\(from)" : "\(from)–\(to)"
        case let (from?, nil): L("від \(from)")
        case let (nil, to?): L("до \(to)")
        default: nil
        }
    }

    private func chip(_ title: String, key: String, remove: @escaping () -> Void) -> some View {
        Button(action: remove) {
            HStack(spacing: 5) {
                Text(title)
                    .lineLimit(1)
                Image(systemName: "xmark")
                    .font(.caption2.weight(.bold))
                    .accessibilityHidden(true)
            }
            .font(.footnote)
            .foregroundStyle(BeryndaColor.ink)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(BeryndaColor.surface, in: Capsule())
            // Visually a small capsule, but a 44-point target.
            .minimumHitTarget()
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Прибрати фільтр: \(title)")
        .accessibilityIdentifier("catalog.filter.\(key)")
    }
}

/// Edits a copy of the filters and applies it in one step, so the catalog
/// reloads once rather than on every picker change.
struct CatalogFilterSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var model: CatalogViewModel
    @State private var draft: WorkFilters
    @State private var yearFrom: String
    @State private var yearTo: String

    init(model: CatalogViewModel, initial: WorkFilters) {
        self.model = model
        _draft = State(initialValue: initial)
        _yearFrom = State(initialValue: initial.yearFrom.map(String.init) ?? "")
        _yearTo = State(initialValue: initial.yearTo.map(String.init) ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Мова", selection: $draft.language) {
                        Text("Усі мови").tag(String?.none)
                        ForEach(options(model.facets?.languages, selected: draft.language)) { option in
                            Text(label(CatalogVocabulary.languageName(option.value), count: option.count))
                                .tag(String?.some(option.value))
                        }
                    }
                    .accessibilityIdentifier("catalog.filters.language")

                    Picker("Тип", selection: $draft.workType) {
                        Text("Усі типи").tag(String?.none)
                        ForEach(options(model.facets?.workTypes, selected: draft.workType)) { option in
                            Text(label(CatalogVocabulary.workTypeName(option.value), count: option.count))
                                .tag(String?.some(option.value))
                        }
                    }
                    .accessibilityIdentifier("catalog.filters.work-type")
                }

                Section {
                    HStack(spacing: 12) {
                        TextField("від", text: $yearFrom)
                            .keyboardType(.numberPad)
                            .accessibilityLabel("Рік від")
                            .accessibilityIdentifier("catalog.filters.year-from")
                        Text("–").foregroundStyle(BeryndaColor.mutedInk)
                        TextField("до", text: $yearTo)
                            .keyboardType(.numberPad)
                            .accessibilityLabel("Рік до")
                            .accessibilityIdentifier("catalog.filters.year-to")
                    }
                } header: {
                    Text("Рік першої публікації")
                } footer: {
                    if let bounds = model.facets?.yearBounds {
                        Text("У каталозі: \(String(bounds.lowerBound))–\(String(bounds.upperBound))")
                    }
                }

                Section("Тема") {
                    if let topic = draft.topic {
                        HStack {
                            Text(topic.name)
                            Spacer()
                            Button("Прибрати", role: .destructive) { draft.topic = nil }
                                .buttonStyle(.borderless)
                        }
                    }
                    NavigationLink {
                        TopicPickerView(selection: $draft.topic)
                    } label: {
                        draft.topic == nil ? Text("Обрати тему") : Text("Змінити тему")
                    }
                    .accessibilityIdentifier("catalog.filters.topic")
                }

                if hasDraftRefinements {
                    Section {
                        Button("Скинути фільтри", role: .destructive) {
                            draft = draft.clearingRefinements()
                            yearFrom = ""
                            yearTo = ""
                        }
                        .accessibilityIdentifier("catalog.filters.reset")
                    }
                }
            }
            .navigationTitle("Фільтри")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Скасувати") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Показати") { apply() }
                        .accessibilityIdentifier("catalog.filters.apply")
                }
            }
            .task { await model.loadFacetsIfNeeded() }
        }
    }

    private var hasDraftRefinements: Bool {
        draft.hasRefinements || Self.year(yearFrom) != nil || Self.year(yearTo) != nil
    }

    private func apply() {
        var applied = draft
        applied.yearFrom = Self.year(yearFrom)
        applied.yearTo = Self.year(yearTo)
        // The switch lives outside the sheet; keep whatever it says now.
        applied.readableOnly = model.filters.readableOnly
        if applied != model.filters {
            model.filters = applied
        }
        dismiss()
    }

    /// The facet's options, plus the current choice if the counts no longer
    /// include it, so a selection never silently disappears from its picker.
    private func options(_ facet: [FacetOption]?, selected: String?) -> [FacetOption] {
        var rows = facet ?? []
        if let selected, !rows.contains(where: { $0.value == selected }) {
            rows.insert(FacetOption(value: selected, count: 0), at: 0)
        }
        return rows
    }

    private func label(_ name: String, count: Int) -> String {
        count > 0 ? "\(name) · \(count.formatted())" : name
    }

    private static func year(_ text: String) -> Int? {
        let digits = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value = Int(digits), (1...2_100).contains(value) else { return nil }
        return value
    }
}

/// Chooses one topic for the filter: roots with their subtopics, or a
/// search across all topics.
struct TopicPickerView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @Binding var selection: TopicReference?

    var body: some View {
        TopicPickerList(repository: environment.catalogRepository, selection: $selection)
    }
}

private struct TopicPickerList: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model: TopicListViewModel
    @Binding var selection: TopicReference?

    init(repository: any CatalogRepository, selection: Binding<TopicReference?>) {
        _model = StateObject(wrappedValue: TopicListViewModel(repository: repository))
        _selection = selection
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
                    message: "Спробуйте інший запит.",
                    systemImage: "text.magnifyingglass"
                )
            case .loaded:
                List {
                    ForEach(model.topics) { topic in
                        Group {
                            if model.isSearching || topic.children.isEmpty {
                                row(topic.reference, subtitle: model.isSearching ? topic.parentName : nil)
                            } else {
                                DisclosureGroup {
                                    row(topic.reference, title: L("Уся тема"))
                                    ForEach(topic.children) { child in
                                        row(child.reference)
                                    }
                                } label: {
                                    Text(topic.name)
                                }
                            }
                        }
                        .task { await model.loadNextPage(after: topic) }
                    }
                    if model.isLoadingNextPage {
                        ProgressView().frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .navigationTitle("Тема")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $model.query, prompt: "Назва теми")
        .onChange(of: model.query) { _, _ in model.searchChanged() }
        .task { if case .loading = model.state { await model.load() } }
    }

    private func row(_ topic: TopicReference, title: String? = nil, subtitle: String? = nil) -> some View {
        Button {
            selection = topic
            dismiss()
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title ?? topic.name)
                        .foregroundStyle(BeryndaColor.ink)
                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(BeryndaColor.mutedInk)
                    }
                }
                Spacer()
                if selection?.slug == topic.slug {
                    Image(systemName: "checkmark")
                        .foregroundStyle(BeryndaColor.accent)
                        .accessibilityHidden(true)
                }
            }
        }
        // The checkmark is drawn; VoiceOver hears "selected" instead.
        .accessibilityAddTraits(selection?.slug == topic.slug ? .isSelected : [])
        .accessibilityIdentifier("topic.pick.\(topic.slug)")
    }
}
