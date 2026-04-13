import AuthenticationServices
import SwiftUI

struct SignInView: View {
    @State private var accountStore = AccountStore.shared

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.black, Color(red: 0.06, green: 0.12, blue: 0.10)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("ZoneTracker")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)

                    Text("Adaptive cardio planning on iPhone, guided execution on Apple Watch.")
                        .font(.headline)
                        .foregroundStyle(Color.white.opacity(0.82))

                    Text("Sign in once on iPhone to keep your profile, recommendations, and completed workouts tied to one account.")
                        .font(.subheadline)
                        .foregroundStyle(Color.white.opacity(0.65))
                }

                VStack(alignment: .leading, spacing: 14) {
                    benefitRow(icon: "applewatch", title: "Watch-led workouts", detail: "Your next planned session syncs to the watch with live target coaching.")
                    benefitRow(icon: "cloud.fill", title: "Cloud-backed history", detail: "Profiles and completed workouts sync through your private iCloud database.")
                    benefitRow(icon: "heart.text.square.fill", title: "Health-first setup", detail: "Heart rate stays at the center of the training loop.")
                }
                .padding(20)
                .background(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(Color.white.opacity(0.08))
                        .overlay(
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .stroke(Color.white.opacity(0.08), lineWidth: 1)
                        )
                )

                SignInWithAppleButton(.signIn) { request in
                    request.requestedScopes = [.fullName, .email]
                } onCompletion: { result in
                    Task {
                        await accountStore.handleAuthorization(result: result)
                    }
                }
                .signInWithAppleButtonStyle(.white)
                .frame(height: 54)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                if let errorMessage = accountStore.lastErrorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                Spacer()
            }
            .padding(24)
        }
    }

    private func benefitRow(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.zone2Green)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.bold())
                    .foregroundStyle(.white)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(Color.white.opacity(0.68))
            }
        }
    }
}
