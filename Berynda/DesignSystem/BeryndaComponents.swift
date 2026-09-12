import BeryndaCore
import SwiftUI

enum BeryndaSpacing {
    static let compact: CGFloat = 8
    static let standard: CGFloat = 16
    static let section: CGFloat = 24
}

struct BeryndaPanel<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(16)
            .background(BeryndaColor.surface, in: RoundedRectangle(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .stroke(BeryndaColor.border, lineWidth: 1)
            }
    }
}

struct BeryndaEmptyState: View {
    let title: String
    let message: String
    let systemImage: String

    var body: some View {
        ContentUnavailableView(title, systemImage: systemImage, description: Text(message))
            .foregroundStyle(BeryndaColor.ink)
    }
}

struct BeryndaLoadingState: View {
    let message: String

    var body: some View {
        VStack(spacing: BeryndaSpacing.standard) {
            ProgressView()
                .controlSize(.large)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(BeryndaColor.mutedInk)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }
}

struct BeryndaErrorState: View {
    let title: String
    let message: String
    let retry: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: "wifi.exclamationmark")
        } description: {
            Text(message)
        } actions: {
            Button("Спробувати ще раз", action: retry)
                .buttonStyle(.borderedProminent)
                .tint(BeryndaColor.accent)
        }
        .foregroundStyle(BeryndaColor.ink)
    }
}

struct BeryndaBookCover: View {
    let title: String
    var imageURL: URL? = nil
    /// Resolved once from the work (`work.coverDesign`) so the catalog list,
    /// the detail header, and the library all draw the same cover.
    let design: CoverDesign
    var width: CGFloat = 54
    var height: CGFloat = 78

    var body: some View {
        coverContent
            .frame(width: width, height: height)
            .clipShape(coverShape)
            .overlay {
                coverShape.stroke(.black.opacity(0.14), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.12), radius: 2, y: 1)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var coverContent: some View {
        if let imageURL {
            AsyncImage(url: imageURL, transaction: Transaction(animation: .easeInOut)) { phase in
                switch phase {
                case let .success(image):
                    image
                        .resizable()
                        .scaledToFill()
                case .empty, .failure:
                    generatedCover
                @unknown default:
                    generatedCover
                }
            }
        } else {
            generatedCover
        }
    }

    private var generatedCover: some View {
        let palette = BeryndaColor.coverPalette(for: design.tone)
        return Rectangle()
            .fill(palette.background)
            .overlay(alignment: .leading) {
                spine
            }
            .overlay {
                variantDecoration(ink: palette.ink)
            }
            .overlay {
                glyphView(ink: palette.ink)
            }
    }

    private var spine: some View {
        Rectangle()
            .fill(.black.opacity(0.16))
            .frame(width: max(width * 0.07, 3))
            .padding(.vertical, 2)
    }

    /// The three layout templates kept after the cover-pattern review:
    /// `plain` has no decoration, `frame` an inset rule, `label` a panel the
    /// glyph sits inside.
    @ViewBuilder
    private func variantDecoration(ink: Color) -> some View {
        switch design.variant {
        case .plain:
            EmptyView()
        case .frame:
            RoundedRectangle(cornerRadius: max(width * 0.07, 3), style: .continuous)
                .stroke(ink.opacity(0.38), lineWidth: 1)
                .padding(max(width * 0.1, 5))
        case .label:
            RoundedRectangle(cornerRadius: max(width * 0.05, 2), style: .continuous)
                .fill(ink.opacity(0.12))
                .overlay {
                    RoundedRectangle(cornerRadius: max(width * 0.05, 2), style: .continuous)
                        .stroke(ink.opacity(0.32), lineWidth: 1)
                }
                .padding(.horizontal, max(width * 0.12, 6))
                .padding(.vertical, max(height * 0.22, 10))
        }
    }

    @ViewBuilder
    private func glyphView(ink: Color) -> some View {
        if let glyph = design.glyph {
            Text(glyph)
                .font(BeryndaCoverFont.font(for: glyph, size: width * 0.42))
                .minimumScaleFactor(0.5)
                .foregroundStyle(ink)
                .padding(width * 0.14)
        }
    }

    private var coverShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: max(width * 0.09, 4), style: .continuous)
    }
}
