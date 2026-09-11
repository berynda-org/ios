import BeryndaCore
import Combine
import Foundation

@MainActor
final class AppEnvironment: ObservableObject {
    let catalogRepository: any CatalogRepository
    let readerRepository: any ReaderRepository
    let networkMonitor: NetworkMonitor
    let session: SessionController
    let account: AccountViewModel
    let library: LibraryViewModel
    let localReadingPositions: LocalReadingPositionStore
    let recentlyViewed: RecentlyViewedStore
    let localStorage: LocalStorageSummary
    @Published var selectedTab: RootTab = .catalog
    @Published var pendingRoute: AppRoute?
    @Published var catalogPath: [CatalogDestination] = []
    @Published var tabletCatalogSelection: CatalogDestination?
    @Published var presentedReader: ReaderPresentation?
    @Published var presentedAuthenticationLink: AuthenticationLinkPresentation?
    @Published var showsAuthentication = false
    @Published var authenticatedActionMessage: String?
    // True while the full-screen reader is on screen. The root view cannot
    // raise a sheet over a full-screen cover, so the reader presents the
    // sign-in sheet itself and the root stays quiet meanwhile.
    @Published var isReaderPresented = false
    private var pendingAuthenticatedAction: AuthenticatedAction?

    init(
        catalogRepository: any CatalogRepository,
        readerRepository: any ReaderRepository,
        session: SessionController,
        authentication: any AuthenticationServing,
        accountRepository: any AccountRepository,
        libraryRepository: any LibraryRepository,
        networkMonitor: NetworkMonitor? = nil
    ) {
        self.catalogRepository = catalogRepository
        self.readerRepository = readerRepository
        self.session = session
        let localReadingPositions = LocalReadingPositionStore()
        self.localReadingPositions = localReadingPositions
        let recentlyViewed = RecentlyViewedStore()
        self.recentlyViewed = recentlyViewed
        self.localStorage = LocalStorageSummary(
            readingPositions: localReadingPositions,
            recentlyViewed: recentlyViewed
        )
        let account = AccountViewModel(
            session: session,
            authentication: authentication,
            repository: accountRepository,
            localPositions: localReadingPositions,
            recentlyViewed: recentlyViewed
        )
        self.account = account
        self.library = LibraryViewModel(
            repository: libraryRepository,
            account: account
        )
        self.networkMonitor = networkMonitor ?? NetworkMonitor()
    }

    static func live(baseURL: URL = AppConfiguration.apiBaseURL) -> AppEnvironment {
        precondition(
            baseURL.scheme == "https" && baseURL.absoluteString.hasSuffix("/api/v1/"),
            "The production API URL must use HTTPS and end in /api/v1/."
        )
        let authentication = LiveAuthenticationService(baseURL: baseURL)
        let session = SessionController(
            tokenStore: KeychainTokenStore(),
            authentication: authentication
        )
        let client = BeryndaAPIClient(
            baseURL: baseURL,
            authorizationSession: session
        )
        return AppEnvironment(
            catalogRepository: LiveCatalogRepository(client: client),
            readerRepository: LiveReaderRepository(client: client),
            session: session,
            authentication: authentication,
            accountRepository: LiveAccountRepository(client: client),
            libraryRepository: LiveLibraryRepository(client: client)
        )
    }

    #if DEBUG
    static func uiTesting() -> AppEnvironment {
        let repository = UITestRepository()
        let authentication = UITestAuthenticationService()
        let session = SessionController(
            tokenStore: UITestTokenStore(),
            authentication: authentication
        )
        return AppEnvironment(
            catalogRepository: repository,
            readerRepository: repository,
            session: session,
            authentication: authentication,
            accountRepository: UITestAccountRepository(),
            libraryRepository: repository
        )
    }
    #endif

    func open(_ url: URL) {
        guard let route = AppRoute(url: url) else { return }
        pendingRoute = route
    }

    func consumePendingRoute() {
        guard let route = pendingRoute else { return }
        pendingRoute = nil
        switch route {
        case let .work(slug):
            selectedTab = .catalog
            presentedReader = nil
            catalogPath = [.linkedWork(identifier: slug)]
            tabletCatalogSelection = .linkedWork(identifier: slug)
        case let .reader(fileID, page):
            selectedTab = .catalog
            presentedReader = ReaderPresentation(
                fileID: fileID,
                fallbackTitle: "Берында",
                initialPage: page
            )
        case .confirmEmail, .resetPassword:
            selectedTab = .profile
            presentedAuthenticationLink = AuthenticationLinkPresentation(route: route)
        }
    }

    func presentReader(fileID: UUID, fallbackTitle: String, initialPage: Int? = nil) {
        presentedReader = ReaderPresentation(
            fileID: fileID,
            fallbackTitle: fallbackTitle,
            initialPage: initialPage
        )
    }

    func requireAuthentication(for action: AuthenticatedAction) {
        pendingAuthenticatedAction = action
        showsAuthentication = true
    }

    func authenticationDismissed() {
        if account.state != .authenticated {
            pendingAuthenticatedAction = nil
        }
    }

    func resumePendingAuthenticatedAction() async {
        guard account.state == .authenticated,
              let action = pendingAuthenticatedAction else { return }
        pendingAuthenticatedAction = nil

        let result: LibraryViewModel.SaveResult
        let successMessage: String
        switch action {
        case let .addWork(workID):
            result = await library.quickAdd(workID: workID)
            successMessage = "Твір додано до бібліографічного списку."
        case let .saveCollection(collection):
            result = await library.setCollectionSaved(collection, saved: true)
            successMessage = "Колекцію додано до бібліотеки."
        case let .bookmark(fileID, page):
            // The page is the one captured when the reader tapped, not
            // wherever the reader has scrolled to by the time sign-in ends.
            result = await library.quickAdd(fileID: fileID, page: page)
            successMessage = "Закладку додано до бібліографічного списку."
        }

        switch result {
        case .saved:
            authenticatedActionMessage = successMessage
        case .alreadySaved:
            authenticatedActionMessage = "Цей запис уже є у вашій бібліотеці."
        case .inProgress:
            authenticatedActionMessage = "Інше збереження вже виконується. Спробуйте ще раз."
        case .signInRequired:
            authenticatedActionMessage = "Сеанс завершився. Увійдіть і повторіть дію."
        case let .failed(message):
            authenticatedActionMessage = message
        }
    }
}

enum AuthenticatedAction {
    case addWork(UUID)
    case saveCollection(PublicCollectionSummary)
    case bookmark(fileID: UUID, page: Int)
}

enum CatalogDestination: Hashable {
    case work(WorkSummary)
    case linkedWork(identifier: String)
}

struct ReaderPresentation: Identifiable, Equatable {
    let id = UUID()
    let fileID: UUID
    let fallbackTitle: String
    let initialPage: Int?
}

struct AuthenticationLinkPresentation: Identifiable, Equatable {
    let id = UUID()
    let route: AppRoute
}

enum RootTab: Hashable {
    case catalog
    case library
    case profile
}
