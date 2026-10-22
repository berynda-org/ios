import BeryndaCore
import SwiftUI

/// «Зберегти для читання офлайн» on an edition whose rights allow it: the
/// button, then progress, then the saved state with a way to remove it.
struct OfflineSaveControl: View {
    let fileID: UUID
    let editionID: UUID
    @ObservedObject var offline: OfflineSync

    var body: some View {
        Group {
            if let fraction = offline.downloads[fileID] {
                HStack(spacing: 10) {
                    ProgressView(value: fraction)
                        .accessibilityLabel("Зберігаємо для читання офлайн")
                    Button("Скасувати") { offline.cancelSave(fileID: fileID) }
                        .font(.footnote)
                }
                .accessibilityIdentifier("edition.saving-offline.\(editionID)")
            } else if offline.isSaved(fileID) {
                HStack {
                    Label("Збережено для читання офлайн", systemImage: "arrow.down.circle.fill")
                        .font(.footnote)
                        .foregroundStyle(BeryndaColor.accent)
                        .accessibilityIdentifier("edition.saved-offline.\(editionID)")
                    Spacer()
                    Button("Видалити", role: .destructive) {
                        Task { await offline.remove(fileID: fileID) }
                    }
                    .font(.footnote)
                    .accessibilityIdentifier("edition.remove-offline.\(editionID)")
                }
            } else {
                Button {
                    offline.save(fileID: fileID)
                } label: {
                    Label("Зберегти для читання офлайн", systemImage: "arrow.down.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("edition.save-offline.\(editionID)")
            }
        }
        .alert("Офлайн-читання", isPresented: Binding(
            get: { offline.saveError != nil },
            set: { if !$0 { offline.saveError = nil } }
        )) {
            Button("Гаразд", role: .cancel) {}
        } message: {
            Text(offline.saveError ?? "")
        }
    }
}

/// The saved editions in Profile → «Сховище», each removable.
struct OfflineStorageSection: View {
    @ObservedObject var offline: OfflineSync
    @State private var confirmsRemoveAll = false

    var body: some View {
        Section {
            if offline.copies.isEmpty {
                Text("Збережених для офлайн-читання видань немає. Зберегти можна видання суспільного надбання та відкриті ліцензії — кнопкою на сторінці твору.")
                    .font(.footnote)
                    .foregroundStyle(BeryndaColor.mutedInk)
            } else {
                ForEach(offline.copies) { copy in
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(copy.title)
                            if !copy.authors.isEmpty {
                                Text(copy.authors.joined(separator: ", "))
                                    .font(.caption)
                                    .foregroundStyle(BeryndaColor.mutedInk)
                            }
                        }
                        Spacer()
                        Text(Self.bytes(copy.byteCount))
                            .font(.caption)
                            .foregroundStyle(BeryndaColor.mutedInk)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("profile.offline.\(copy.fileID)")
                    .swipeActions {
                        Button("Видалити", role: .destructive) {
                            Task { await offline.remove(fileID: copy.fileID) }
                        }
                    }
                }
                LabeledContent(
                    "Разом офлайн",
                    value: Self.bytes(offline.copies.reduce(0) { $0 + $1.byteCount })
                )
                .fontWeight(.semibold)
                Button("Видалити всі збережені видання", role: .destructive) {
                    confirmsRemoveAll = true
                }
                .accessibilityIdentifier("profile.offline.remove-all")
                .alert("Видалити всі збережені видання?", isPresented: $confirmsRemoveAll) {
                    Button("Видалити", role: .destructive) {
                        Task { await offline.removeAll() }
                    }
                    Button("Скасувати", role: .cancel) {}
                } message: {
                    Text("Їх можна буде зберегти знову, коли буде мережа.")
                }
            }
        } header: {
            Text("Офлайн-читання")
        } footer: {
            Text("Збережене зберігається лише в застосунку. Його перевіряємо, коли є мережа, і прибираємо через \(OfflineStorageSection.maxAgeDays) днів без відкриття.")
        }
        .task { await offline.refreshCopies() }
    }

    static let maxAgeDays = 30

    private static let formatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowsNonnumericFormatting = false
        return formatter
    }()

    private static func bytes(_ count: Int64) -> String {
        formatter.string(fromByteCount: count)
    }
}
