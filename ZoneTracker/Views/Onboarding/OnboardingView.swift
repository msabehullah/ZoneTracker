import SwiftUI
import SwiftData

// MARK: - Onboarding View

struct OnboardingView: View {
    @Environment(\.modelContext) private var context
    @Bindable var profile: UserProfile
    var onComplete: () -> Void

    @State private var step = 0
    @State private var ageText = "31"
    @State private var weightText = "150"
    @State private var heightFeet = 5
    @State private var heightInches = 8
    @State private var isRequestingHealthKit = false

    var body: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()

            VStack(spacing: 32) {
                // Progress dots
                HStack(spacing: 8) {
                    ForEach(0..<4) { i in
                        Circle()
                            .fill(i <= step ? Color.zone2Green : Color.cardBorder)
                            .frame(width: 8, height: 8)
                    }
                }
                .padding(.top, 20)

                Spacer()

                switch step {
                case 0: welcomeStep
                case 1: profileStep
                case 2: zonesStep
                case 3: healthKitStep
                default: EmptyView()
                }

                Spacer()

                Button(action: advance) {
                    Text(step == 3 ? "Get Started" : "Continue")
                        .font(.headline)
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.zone2Green)
                        .cornerRadius(14)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Step 1: Welcome

    private var welcomeStep: some View {
        VStack(spacing: 20) {
            Image(systemName: "heart.circle.fill")
                .font(.system(size: 80))
                .foregroundColor(.zone2Green)

            Text("ZoneTracker")
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .foregroundColor(.white)

            Text("A 3-phase progressive cardio plan\nthat adapts to your performance.")
                .font(.body)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            VStack(alignment: .leading, spacing: 12) {
                phaseRow("Phase 1", "Aerobic Base Building", "6 weeks")
                phaseRow("Phase 2", "Introducing Intervals", "6 weeks")
                phaseRow("Phase 3", "VO2 Max Development", "Ongoing")
            }
            .padding(20)
            .background(Color.cardBackground)
            .cornerRadius(16)
            .padding(.horizontal, 24)
        }
    }

    private func phaseRow(_ phase: String, _ title: String, _ duration: String) -> some View {
        HStack {
            Text(phase)
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.zone2Green)
                .frame(width: 60, alignment: .leading)
            VStack(alignment: .leading) {
                Text(title).font(.subheadline).foregroundColor(.white)
                Text(duration).font(.caption2).foregroundColor(.gray)
            }
            Spacer()
        }
    }

    // MARK: - Step 2: Profile

    private var profileStep: some View {
        VStack(spacing: 24) {
            Text("About You")
                .font(.title.bold())
                .foregroundColor(.white)

            VStack(spacing: 16) {
                profileField("Age", text: $ageText, suffix: "years")

                profileField("Weight", text: $weightText, suffix: "lbs")

                HStack(spacing: 12) {
                    Text("Height")
                        .foregroundColor(.gray)
                        .frame(width: 70, alignment: .leading)

                    Picker("Feet", selection: $heightFeet) {
                        ForEach(4...7, id: \.self) { Text("\($0) ft") }
                    }
                    .pickerStyle(.menu)
                    .tint(.white)

                    Picker("Inches", selection: $heightInches) {
                        ForEach(0...11, id: \.self) { Text("\($0) in") }
                    }
                    .pickerStyle(.menu)
                    .tint(.white)
                }
                .padding()
                .background(Color.cardBackground)
                .cornerRadius(12)
            }
            .padding(.horizontal, 24)
        }
    }

    private func profileField(_ label: String, text: Binding<String>, suffix: String) -> some View {
        HStack {
            Text(label)
                .foregroundColor(.gray)
                .frame(width: 70, alignment: .leading)
            TextField("", text: text)
                .keyboardType(.numberPad)
                .font(.system(.title3, design: .monospaced))
                .foregroundColor(.white)
            Text(suffix)
                .foregroundColor(.gray)
        }
        .padding()
        .background(Color.cardBackground)
        .cornerRadius(12)
    }

