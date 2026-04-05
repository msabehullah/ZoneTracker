import SwiftUI
import SwiftData

// MARK: - Settings View

struct SettingsView: View {
    @Bindable var profile: UserProfile
    @Environment(\.modelContext) private var context

    // Local editing state
    @State private var ageText: String = ""
    @State private var weightText: String = ""
    @State private var heightFeet: Int = 5
    @State private var heightInches: Int = 8
    @State private var zone2Low: Int = 130
    @State private var zone2High: Int = 150
    @State private var showingResetAlert = false
    @State private var showingSavedBanner = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    profileSection
                    zone2Section
                    legDaysSection
                    phaseSection
                    healthKitSection
                    dangerZone
                }
                .padding()
            }
            .background(Color.appBackground)
            .navigationTitle("Settings")
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .foregroundColor(.zone2Green)
                        .fontWeight(.semibold)
                }
            }
            .onAppear { loadCurrentValues() }
            .overlay(alignment: .top) {
                if showingSavedBanner {
                    savedBanner
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Profile Section

    private var profileSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Profile")

            settingRow("Age") {
                HStack {
                    TextField("31", text: $ageText)
                        .keyboardType(.numberPad)
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 60)
                    Text("years")
                        .foregroundColor(.gray)
                        .font(.subheadline)
                }
            }

            settingRow("Weight") {
                HStack {
                    TextField("150", text: $weightText)
                        .keyboardType(.numberPad)
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 60)
                    Text("lbs")
                        .foregroundColor(.gray)
                        .font(.subheadline)
                }
            }

            settingRow("Height") {
                HStack(spacing: 8) {
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
            }

            settingRow("Max HR") {
                Text("\(220 - (Int(ageText) ?? profile.age)) bpm")
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.gray)
            }
        }
        .settingsCard()
    }

    // MARK: - Zone 2 Section

    private var zone2Section: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Zone 2 Target")

            Text("Customize the heart rate range for Zone 2 workouts. Default is 130–150 bpm.")
                .font(.caption)
                .foregroundColor(.gray)

            settingRow("Lower Bound") {
                HStack {
                    Stepper("\(zone2Low) bpm", value: $zone2Low, in: 100...180)
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(.white)
                }
            }

            settingRow("Upper Bound") {
                HStack {
                    Stepper("\(zone2High) bpm", value: $zone2High, in: 110...200)
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(.white)
                }
            }

            // Zone preview bar
            GeometryReader { geo in
                let maxHR = Double(220 - (Int(ageText) ?? profile.age))
                let low = Double(zone2Low) / maxHR
                let high = Double(zone2High) / maxHR

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.cardBorder)
                        .frame(height: 8)
                    Capsule()
                        .fill(Color.zone2Green)
                        .frame(
                            width: (high - low) * geo.size.width,
                            height: 8
                        )
                        .offset(x: low * geo.size.width)
                }
            }
            .frame(height: 8)
            .padding(.top, 4)
        }
        .settingsCard()
    }

    // MARK: - Leg Days Section

    private var legDaysSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Heavy Leg Days")

            Text("The recommendation engine avoids high-intensity cardio on these days and the day after to allow leg recovery.")
                .font(.caption)
                .foregroundColor(.gray)

            HStack(spacing: 8) {
                ForEach(weekdaySymbols.indices, id: \.self) { i in
                    let weekday = i + 1 // weekday indices: 1=Sun ... 7=Sat
                    let isSelected = profile.legDays.contains(weekday)

                    Button {
                        toggleLegDay(weekday)
                    } label: {
                        Text(weekdaySymbols[i])
                            .font(.system(.caption, design: .rounded).bold())
                            .frame(width: 36, height: 36)
                            .background(isSelected ? Color.orange : Color.cardBorder)
                            .foregroundColor(isSelected ? .black : .gray)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .settingsCard()
    }

    private let weekdaySymbols = ["Su", "Mo", "Tu", "We", "Th", "Fr", "Sa"]

    private func toggleLegDay(_ weekday: Int) {
        if profile.legDays.contains(weekday) {
            profile.legDays.removeAll { $0 == weekday }
        } else {
            profile.legDays.append(weekday)
        }
    }

    // MARK: - Phase Section

    private var phaseSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Training Phase")

            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(profile.phase.displayName)
                        .font(.subheadline.bold())
                        .foregroundColor(.white)
                    Text(profile.phase.subtitle)
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                Spacer()
                Text("Week \(profile.weekNumber)")
                    .font(.system(.subheadline, design: .monospaced))
                    .foregroundColor(.zone2Green)
            }

            if profile.phase.next != nil {
                Text("Phase advances automatically when your performance criteria are met (see the Progress tab).")
                    .font(.caption)
                    .foregroundColor(.gray)
            } else {
                Text("You are in the final phase. Keep training!")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
        }
        .settingsCard()
    }

    // MARK: - HealthKit Section

    private var healthKitSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Health Integration")

            HStack {
                Image(systemName: "applewatch")
                    .foregroundColor(.zone2Green)
                Text("Apple Watch heart rate and workout data is used to personalize your recommendations.")
                    .font(.caption)
                    .foregroundColor(.gray)
            }

            Button {
                Task { try? await HealthKitManager.shared.requestAuthorization() }
            } label: {
                HStack {
                    Image(systemName: "arrow.triangle.2.circlepath")
                    Text("Re-authorize HealthKit")
                }
                .font(.subheadline)
                .foregroundColor(.zone2Green)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Color.cardBorder)
                .cornerRadius(10)
            }
            .buttonStyle(.plain)
        }
        .settingsCard()
    }

    // MARK: - Danger Zone

    private var dangerZone: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Reset")

            Button {
                showingResetAlert = true
            } label: {
                HStack {
                    Image(systemName: "arrow.counterclockwise")
                    Text("Reset to Phase 1")
                }
                .font(.subheadline)
                .foregroundColor(.red)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Color.red.opacity(0.15))
                .cornerRadius(10)
            }
            .buttonStyle(.plain)
            .alert("Reset Training Phase?", isPresented: $showingResetAlert) {
                Button("Reset", role: .destructive) { resetPhase() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will set you back to Phase 1, Week 1. Your workout history is preserved.")
            }
        }
        .settingsCard()
    }

    // MARK: - Saved Banner

    private var savedBanner: some View {
        Text("Settings Saved")
            .font(.subheadline.bold())
            .foregroundColor(.black)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(Color.zone2Green)
            .cornerRadius(20)
            .padding(.top, 8)
            .transition(.move(edge: .top).combined(with: .opacity))
    }

    // MARK: - Helpers

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(.caption, design: .rounded).bold())
            .foregroundColor(.gray)
            .kerning(1)
    }

    private func settingRow<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack {
            Text(label)
                .foregroundColor(.gray)
                .font(.subheadline)
                .frame(width: 100, alignment: .leading)
            Spacer()
            content()
        }
    }

    // MARK: - Data

    private func loadCurrentValues() {
        ageText = "\(profile.age)"
        weightText = "\(Int(profile.weight))"
        let totalInches = Int(profile.height)
        heightFeet = totalInches / 12
        heightInches = totalInches % 12
        zone2Low = profile.zone2TargetLow
        zone2High = profile.zone2TargetHigh
    }

    private func save() {
        let age = Int(ageText) ?? profile.age
        profile.age = age
        profile.maxHR = 220 - age
        profile.weight = Double(weightText) ?? profile.weight
        profile.height = Double(heightFeet * 12 + heightInches)
        profile.zone2TargetLow = min(zone2Low, zone2High - 5)
        profile.zone2TargetHigh = max(zone2High, zone2Low + 5)

        withAnimation(.spring(response: 0.3)) {
            showingSavedBanner = true
        }
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            withAnimation { showingSavedBanner = false }
        }
    }

    private func resetPhase() {
        profile.phase = .phase1
        profile.phaseStartDate = Date()
    }
}

// MARK: - View Extension

private extension View {
    func settingsCard() -> some View {
        self
            .padding()
            .background(Color.cardBackground)
            .cornerRadius(16)
    }
}
