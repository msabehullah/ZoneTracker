import SwiftUI
import SwiftData

// MARK: - Settings View

/// Settings screen follows a clear read-only → edit → save pattern:
///
/// * By default, the screen renders persisted profile values as **read-only**
///   cards. No accidental taps can mutate the profile.
/// * Tapping **Edit** lifts the persisted values into a local
///   ``SettingsDraft``. Controls become editable. A **Save** button appears
///   in the toolbar, and **Edit** turns into **Cancel**.
/// * Tapping **Cancel** discards the draft. Tapping **Save** commits it once,
///   syncs to Watch + CloudKit, and exits edit mode with a confirmation
///   banner.
///
/// Edit Assessment is a separate pathway and is not part of this draft flow —
/// it opens the reusable ``AssessmentFlowView`` which has its own Cancel/Save.
struct SettingsView: View {
    @Query(sort: \WorkoutEntry.date, order: .reverse) private var workouts: [WorkoutEntry]
    @Bindable var profile: UserProfile
    @Environment(\.modelContext) private var context
    @State private var accountStore = AccountStore.shared
    @State private var syncCoordinator = AppSyncCoordinator.shared

    // Edit-mode state
    @State private var isEditing = false
    @State private var draft: SettingsDraft = .empty
    @State private var showingResetAlert = false
    @State private var showingSavedBanner = false
    @State private var showingExportShare = false
    @State private var exportURL: URL?

