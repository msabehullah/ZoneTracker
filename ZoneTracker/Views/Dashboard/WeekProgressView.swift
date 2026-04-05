import SwiftUI

// MARK: - Week Progress View

struct WeekProgressView: View {
    let completed: Int
    let target: Int

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Text("This Week")
                    .font(.subheadline)
                    .foregroundColor(.gray)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(completed)")
                        .font(.system(size: 36, weight: .bold, design: .monospaced))
                        .foregroundColor(.zone2Green)
                    Text("/ \(target)")
                        .font(.system(.title3, design: .monospaced))
                        .foregroundColor(.gray)
                }
                Text("sessions completed")
                    .font(.caption)
                    .foregroundColor(.gray)
            }

            Spacer()

            VStack(spacing: 6) {
                ForEach(0..<target, id: \.self) { i in
                    HStack(spacing: 4) {
                        Circle()
                            .fill(i < completed ? Color.zone2Green : Color.cardBorder)
                            .frame(width: 14, height: 14)
                        if i < completed {
                            Image(systemName: "checkmark")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.zone2Green)
                        }
                    }
                }
            }
        }
        .padding()
        .background(Color.cardBackground)
        .cornerRadius(16)
    }
}
