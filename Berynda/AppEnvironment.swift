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
    /// Queued writes and the offline shelf.
    let offline: OfflineSync
    private var cancellables: Set<AnyCancellable> = []
    @Published var selectedTab: RootTab = .catalog
    @Published var pendingRoute: AppRoute?
    @Published var catalogPath: [CatalogDestination] = []
    @Published var tabletCatalogSelection: CatalogDestination?
    @Published var presentedReader: ReaderPresentation?
    @Published var presentedAuthenticationLink: AuthenticationLinkPresentation?
    @Published var showsAuthentication = false
    @Published var authenticatedActionMessage: String?
    /// A one-line confirmation after the account itself changed, e.g. it
    /// was deleted.
    @Published var accountNotice: String?
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
        networkMonitor: NetworkMonitor? = nil,
        mutationSender: (any MutationSending)? = nil,
        offlineStatusChecker: (any OfflineStatusChecking)? = nil,
        outboxURL: URL? = nil,
        offlineDirectory: URL? = nil
    ) {
        self.catalogRepository = catalogRepository
        let offlineLibrary = OfflineLibrary(
            directory: offlineDirectory ?? FileManager.default.temporaryDirectory
                .appendingPathComponent("BeryndaOffline-\(UUID().uuidString)", isDirectory: true)
        )
        // Saved copies are read first; saving itself always fetches live.
        self.readerRepository = OfflineAwareReaderRepository(live: readerRepository, library: offlineLibrary)
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
        let offline = OfflineSync(
            outbox: MutationOutbox(fileURL: outboxURL),
            library: offlineLibrary,
            sender: mutationSender,
            statusChecker: offlineStatusChecker,
            source: readerRepository,
            localPositions: localReadingPositions
        )
        self.offline = offline
        self.library = LibraryViewModel(
            repository: libraryRepository,
            account: account,
            offline: offline
        )
        self.networkMonitor = networkMonitor ?? NetworkMonitor()
        observeSyncTriggers()
    }

    /// Queued writes go out when the network returns and after sign-in, and
    /// are forgotten the moment the account they belong to signs out (which
    /// includes deletion).
    private func observeSyncTriggers() {
        // The launch value is `.anonymous` until the stored session is
        // restored, so only a real sign-out (a move to anonymous) clears the
        // queue. An expired session keeps it: the owner check in the outbox
        // stops it reaching a different account that signs in next.
        account.$state
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] state in
                guard let self else { return }
                Task { @MainActor in
                    switch state {
                    case .authenticated:
                        await self.syncNow()
                    case .anonymous:
                        await self.offline.forgetQueuedWrites()
                    case .expired:
                        break
                    }
                }
            }
            .store(in: &cancellables)
        networkMonitor.$status
            .removeDuplicates()
            .filter { $0 == .online }
            .sink { [weak self] _ in
                Task { @MainActor in await self?.syncNow() }
            }
            .store(in: &cancellables)
    }

    /// Also called when the app comes back to the foreground.
    func syncNow() async {
        let owner = account.state == .authenticated ? account.profile?.id : nil
        await offline.sync(ownerID: owner)
    }

    static func live(baseURL: URL = AppConfiguration.apiBaseURL) -> AppEnvironment {
        precondition(
            baseURL.scheme == "https" && baseURL.absoluteString.hasSuffix("/api/v1/"),
            "The production API URL must use HTTPS and end in /api/v1/."
        )
        // Server-supplied copy (errors, restriction reasons) follows the
        // interface language chosen in Profile, read fresh on every request.
        let language: @Sendable () -> String = { AppLanguage.current.acceptLanguage }
        let authentication = LiveAuthenticationService(baseURL: baseURL, language: language)
        let session = SessionController(
            tokenStore: KeychainTokenStore(),
            authentication: authentication
        )
        let client = BeryndaAPIClient(
            baseURL: baseURL,
            language: language,
            authorizationSession: session
        )
        return AppEnvironment(
            catalogRepository: LiveCatalogRepository(client: client),
            readerRepository: LiveReaderRepository(client: client),
            session: session,
            authentication: authentication,
            accountRepository: LiveAccountRepository(client: client),
            libraryRepository: LiveLibraryRepository(client: client),
            mutationSender: LiveMutationSender(client: client),
            offlineStatusChecker: LiveOfflineStatusChecker(client: client),
            outboxURL: MutationOutbox.defaultFileURL(),
            offlineDirectory: OfflineLibrary.defaultDirectory()
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
                fallbackTitle: L("Беринда"),
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

    /// After deletion the device has already forgotten the account; this
    /// leaves every screen that showed it and says it is done.
    func accountWasDeleted() async {
        pendingAuthenticatedAction = nil
        presentedReader = nil
        catalogPath = []
        tabletCatalogSelection = nil
        selectedTab = .catalog
        await library.loadIfNeeded()
        accountNotice = L("Обліковий запис видалено.")
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
            successMessage = L("Твір додано до бібліографічного списку.")
        case let .saveCollection(collection):
            result = await library.setCollectionSaved(collection, saved: true)
            successMessage = L("Колекцію додано до бібліотеки.")
        case let .bookmark(fileID, page):
            // The page is the one captured when the reader tapped, not
            // wherever the reader has scrolled to by the time sign-in ends.
            result = await library.quickAdd(fileID: fileID, page: page)
            successMessage = L("Закладку додано до бібліографічного списку.")
        }

        switch result {
        case .saved:
            authenticatedActionMessage = successMessage
        case .removed:
            // Pending actions only ever save; kept for exhaustiveness.
            authenticatedActionMessage = L("Колекцію прибрано з бібліотеки.")
        case .alreadySaved:
            authenticatedActionMessage = L("Цей запис уже є у вашій бібліотеці.")
        case .inProgress:
            authenticatedActionMessage = L("Інше збереження вже виконується. Спробуйте ще раз.")
        case .signInRequired:
            authenticatedActionMessage = L("Сеанс завершився. Увійдіть і повторіть дію.")
        case .queued:
            authenticatedActionMessage = LibraryViewModel.SaveResult.queuedMessage
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
    /// The topic browser, opened with the catalog's readable switch.
    case topics(readableOnly: Bool)
    /// An author found by the catalog search.
    case author(id: UUID, name: String)
    /// The periodical list, opened with the catalog's readable switch.
    case periodicals(readableOnly: Bool)
    /// A periodical found by the catalog search.
    case periodical(id: UUID, name: String)
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
