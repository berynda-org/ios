import Foundation
import XCTest
import BeryndaCore
@testable import Berynda

/// The reader's bookmark is a protected action like quick add and saved
/// collections: an anonymous reader is asked to sign in and the bookmark is
/// placed afterwards, on the page captured at the tap.
@MainActor
final class ReaderBookmarkAuthTests: XCTestCase {
    // The one file the UI-test repository serves; see UITestRepository.
    private let readerFileID = UUID(uuidString: "44444444-4444-4444-4444-444444444444")!

    func testAnonymousBookmarkAsksForSignInAndResumesAfterwards() async {
        let environment = AppEnvironment.uiTesting()
        XCTAssertNotEqual(environment.account.state, .authenticated)
        XCTAssertFalse(environment.showsAuthentication)

        // Signed out, the library refuses the bookmark instead of saving it.
        let refused = await environment.library.quickAdd(fileID: readerFileID, page: 2)
        XCTAssertEqual(refused, .signInRequired)

        environment.requireAuthentication(for: .bookmark(fileID: readerFileID, page: 2))
        XCTAssertTrue(environment.showsAuthentication)
        XCTAssertNil(environment.authenticatedActionMessage)

        let signedIn = await environment.account.signIn(
            email: "reader@example.org",
            password: "password123"
        )
        XCTAssertTrue(signedIn)
        XCTAssertEqual(environment.account.state, .authenticated)

        await environment.resumePendingAuthenticatedAction()
        XCTAssertEqual(
            environment.authenticatedActionMessage,
            "Закладку додано до бібліографічного списку."
        )
    }

    func testResumeIsANoOpWhileStillAnonymous() async {
        let environment = AppEnvironment.uiTesting()
        environment.requireAuthentication(for: .bookmark(fileID: readerFileID, page: 2))

        await environment.resumePendingAuthenticatedAction()
        XCTAssertNil(environment.authenticatedActionMessage)
        XCTAssertTrue(environment.showsAuthentication)
    }

    func testDismissingSignInDropsThePendingBookmark() async {
        let environment = AppEnvironment.uiTesting()
        environment.requireAuthentication(for: .bookmark(fileID: readerFileID, page: 2))

        // The reader closed the sheet without signing in.
        environment.showsAuthentication = false
        environment.authenticationDismissed()

        // A later sign-in must not place a bookmark the reader gave up on.
        _ = await environment.account.signIn(
            email: "reader@example.org",
            password: "password123"
        )
        await environment.resumePendingAuthenticatedAction()
        XCTAssertNil(environment.authenticatedActionMessage)
    }
}
