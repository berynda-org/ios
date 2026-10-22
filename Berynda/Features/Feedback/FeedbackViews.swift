import BeryndaCore
import SwiftUI

/// Profile → «Відгук і підтримка»: shown signed in and signed out alike.
struct FeedbackSupportSection: View {
    let repository: any FeedbackRepository
    let isSignedIn: Bool

    var body: some View {
        Section("Відгук і підтримка") {
            NavigationLink {
                FeedbackFormView(kind: .rating, repository: repository, isSignedIn: isSignedIn)
            } label: {
                Label("Оцінити застосунок", systemImage: "star")
            }
            .accessibilityIdentifier("profile.feedback.rate")
            NavigationLink {
                FeedbackFormView(kind: .support, repository: repository, isSignedIn: isSignedIn)
            } label: {
                Label("Написати в підтримку", systemImage: "envelope")
            }
            .accessibilityIdentifier("profile.feedback.support")
        }
    }
}

struct FeedbackFormView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model: FeedbackViewModel

    init(kind: FeedbackViewModel.Kind, repository: any FeedbackRepository, isSignedIn: Bool) {
        _model = StateObject(
            wrappedValue: FeedbackViewModel(kind: kind, repository: repository, isSignedIn: isSignedIn)
        )
    }

    var body: some View {
        Form {
            if model.didSend {
                Section {
                    Label("Дякуємо! Повідомлення надіслано.", systemImage: "checkmark.circle")
                        .foregroundStyle(BeryndaColor.accent)
                        .accessibilityIdentifier("feedback.sent")
                    Button("Готово") { dismiss() }
                }
            } else {
                form
            }
        }
        .scrollContentBackground(.hidden)
        .background(BeryndaColor.paper)
        .navigationTitle(model.kind == .rating ? Text("Оцінити застосунок") : Text("Написати в підтримку"))
        .navigationBarTitleDisplayMode(.inline)
        .announcesChanges(of: model.errorMessage)
        .onChange(of: model.didSend) { _, sent in
            if sent { VoiceOver.announce(L("Дякуємо! Повідомлення надіслано.")) }
        }
    }

    @ViewBuilder
    private var form: some View {
        if model.kind == .rating {
            Section("Оцінка") {
                StarRatingPicker(rating: $model.rating)
            }
        }

        Section {
            TextField(
                model.kind == .rating ? L("Що сподобалося або що покращити?") : L("Опишіть, що сталося"),
                text: $model.message,
                axis: .vertical
            )
            .lineLimit(4...10)
            .accessibilityIdentifier("feedback.message")
        } header: {
            model.kind == .rating ? Text("Коментар (необов’язково)") : Text("Повідомлення")
        } footer: {
            Text(verbatim: "\(model.message.count) / \(model.maximumMessageLength)")
                .foregroundStyle(
                    model.message.count > model.maximumMessageLength ? Color.red : BeryndaColor.mutedInk
                )
                .accessibilityLabel(L("Символів: \(model.message.count) з \(model.maximumMessageLength)"))
        }

        contactSection

        if let error = model.errorMessage {
            Section {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("feedback.error")
            }
        }

        Section {
            Button {
                Task { await model.send() }
            } label: {
                HStack {
                    Text("Надіслати")
                    if model.isSending {
                        Spacer()
                        ProgressView()
                    }
                }
            }
            .disabled(model.isSending)
            .accessibilityIdentifier("feedback.send")
        }
    }

    @ViewBuilder
    private var contactSection: some View {
        if model.isSignedIn {
            Section {
                Text("Відповімо на адресу вашого облікового запису.")
                    .font(.footnote)
                    .foregroundStyle(BeryndaColor.mutedInk)
            }
        } else if model.kind == .rating {
            Section {
                TextField("Ім’я (необов’язково)", text: $model.name)
                    .textContentType(.name)
                    .accessibilityIdentifier("feedback.name")
                TextField("Електронна адреса (необов’язково)", text: $model.email)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("feedback.email")
            } header: {
                Text("Контакти")
            } footer: {
                Text("Можна залишити відгук анонімно.")
            }
        } else {
            Section {
                TextField("Електронна адреса для відповіді", text: $model.email)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("feedback.email")
            } header: {
                Text("Контакти")
            }
        }
    }
}

/// Five stars: each a 44-point button for touch, and together one adjustable
/// VoiceOver element ("Оцінка, 4 з 5 зірок", swipe up or down to change).
struct StarRatingPicker: View {
    @Binding var rating: Int?

    var body: some View {
        HStack(spacing: 4) {
            ForEach(1...5, id: \.self) { star in
                Button {
                    rating = star
                } label: {
                    // Each star takes a fifth of the row: a target well over
                    // 44 points that does not depend on the row's width.
                    Image(systemName: star <= (rating ?? 0) ? "star.fill" : "star")
                        .font(.title2)
                        .foregroundStyle(BeryndaColor.accent)
                        .frame(maxWidth: .infinity, minHeight: BeryndaHitTarget.minimum)
                        .contentShape(Rectangle())
                }
                // Plain style: several buttons in one form row each keep
                // their own tap instead of the row firing all of them.
                .buttonStyle(.plain)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Оцінка")
        .accessibilityValue(rating.map { L("\($0) з 5 зірок") } ?? L("Не вибрано"))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment:
                rating = min((rating ?? 0) + 1, 5)
            case .decrement:
                rating = max((rating ?? 2) - 1, 1)
            @unknown default:
                break
            }
        }
        .accessibilityIdentifier("feedback.rating")
    }
}
