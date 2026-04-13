import SwiftUI

// MARK: - Shared Empty States

struct InlineEmptyState: View {
    let systemImage: String
    let message: String
    var minHeight: CGFloat = 96

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.zone2Green)
                .frame(width: 36, height: 36)
                .background(
                    Circle()
                        .fill(Color.zone2Green.opacity(0.14))
                )

            Text(message)
                .font(.caption)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 240)
        }
        .frame(maxWidth: .infinity, minHeight: minHeight)
    }
}

struct FeatureEmptyStateCard: View {
    let systemImage: String
    let title: String
    let message: String
    var footnote: String? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 24, weight: .semibold))
                .foregroundColor(.zone2Green)
                .frame(width: 48, height: 48)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.zone2Green.opacity(0.14))
                )

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.headline)
                    .foregroundColor(.white)

                Text(message)
                    .font(.subheadline)
                    .foregroundColor(.gray)

                if let footnote, !footnote.isEmpty {
                    Text(footnote)
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.zone2Green)
                        .padding(.top, 2)
                }
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
