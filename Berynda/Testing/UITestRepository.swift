import BeryndaCore
import Foundation

#if DEBUG
actor UITestRepository: CatalogRepository, ReaderRepository, LibraryRepository {
    private let decoder = JSONDecoder()

    func works(search: String?, page: Int) async throws -> PaginatedResponse<WorkSummary> {
        let query = search?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        if let query, !query.isEmpty {
            let results = query.contains("кобзар") ? Self.kobzarWork : ""
            let count = results.isEmpty ? 0 : 1
            return try decode(Self.page(count: count, next: nil, results: results))
        }

        switch page {
        case 1:
            return try decode(
                Self.page(
                    count: 3,
                    next: "https://berynda.org/api/v1/works/?page=2",
                    results: [Self.kobzarWork, Self.forestSongWork].joined(separator: ",")
                )
            )
        case 2:
            return try decode(Self.page(count: 3, next: nil, results: Self.noFileWork))
        default:
            return try decode(Self.page(count: 3, next: nil, results: ""))
        }
    }

    func work(identifier: String) async throws -> WorkSummary {
        let json: String
        switch identifier.lowercased() {
        case "kobzar", Self.kobzarWorkID.uuidString.lowercased():
            // Detail-shaped, unlike the list row, so the enriched
            // bibliography is exercised rather than assumed.
            json = Self.kobzarDetail
        case "lisova-pisnia", Self.forestSongWorkID.uuidString.lowercased():
            json = Self.forestSongWork
        case "slovo-o-polku", Self.noFileWorkID.uuidString.lowercased():
            json = Self.noFileWork
        default:
            throw UITestFixtureError.missingFixture
        }
        return try decode(json)
    }

    func editions(workID: UUID) async throws -> [EditionSummary] {
        switch workID {
        case Self.kobzarWorkID:
            return try decode("[\(Self.readableEdition)]")
        case Self.forestSongWorkID:
            return try decode("[\(Self.restrictedEdition)]")
        case Self.noFileWorkID:
            return try decode("[\(Self.noFileEdition)]")
        default:
            return []
        }
    }

    func info(fileID: UUID) async throws -> ReaderInfo {
        guard fileID == Self.readerFileID else { throw UITestFixtureError.missingFixture }
        return try decode(Self.readerInfo)
    }

    func text(fileID: UUID) async throws -> TextReaderContent {
        try decode(#"{"body":"Тестовий текст","page_offsets":[]}"#)
    }

    func epubDocument(fileID: UUID) async throws -> Data {
        throw UITestFixtureError.unsupported
    }

    func fullDocument(fileID: UUID) async throws -> Data {
        throw UITestFixtureError.unsupported
    }

    func pagePDF(fileID: UUID, page: Int) async throws -> Data {
        throw UITestFixtureError.unsupported
    }

    func pageImage(fileID: UUID, page: Int, width: Int) async throws -> Data {
        guard fileID == Self.readerFileID, (1...3).contains(page) else {
            throw UITestFixtureError.missingFixture
        }
        return Data(
            base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
        )!
    }

    func savePosition(
        fileID: UUID,
        positionType: String,
        positionValue: String,
        progressPercent: Int?,
        totalPages: Int?
    ) async throws -> Bool { true }

    func continueReading(limit: Int) async throws -> ContinueReadingResponse {
        ContinueReadingResponse(recentlyRead: [], historyEnabled: true)
    }

    func bibliographyLists() async throws -> [BibliographyList] { [] }

    func createList(title: String) async throws -> BibliographyList {
        throw UITestFixtureError.unsupported
    }

    // The fixture serves no lists, so there is nothing to rename, delete or
    // take an item out of — exactly what the server answers (404) for a list
    // the reader does not have.
    func renameList(id: UUID, title: String) async throws -> BibliographyList {
        throw UITestFixtureError.missingFixture
    }

    func deleteList(id: UUID) async throws {
        throw UITestFixtureError.missingFixture
    }

    func removeItem(listID: UUID, itemID: UUID) async throws {
        throw UITestFixtureError.missingFixture
    }

    func quickAdd(
        workID: UUID?,
        fileID: UUID?,
        positionType: String?,
        positionValue: String?,
        pageNumber: Int?
    ) async throws -> BibliographyItem {
        guard workID == Self.kobzarWorkID || fileID == Self.readerFileID else {
            throw UITestFixtureError.unsupported
        }
        return try decode(Self.quickAddedItem)
    }

    func publicCollections() async throws -> [PublicCollectionSummary] { [] }
    func savedCollections() async throws -> [PublicCollectionSummary] { [] }
    func setCollectionSaved(slug: String, saved: Bool) async throws {}

    private func decode<Value: Decodable>(_ json: String) throws -> Value {
        try decoder.decode(Value.self, from: Data(json.utf8))
    }
}

private extension UITestRepository {
    static let kobzarWorkID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    static let forestSongWorkID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
    static let noFileWorkID = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
    static let readerFileID = UUID(uuidString: "44444444-4444-4444-4444-444444444444")!

    static func page(count: Int, next: String?, results: String) -> String {
        let nextValue = next.map { #""\#($0)""# } ?? "null"
        return #"{"count":\#(count),"next":\#(nextValue),"previous":null,"results":[\#(results)]}"#
    }

    static let kobzarWork = #"{"id":"11111111-1111-1111-1111-111111111111","slug":"kobzar","title":"Кобзар","subtitle":"Вибрані поезії","language":"uk","first_published_year":1840,"authors":[{"id":"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa","display_name":"Тарас Шевченко"}],"editions_count":1,"has_text_file":true,"cover_image_url":null,"cover_tone":"burgundy","cover_variant":"frame","cover_glyph":"К"}"#

    static let kobzarDetail = #"{"id":"11111111-1111-1111-1111-111111111111","slug":"kobzar","title":"Кобзар","subtitle":"Вибрані поезії","original_title":null,"language":"uk","additional_languages":["ru"],"first_published_year":1840,"work_type":"book","is_collection":true,"rights_summary":"public_domain","pd_status":"unknown","editions_count":1,"has_text_file":true,"cover_image_url":null,"cover_tone":"burgundy","cover_variant":"frame","cover_glyph":"К","literary_form":{"id":"cccccccc-cccc-cccc-cccc-cccccccccccc","name":"Поезія","name_en":"Poetry"},"genres":[{"id":"dddddddd-dddd-dddd-dddd-dddddddddddd","name":"Лірика","name_en":"Lyric"}],"topics":[{"id":"eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee","name":"Українська література","name_en":null}],"contributions":[{"person_id":"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa","role":"author","person_display_name":"Тарас Шевченко","display_name_override":null},{"person_id":"ffffffff-ffff-ffff-ffff-ffffffffffff","role":"editor","person_display_name":"Іван Редактор","display_name_override":null}]}"#

    static let forestSongWork = #"{"id":"22222222-2222-2222-2222-222222222222","slug":"lisova-pisnia","title":"Лісова пісня","subtitle":null,"language":"uk","first_published_year":1911,"authors":[{"id":"bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb","display_name":"Леся Українка"}],"editions_count":1,"has_text_file":false,"cover_image_url":null,"cover_tone":"green","cover_variant":"frame","cover_glyph":"Л"}"#

    static let noFileWork = #"{"id":"33333333-3333-3333-3333-333333333333","slug":"slovo-o-polku","title":"Слово о полку Ігоревім","subtitle":null,"language":"uk","first_published_year":1187,"authors":[],"editions_count":1,"has_text_file":false,"cover_image_url":null,"cover_tone":"ochre","cover_variant":"frame","cover_glyph":"С"}"#

    static let readableEdition = #"{"id":"aaaaaaaa-1111-1111-1111-111111111111","work":"11111111-1111-1111-1111-111111111111","display_title":"Кобзар. Видання 1840 року","language":"uk","year":1840,"publisher_name":"Друкарня Є. Фішера","publication_place":"Санкт-Петербург","page_count":3,"readable_file_id":"44444444-4444-4444-4444-444444444444","can_read":true,"can_download":false,"restriction_reason":null}"#

    static let restrictedEdition = #"{"id":"bbbbbbbb-2222-2222-2222-222222222222","work":"22222222-2222-2222-2222-222222222222","display_title":"Лісова пісня. Архівне видання","language":"uk","year":1914,"publisher_name":"Друкарня В. Бонч-Бруєвича","publication_place":"Київ","page_count":96,"readable_file_id":"55555555-5555-5555-5555-555555555555","can_read":false,"can_download":false,"restriction_reason":"Читання обмежено правовласником"}"#

    static let noFileEdition = #"{"id":"cccccccc-3333-3333-3333-333333333333","work":"33333333-3333-3333-3333-333333333333","display_title":"Бібліографічний запис","language":"uk","year":1800,"publisher_name":null,"publication_place":null,"page_count":null,"readable_file_id":null,"can_read":false,"can_download":false,"restriction_reason":null}"#

    static let readerInfo = #"{"file_id":"44444444-4444-4444-4444-444444444444","edition_id":"aaaaaaaa-1111-1111-1111-111111111111","series_id":null,"work_id":"11111111-1111-1111-1111-111111111111","book":{"title":"Кобзар","subtitle":"Вибрані поезії","authors":["Тарас Шевченко"],"edition_year":1840,"publisher":"Друкарня Є. Фішера","publication_place":"Санкт-Петербург","cover_image_url":null},"mime_type":"application/pdf","file_size_bytes":1024,"rendering_mode":"pdf","page_delivery":"server_pages","pages_extracted":true,"split_pending":false,"split_failed":false,"total_pages":3,"has_toc":true,"toc":[{"id":"dddddddd-dddd-dddd-dddd-dddddddddddd","ordinal":1,"title":"Передмова","page_number":1,"anchor":null,"level":0,"work_id":"11111111-1111-1111-1111-111111111111","children":[]}],"reading_position":null,"rights":{"can_read":true,"can_download_file":false,"can_download_page":false,"can_copy_text":false,"can_print":false,"can_share":false,"restriction_reason":null},"page_labels":[{"page":1,"label":"I","source":"print"},{"page":2,"label":"II","source":"print"},{"page":3,"label":"III","source":"print"}]}"#

    static let quickAddedItem = #"{"id":"eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee","work":"11111111-1111-1111-1111-111111111111","work_title":"Кобзар","work_slug":"kobzar","edition":null,"edition_year":null,"edition_title":null,"file":null,"position_type":null,"position_value":null,"page_number":null,"note":""}"#
}

struct UITestTokenStore: TokenStore {
    func load() throws -> AuthTokens? { nil }
    func save(_ tokens: AuthTokens) throws {}
    func clear() throws {}
}

actor UITestAuthenticationService: AuthenticationServing {
    func login(email: String, password: String) async throws -> AuthSession {
        guard email == "reader@example.org", password == "password123" else {
            throw SessionError.invalidCredentials
        }
        return AuthSession(
            tokens: try AuthTokens(
                access: "header.ui-access.signature",
                refresh: "header.ui-refresh.signature"
            ),
            user: UserProfile(
                id: UUID(uuidString: "99999999-9999-9999-9999-999999999999")!,
                email: email,
                displayName: "Тестовий читач"
            )
        )
    }

    func register(email: String, password: String, displayName: String) async throws -> RegistrationResult {
        RegistrationResult(
            id: UUID(uuidString: "99999999-9999-9999-9999-999999999999")!,
            email: email,
            activation: "email_confirmation_required"
        )
    }

    func requestPasswordReset(email: String) async throws {}

    func confirmEmail(token: String) async throws -> UserProfile {
        UserProfile(
            id: UUID(uuidString: "99999999-9999-9999-9999-999999999999")!,
            email: "reader@example.org",
            displayName: "Тестовий читач"
        )
    }

    func confirmPasswordReset(uid: String, token: String, newPassword: String) async throws {}

    func refresh(refreshToken: String) async throws -> AuthTokens {
        throw UITestFixtureError.unsupported
    }

    func logout(accessToken: String, refreshToken: String) async throws {}
}

actor UITestAccountRepository: AccountRepository {
    private var user = UserProfile(
        id: UUID(uuidString: "99999999-9999-9999-9999-999999999999")!,
        email: "reader@example.org",
        displayName: "Тестовий читач"
    )

    func profile() async throws -> UserProfile { user }

    func updateProfile(_ update: ProfileUpdate) async throws -> UserProfile {
        user = UserProfile(
            id: user.id,
            email: user.email,
            displayName: update.displayName ?? user.displayName,
            bio: update.bio ?? user.bio,
            institutionName: update.institutionName ?? user.institutionName,
            uiLanguage: update.uiLanguage ?? user.uiLanguage,
            privacySettings: update.privacySettings ?? user.privacySettings
        )
        return user
    }
}

private enum UITestFixtureError: LocalizedError {
    case missingFixture
    case unsupported

    var errorDescription: String? {
        switch self {
        case .missingFixture: "Тестові дані відсутні."
        case .unsupported: "Цей тестовий сценарій не підтримується."
        }
    }
}
#endif
