import SwiftUI
import SwiftData

// MARK: - Settings View

struct SettingsView: View {
    @Query(sort: \WorkoutEntry.date, order: .reverse) private var workouts: [WorkoutEntry]
    @Bindable var profile: UserProfile
    @Environment(\.modelContext) private var context
    @State private var accountStore = AccountStore.shared
    @State private var syncCoordinator = AppSyncCoordinator.shared

    // Local editing state
    @State private var ageText: String = ""
    @State private var weightText: String = ""
    @State private var heightFeet: Int = 5
    @State private var heightInches: Int = 8
    @State private var zone2Low: Int = 130
    @State private var zone2High: Int = 150
    @State private var coachingHapticsEnabled = true
    @State private var coachingAlertCooldown = 18
    @State private var showingResetAlert = false
    @State private var showingSavedBanner = false
    @State private var showingExportShare = false
    @State private var exportURL: URL?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    accountSection
                    profileSection
                    zone2Section
                    coachingSection
                    legDaysSection
                    phaseSection
                    healthKitSection
                    notificationsSection
                    exportSection
                    dangerZone
                }
                .padding(.horizontal)
                .padding(.top, 16)
                .padding(.bottom, 28)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Color.appBackground)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
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
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .preferredColorScheme(.dark)
    }

    // MARK: - Profile Section

    private var accountSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Account")

            VStack(alignment: .leading, spacing: 6) {
                Text(accountStore.displayName ?? "Signed in with Apple")
                    .font(.subheadline.bold())
                    .foregroundColor(.white)
                Text(accountStore.email ?? "Private Apple relay or hidden email")
                    .font(.caption)
                    .foregroundColor(.gray)
                if let lastSyncDate = syncCoordinator.lastSyncDate {
                    Text("Last cloud sync: \(lastSyncDate.fullDate)")
                        .font(.caption2)
                        .foregroundColor(.gray)
                }
                if let syncError = syncCoordinator.lastSyncError {
                    Text(syncError)
                        .font(.caption2)
                        .foregroundColor(.orange)
                }
            }

            Button(role: .destructive) {
                accountStore.signOut()
            } label: {
                HStack {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                    Text("Sign Out")
                }
                .font(.subheadline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
            }
            .buttonStyle(.bordered)
            .tint(.red)
        }
        .settingsCard()
    }

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

    private var coachingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Coaching")

            Toggle(isOn: $coachingHapticsEnabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Watch Haptic Coaching")
                        .foregroundColor(.white)
                    Text("Alert when your heart rate leaves the active target range, then re-arm after you return.")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
            }
            .tint(.zone2Green)

            settingRow("Cooldown") {
                Stepper(
                    "\(coachingAlertCooldown) sec",
                    value: $coachingAlertCooldown,
                    in: 10...45,
                    step: 1
                )
                .font(.system(.body, design: .monospaced))
                .foregroundColor(.white)
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

    // MARK: - Notifications Section

    private var notificationsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Notifications")

            Text("Get reminded when you haven't trained in a while, and celebrate phase advancements.")
                .font(.caption)
                .foregroundColor(.gray)

            Button {
                Task {
                    await NotificationManager.shared.requestAuthorization()
                    NotificationManager.shared.scheduleInactivityReminder(
                        lastWorkoutDate: workouts.first?.date
                    )
                }
            } label: {
                HStack {
                    Image(systemName: "bell.badge")
                    Text("Enable Reminders")
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

    // MARK: - Export Section

    private var exportSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Data")

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(workouts.count) workouts")
                        .font(.subheadline)
                        .foregroundColor(.white)
                    Text("Export your full workout history as CSV")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                Spacer()
            }

            Button {
                let csv = DataExporter.exportCSV(workouts: workouts)
                exportURL = DataExporter.writeToTempFile(csv: csv)
                if exportURL != nil {
                    showingExportShare = true
                }
            } label: {
                HStack {
                    Image(systemName: "square.and.arrow.up")
                    Text("Export CSV")
                }
                .font(.subheadline)
                .foregroundColor(.zone2Green)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Color.cardBorder)
                .cornerRadius(10)
            }
            .buttonStyle(.plain)
            .disabled(workouts.isEmpty)
            .sheet(isPresented: $showingExportShare) {
                if let url = exportURL {
                    ShareSheet(items: [url])
                }
            }
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
        Text(title)
            .font(.system(.headline, design: .rounded).weight(.semibold))
            .foregroundColor(.white)
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
        coachingHapticsEnabled = profile.coachingHapticsEnabled
        coachingAlertCooldown = profile.coachingAlertCooldownSeconds
    }

    private func save() {
        let age = Int(ageText) ?? profile.age
        profile.age = age
        profile.maxHR = 220 - age
        profile.weight = Double(weightText) ?? profile.weight
        profile.height = Double(heightFeet * 12 + heightInches)
        profile.zone2TargetLow = min(zone2Low, zone2High - 5)
        profile.zone2TargetHigh = max(zone2High, zone2Low + 5)
        profile.coachingHapticsEnabled = coachingHapticsEnabled
        profile.coachingAlertCooldownSeconds = coachingAlertCooldown
        profile.accountIdentifier = accountStore.appleUserID

        ConnectivityManager.shared.sendCompanionProfile(
            WorkoutPlanningService.companionProfile(
                from: profile,
                accountIdentifier: accountStore.appleUserID
            ),
            preservePlan: false
        )
        syncCoordinator.synchronizeIfPossible(
            accountStore: accountStore,
            profile: profile,
            workouts: workouts,
            context: context
        )

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
            .appCard()
    }
}

// MARK: - Share Sheet

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