    // Assessment edit sheet state (separate pathway)
    @State private var showingAssessmentEdit = false
    @State private var assessmentDraft: AssessmentDraft = .blank
    @State private var assessmentOriginalGoal: CardioGoal = .generalFitness

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    accountSection
                    profileSection
                    targetZoneSection
                    coachingSection
                    legDaysSection
                    goalSection
                    healthKitSection
                    notificationsSection
                    exportSection
                    dangerZone
                    signOutSection
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
            .toolbar { toolbarContent }
            .overlay(alignment: .top) {
                if showingSavedBanner {
                    savedBanner
                }
            }
            .sheet(isPresented: $showingAssessmentEdit) {
                AssessmentFlowView(
                    draft: $assessmentDraft,
                    mode: .editExisting,
                    originalGoal: assessmentOriginalGoal,
                    onCancel: { showingAssessmentEdit = false },
                    onComplete: { resetFocus in
                        commitAssessmentEdit(resetFocus: resetFocus)
                    }
                )
                .interactiveDismissDisabled()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .preferredColorScheme(.dark)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if isEditing {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { cancelEditing() }
                    .foregroundColor(.gray)
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { saveEditing() }
                    .foregroundColor(.zone2Green)
                    .fontWeight(.semibold)
            }
        } else {
            ToolbarItem(placement: .confirmationAction) {
                Button("Edit") { beginEditing() }
                    .foregroundColor(.zone2Green)
                    .fontWeight(.semibold)
            }
        }
    }

    // MARK: - Account

    private var accountSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Account")

            VStack(alignment: .leading, spacing: 6) {
                Text(accountStore.emailPresentation)
                    .font(.subheadline.bold())
                    .foregroundColor(.white)
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
        }
        .settingsCard()
    }

    // MARK: - Profile

    private var profileSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Profile")

            if isEditing {
                settingRow("Age") {
                    HStack {
                        TextField("31", text: $draft.ageText)
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
                        TextField("150", text: $draft.weightText)
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
                        Picker("Feet", selection: $draft.heightFeet) {
                            ForEach(4...7, id: \.self) { Text("\($0) ft") }
                        }
                        .pickerStyle(.menu)
                        .tint(.white)

                        Picker("Inches", selection: $draft.heightInches) {
                            ForEach(0...11, id: \.self) { Text("\($0) in") }
                        }
                        .pickerStyle(.menu)
                        .tint(.white)
                    }
                }
            } else {
                readOnlyRow("Age", value: "\(profile.age) years")
                readOnlyRow("Weight", value: "\(Int(profile.weight)) lbs")
                readOnlyRow("Height", value: formatHeight(totalInches: Int(profile.height)))
            }

            settingRow("Max HR") {
                Text("\(220 - previewAge) bpm")
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.gray)
            }
        }
        .settingsCard()
    }

    // MARK: - Target Zone

    private var targetZoneSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Target Zone")

            Text("Customize the heart rate range for target zone workouts. Default is 130–150 bpm.")
                .font(.caption)
                .foregroundColor(.gray)

            if isEditing {
                settingRow("Lower Bound") {
                    Stepper("\(draft.zone2Low) bpm", value: $draft.zone2Low, in: 100...180)
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(.white)
                }

                settingRow("Upper Bound") {
                    Stepper("\(draft.zone2High) bpm", value: $draft.zone2High, in: 110...200)
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(.white)
                }
            } else {
                readOnlyRow("Lower Bound", value: "\(profile.zone2TargetLow) bpm")
                readOnlyRow("Upper Bound", value: "\(profile.zone2TargetHigh) bpm")
            }

            // Zone preview bar reflects the draft value while editing so the
            // user can see their change in context before saving.
            GeometryReader { geo in
                let maxHR = Double(220 - previewAge)
                let low = Double(previewZoneLow) / maxHR
                let high = Double(previewZoneHigh) / maxHR

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.cardBorder)
                        .frame(height: 8)
                    Capsule()
                        .fill(Color.zone2Green)
                        .frame(
                            width: max(0, (high - low)) * geo.size.width,
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

    // MARK: - Coaching

    private var coachingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Coaching")

            if isEditing {
                Toggle(isOn: $draft.coachingHapticsEnabled) {
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
                        "\(draft.coachingAlertCooldown) sec",
                        value: $draft.coachingAlertCooldown,
                        in: 10...45,
                        step: 1
                    )
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.white)
                }
            } else {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Watch Haptic Coaching")
                            .foregroundColor(.white)
                            .font(.subheadline)
                        Text("Alert when your heart rate leaves the active target range.")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                    Spacer()
                    Text(profile.coachingHapticsEnabled ? "On" : "Off")
                        .font(.system(.subheadline, design: .monospaced))
                        .foregroundColor(profile.coachingHapticsEnabled ? .zone2Green : .gray)
                }

                readOnlyRow("Cooldown", value: "\(profile.coachingAlertCooldownSeconds) sec")
            }
        }
        .settingsCard()
    }

    // MARK: - Leg Days

    private var legDaysSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Heavy Leg Days")

            Text("The recommendation engine avoids high-intensity cardio on these days and the day after to allow leg recovery.")
                .font(.caption)
                .foregroundColor(.gray)

            let source = isEditing ? draft.legDays : profile.legDays

            HStack(spacing: 8) {
                ForEach(weekdaySymbols.indices, id: \.self) { i in
                    let weekday = i + 1
                    let isSelected = source.contains(weekday)

                    Button {
                        guard isEditing else { return }
                        toggleDraftLegDay(weekday)
                    } label: {
                        Text(weekdaySymbols[i])
                            .font(.system(.caption, design: .rounded).bold())
                            .frame(width: 36, height: 36)
                            .background(isSelected ? Color.orange : Color.cardBorder)
                            .foregroundColor(isSelected ? .black : .gray)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .disabled(!isEditing)
                    .opacity(isEditing || isSelected ? 1 : 0.75)
                }
            }
        }
        .settingsCard()
    }

    private let weekdaySymbols = ["Su", "Mo", "Tu", "We", "Th", "Fr", "Sa"]

    private func toggleDraftLegDay(_ weekday: Int) {
        if draft.legDays.contains(weekday) {
            draft.legDays.removeAll { $0 == weekday }
        } else {
            draft.legDays.append(weekday)
        }
    }

    // MARK: - Goal & Focus Section

    private var goalSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Coaching Plan")

            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(profile.primaryGoal.displayName)
                        .font(.subheadline.bold())
                        .foregroundColor(.white)
                    Text(profile.focus.displayName)
                        .font(.caption)
                        .foregroundColor(.zone2Green)
                }
                Spacer()
                Text("Week \(profile.weekNumber)")
                    .font(.system(.subheadline, design: .monospaced))
                    .foregroundColor(.zone2Green)
            }

            Text(profile.focus.subtitle)
                .font(.caption)
                .foregroundColor(.gray)

            if profile.focus.next != nil {
                Text("Your focus advances automatically when your performance criteria are met.")
                    .font(.caption)
                    .foregroundColor(.gray)
            } else {
                Text("You are at peak performance focus. Keep training!")
                    .font(.caption)
                    .foregroundColor(.gray)
            }

            Button {
                openAssessmentEditor()
            } label: {
                HStack {
                    Image(systemName: "slider.horizontal.3")
                    Text("Edit Assessment")
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.gray)
                }
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.zone2Green)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .padding(.horizontal, 12)
                .background(Color.cardBorder)
                .cornerRadius(10)
            }
            .buttonStyle(.plain)
        }
        .settingsCard()
    }

    private func openAssessmentEditor() {
        assessmentDraft = AssessmentDraft.from(profile: profile)
        assessmentOriginalGoal = profile.primaryGoal
        showingAssessmentEdit = true
    }

    private func commitAssessmentEdit(resetFocus: Bool) {
        assessmentDraft.apply(to: profile, resetFocus: resetFocus)
        profile.accountIdentifier = accountStore.appleUserID
        showingAssessmentEdit = false

        // Refresh the settings draft in case the user also has edit mode
        // open — keeps the two in sync so an accidental Save later won't
        // clobber the assessment commit with stale values.
        if isEditing {
            draft = SettingsDraft(profile: profile)
        }

        // Explicit persist — assessment edits were surviving in-session but
        // losing on cold relaunch when autosave didn't flush before exit.
        do {
            try context.save()
        } catch {
            print("Assessment edit commit failed to save: \(error)")
        }

        ConnectivityManager.shared.sendCompanionProfile(
            WorkoutPlanningService.companionProfile(
                from: profile,
                accountIdentifier: accountStore.appleUserID
            ),
            preservePlan: !resetFocus
        )
        syncCoordinator.synchronizeIfPossible(
            accountStore: accountStore,
            profile: profile,
            workouts: workouts,
            context: context
        )

        flashSavedBanner()
    }

    // MARK: - HealthKit Section

    private var healthKitSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Health Integration")

            HStack {
                Image(systemName: "applewatch")
                    .foregroundColor(.zone2Green)
                Text("Apple Watch heart rate and workout data is used to personalize your coaching.")
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

            Text("Get reminded when you haven't trained in a while, and celebrate when your focus advances.")
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
                    Text("Reset Training")
                }
                .font(.subheadline)
                .foregroundColor(.red)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Color.red.opacity(0.15))
                .cornerRadius(10)
            }
            .buttonStyle(.plain)
            .alert("Reset Training?", isPresented: $showingResetAlert) {
                Button("Reset", role: .destructive) { resetFocus() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will reset your training focus to the beginning. Your workout history is preserved.")
            }
        }
        .settingsCard()
    }

    private var signOutSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Session")

            Button(role: .destructive) {
                accountStore.signOut()
            } label: {
                HStack {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                    Text("Sign Out")
                }
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
            }
            .buttonStyle(.bordered)
            .tint(.red)
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

    private func readOnlyRow(_ label: String, value: String) -> some View {
        settingRow(label) {
            Text(value)
                .font(.system(.body, design: .monospaced))
                .foregroundColor(.white)
        }
    }

    private func formatHeight(totalInches: Int) -> String {
        "\(totalInches / 12) ft \(totalInches % 12) in"
    }

    // Preview values that reflect the draft when editing, else the persisted profile.
    private var previewAge: Int {
        isEditing ? (Int(draft.ageText) ?? profile.age) : profile.age
    }

    private var previewZoneLow: Int {
        isEditing ? draft.zone2Low : profile.zone2TargetLow
    }

    private var previewZoneHigh: Int {
        isEditing ? draft.zone2High : profile.zone2TargetHigh
    }

    // MARK: - Edit Lifecycle

    private func beginEditing() {
        draft = SettingsDraft(profile: profile)
        withAnimation(.easeInOut(duration: 0.2)) { isEditing = true }
    }

    private func cancelEditing() {
        // Discard draft — revert to persisted values.
        withAnimation(.easeInOut(duration: 0.2)) { isEditing = false }
        draft = .empty
    }

    private func saveEditing() {
        draft.apply(to: profile)
        profile.accountIdentifier = accountStore.appleUserID

        // Explicit persist — profile edits were surviving in-session but
        // losing on cold relaunch when autosave didn't flush before exit.
        do {
            try context.save()
        } catch {
            print("Settings edit commit failed to save: \(error)")
        }

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

        withAnimation(.easeInOut(duration: 0.2)) { isEditing = false }
        draft = .empty
        flashSavedBanner()
    }

    private func flashSavedBanner() {
        withAnimation(.spring(response: 0.3)) { showingSavedBanner = true }
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            withAnimation { showingSavedBanner = false }
        }
    }

    private func resetFocus() {
        profile.focus = profile.primaryGoal.initialFocus
        profile.phaseStartDate = Date()
    }
}

