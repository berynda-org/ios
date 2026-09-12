import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var networkMonitor: NetworkMonitor
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @AppStorage("appearance.mode") private var appearanceMode = "system"

    var body: some View {
        Group {
            if horizontalSizeClass == .regular {
                TabletRootView()
            } else {
                PhoneRootView()
            }
        }
        .background(BeryndaColor.paper.ignoresSafeArea())
        .preferredColorScheme(preferredColorScheme)
        .safeAreaInset(edge: .top, spacing: 0) {
            if networkMonitor.status == .offline {
                Label("Немає з’єднання з мережею", systemImage: "wifi.slash")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .frame(maxWidth: .infinity, minHeight: 36)
                    .background(BeryndaColor.deepAccent)
                    .accessibilityIdentifier("network.offline-banner")
                }
        }
        .fullScreenCover(item: $environment.presentedReader) { presentation in
            ReaderView(
                fileID: presentation.fileID,
                fallbackTitle: presentation.fallbackTitle,
                initialPage: presentation.initialPage,
                repository: environment.readerRepository,
                session: environment.session,
                account: environment.account,
                localPositions: environment.localReadingPositions,
                library: environment.library
            )
        }
        .task { environment.consumePendingRoute() }
        .onChange(of: environment.pendingRoute) { _, _ in
            environment.consumePendingRoute()
        }
        .task { await environment.account.restore() }
        .sheet(isPresented: showsRootAuthentication, onDismiss: {
            environment.authenticationDismissed()
        }) {
            AuthenticationView(
                account: environment.account,
                onAuthenticated: { await environment.resumePendingAuthenticatedAction() }
            )
        }
        .sheet(item: $environment.presentedAuthenticationLink) { presentation in
            AuthenticationLinkView(
                route: presentation.route,
                account: environment.account
            )
        }
        .alert("Бібліотека", isPresented: Binding(
            get: { environment.authenticatedActionMessage != nil },
            set: { if !$0 { environment.authenticatedActionMessage = nil } }
        )) {
            Button("Гаразд", role: .cancel) {}
        } message: {
            Text(environment.authenticatedActionMessage ?? "")
        }
    }

    // UIKit lets a view controller present one modal at a time, and the
    // reader is a full-screen cover over this view: a sheet raised here while
    // a book is open never shows (or pops up only after the book is closed).
    // ReaderView presents the same sign-in sheet itself, so this one waits
    // until the reader is gone.
    private var showsRootAuthentication: Binding<Bool> {
        Binding(
            get: { environment.showsAuthentication && !environment.isReaderPresented },
            set: { if !$0 { environment.showsAuthentication = false } }
        )
    }

    private var preferredColorScheme: ColorScheme? {
        switch appearanceMode {
        case "light": .light
        case "dark": .dark
        default: nil
        }
    }
}

private struct PhoneRootView: View {
    @EnvironmentObject private var environment: AppEnvironment

    var body: some View {
        TabView(selection: $environment.selectedTab) {
            CatalogNavigationView()
                .tabItem {
                    Label("Каталог", systemImage: "books.vertical")
                        .accessibilityIdentifier("tab_catalog")
                }
                .tag(RootTab.catalog)

            NavigationStack { LibraryView() }
                .tabItem {
                    Label("Бібліотека", systemImage: "bookmark")
                        .accessibilityIdentifier("tab_library")
                }
                .tag(RootTab.library)

            NavigationStack { ProfileView() }
                .tabItem {
                    Label("Профіль", systemImage: "person.crop.circle")
                        .accessibilityIdentifier("tab_profile")
                }
                .tag(RootTab.profile)
        }
    }
}

private struct TabletRootView: View {
    @EnvironmentObject private var environment: AppEnvironment

    var body: some View {
        NavigationSplitView {
            List {
                sidebarButton("Каталог", systemImage: "books.vertical", tab: .catalog)
                sidebarButton("Бібліотека", systemImage: "bookmark", tab: .library)
                sidebarButton("Профіль", systemImage: "person.crop.circle", tab: .profile)
            }
            .navigationTitle("Берында")
        } content: {
            switch environment.selectedTab {
            case .catalog:
                TabletCatalogColumn(
                    repository: environment.catalogRepository,
                    recentlyViewed: environment.recentlyViewed,
                    selection: $environment.tabletCatalogSelection
                )
            case .library:
                NavigationStack { LibraryView() }
            case .profile:
                NavigationStack { ProfileView() }
            }
        } detail: {
            switch environment.selectedTab {
            case .catalog:
                switch environment.tabletCatalogSelection {
                case let .work(work):
                    WorkDetailView(work: work, repository: environment.catalogRepository)
                case let .linkedWork(identifier):
                    LinkedWorkView(identifier: identifier, repository: environment.catalogRepository)
                case nil:
                    ContentUnavailableView(
                        "Оберіть твір",
                        systemImage: "books.vertical",
                        description: Text("Відомості про твір і його видання відкриються тут.")
                    )
                }
            case .library:
                ContentUnavailableView("Бібліотека", systemImage: "bookmark")
            case .profile:
                ContentUnavailableView("Профіль", systemImage: "person.crop.circle")
            }
        }
    }

    private func sidebarButton(_ title: String, systemImage: String, tab: RootTab) -> some View {
        Button {
            environment.selectedTab = tab
        } label: {
            Label(title, systemImage: systemImage)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .listRowBackground(environment.selectedTab == tab ? BeryndaColor.surface : Color.clear)
    }
}

private struct CatalogNavigationView: View {
    @EnvironmentObject private var environment: AppEnvironment

    var body: some View {
        NavigationStack(path: $environment.catalogPath) {
            CatalogView()
                .navigationDestination(for: CatalogDestination.self) { destination in
                    switch destination {
                    case let .work(work):
                        WorkDetailView(
                            work: work,
                            repository: environment.catalogRepository
                        )
                    case let .linkedWork(identifier):
                        LinkedWorkView(
                            identifier: identifier,
                            repository: environment.catalogRepository
                        )
                    }
                }
        }
    }
}