    // MARK: - Step 3: Zones

    private var zonesStep: some View {
        VStack(spacing: 20) {
            Text("Your HR Zones")
                .font(.title.bold())
                .foregroundColor(.white)

            let maxHR = 220 - (Int(ageText) ?? 31)

            Text("Max HR: \(maxHR) bpm")
                .font(.system(.title3, design: .monospaced))
                .foregroundColor(.zone2Green)

            VStack(spacing: 8) {
                zoneRow(.zone1, range: "< 130", calculator: HRZoneCalculator(maxHR: maxHR, zone2Override: 130...150))
                zoneRow(.zone2, range: "130–150", calculator: HRZoneCalculator(maxHR: maxHR, zone2Override: 130...150))
                zoneRow(.zone3, range: "151–\(Int(Double(maxHR) * 0.80))", calculator: HRZoneCalculator(maxHR: maxHR, zone2Override: 130...150))
                zoneRow(.zone4, range: "\(Int(Double(maxHR) * 0.80) + 1)–\(Int(Double(maxHR) * 0.90))", calculator: HRZoneCalculator(maxHR: maxHR, zone2Override: 130...150))
                zoneRow(.zone5, range: "\(Int(Double(maxHR) * 0.90) + 1)–\(maxHR)", calculator: HRZoneCalculator(maxHR: maxHR, zone2Override: 130...150))
            }
            .padding(20)
            .background(Color.cardBackground)
            .cornerRadius(16)
            .padding(.horizontal, 24)

            Text("Zone 2 target (130–150 bpm) is calibrated\nfor your training plan. Adjust in Settings.")
                .font(.caption)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
        }
    }

    private func zoneRow(_ zone: HRZone, range: String, calculator: HRZoneCalculator) -> some View {
        HStack {
            Circle().fill(zone.color).frame(width: 12, height: 12)
            Text(zone.displayName)
                .font(.system(.subheadline, design: .monospaced))
                .foregroundColor(.white)
                .frame(width: 60, alignment: .leading)
            Text(zone.description)
                .font(.caption)
                .foregroundColor(.gray)
            Spacer()
            Text(range)
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.white)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Step 4: HealthKit

    private var healthKitStep: some View {
        VStack(spacing: 24) {
            Image(systemName: "applewatch.and.arrow.forward")
                .font(.system(size: 60))
                .foregroundColor(.zone2Green)

            Text("Connect Health")
                .font(.title.bold())
                .foregroundColor(.white)

            Text("ZoneTracker reads heart rate data from your Apple Watch to track zones, measure progress, and adapt your workouts.")
                .font(.body)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            VStack(alignment: .leading, spacing: 12) {
                permissionRow("Heart rate during workouts")
                permissionRow("Resting heart rate trends")
                permissionRow("Workout logging to Health")
            }
            .padding(20)
            .background(Color.cardBackground)
            .cornerRadius(16)
            .padding(.horizontal, 24)
        }
    }

    private func permissionRow(_ text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.zone2Green)
            Text(text)
                .font(.subheadline)
                .foregroundColor(.white)
        }
    }

    // MARK: - Navigation

    private func advance() {
        if step == 1 {
            applyProfile()
        }

        if step == 3 {
            completeOnboarding()
            return
        }

        withAnimation(.easeInOut(duration: 0.3)) {
            step += 1
        }
    }

    private func applyProfile() {
        let age = Int(ageText) ?? 31
        profile.age = age
        profile.maxHR = 220 - age
        profile.weight = Double(weightText) ?? 150
        profile.height = Double(heightFeet * 12 + heightInches)
    }

    private func completeOnboarding() {
        applyProfile()
        profile.hasCompletedOnboarding = true
        profile.phaseStartDate = Date()

        Task {
            try? await HealthKitManager.shared.requestAuthorization()
        }

        onComplete()
    }
}