// MARK: - Settings Draft

/// Local editable state for the settings screen. Never touches
/// ``UserProfile`` until ``apply(to:)`` is called on Save.
///
/// Strings for age / weight keep parity with the `TextField` bindings —
/// they are coerced at apply-time so intermediate "" or partial input
/// doesn't corrupt the live profile.
struct SettingsDraft: Equatable {
    var ageText: String
    var weightText: String
    var heightFeet: Int
    var heightInches: Int
    var zone2Low: Int
    var zone2High: Int
    var coachingHapticsEnabled: Bool
    var coachingAlertCooldown: Int
    var legDays: [Int]

    static let empty = SettingsDraft(
        ageText: "",
        weightText: "",
        heightFeet: 5,
        heightInches: 8,
        zone2Low: 130,
        zone2High: 150,
        coachingHapticsEnabled: true,
        coachingAlertCooldown: 18,
        legDays: []
    )

    init(
        ageText: String,
        weightText: String,
        heightFeet: Int,
        heightInches: Int,
        zone2Low: Int,
        zone2High: Int,
        coachingHapticsEnabled: Bool,
        coachingAlertCooldown: Int,
        legDays: [Int]
    ) {
        self.ageText = ageText
        self.weightText = weightText
        self.heightFeet = heightFeet
        self.heightInches = heightInches
        self.zone2Low = zone2Low
        self.zone2High = zone2High
        self.coachingHapticsEnabled = coachingHapticsEnabled
        self.coachingAlertCooldown = coachingAlertCooldown
        self.legDays = legDays
    }

