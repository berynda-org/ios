import BeryndaCore
import SwiftUI

/// The save toggle a public collection gets on the catalog shelves and on
/// the work page.
///
/// Observes the library model directly: `AppEnvironment` holds it as a plain
/// constant, so a view that only reads it through the environment object
/// never learns that the snapshot changed and keeps offering to save a
/// collection that is already saved. Once saved, a tap unsaves — the model
/// refuses overlapping mutations, so a second tap during the round trip is
/// disabled rather than raced.
///
/// The sign-in-required flow is unchanged: an anonymous reader is sent to
/// authentication with the save queued as a pending action.
struct CollectionSaveButton: View {
    @EnvironmentObject private var environment: AppEnvironment
    @ObservedObject private var library: LibraryViewModel
    @ObservedObject private var account: AccountViewModel
    private let collection: PublicCollectionSummary
    private let onResult: (LibraryViewModel.SaveResult) -> Void

    init(
        library: LibraryViewModel,
        collection: PublicCollectionSummary,
        onResult: @escaping (LibraryViewModel.SaveResult) -> Void
    ) {
        _library = ObservedObject(wrappedValue: library)
        _account = ObservedObject(wrappedValue: library.accountForObservation)
        self.collection = collection
        self.onResult = onResult
    }

    private var isSaved: Bool { library.isCollectionSaved(collection) }

    var body: some View {
        Button {
            let saved = !isSaved
            Task {
                let result = await library.setCollectionSaved(collection, saved: saved)
                if result == .signInRequired {
                    environment.requireAuthentication(for: .saveCollection(collection))
                } else {
                    onResult(result)
                }
            }
        } label: {
            if isSaved {
                Label("Збережено", systemImage: "checkmark")
            } else {
                Label("Зберегти", systemImage: "bookmark")
            }
        }
        .disabled(library.isMutating)
        .accessibilityIdentifier("collection.save.\(collection.slug)")
        // The catalog is the first tab, so the snapshot may never have been
        // loaded when a shelf appears; without it every button reads unsaved.
        // Keyed by the account state so signing in fetches the reader's saved
        // collections and signing out drops them.
        .task(id: account.state) { await library.loadIfNeeded() }
    }
}

extension LibraryViewModel.SaveResult {
    /// `message` speaks of works and lists; collections need their own copy.
    var collectionMessage: String {
        switch self {
        case .saved: "Колекцію додано до бібліотеки."
        case .removed: "Колекцію прибрано з бібліотеки."
        case .alreadySaved: "Ця колекція вже є у вашій бібліотеці."
        case .inProgress, .signInRequired, .failed: message
        }
    }
}