    init(profile: UserProfile) {
        let totalInches = Int(profile.height)
        self.ageText = "\(profile.age)"
        self.weightText = "\(Int(profile.weight))"
        self.heightFeet = max(4, min(7, totalInches / 12))
        self.heightInches = max(0, min(11, totalInches % 12))
        self.zone2Low = profile.zone2TargetLow
        self.zone2High = profile.zone2TargetHigh
        self.coachingHapticsEnabled = profile.coachingHapticsEnabled
        self.coachingAlertCooldown = profile.coachingAlertCooldownSeconds
        self.legDays = profile.legDays
    }

    /// Commit the draft back to `profile`. Coerces string inputs and
    /// enforces an always-valid zone window (≥5 bpm gap).
    func apply(to profile: UserProfile) {
        let age = Int(ageText) ?? profile.age
        profile.age = age
        profile.maxHR = 220 - age
        profile.weight = Double(weightText) ?? profile.weight
        profile.height = Double(heightFeet * 12 + heightInches)
        profile.zone2TargetLow = min(zone2Low, zone2High - 5)
        profile.zone2TargetHigh = max(zone2High, zone2Low + 5)
        profile.coachingHapticsEnabled = coachingHapticsEnabled
        profile.coachingAlertCooldownSeconds = coachingAlertCooldown
        profile.legDays = legDays.sorted()
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
