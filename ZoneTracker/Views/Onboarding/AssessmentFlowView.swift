import SwiftUI

// MARK: - Assessment Flow View

/// Reusable multi-step assessment flow driven entirely by an ``AssessmentDraft``.
///
/// Used in two modes:
/// - ``AssessmentMode/initialOnboarding``: shown to first-time users, includes
///   the welcome screen and HealthKit connect step, finishes with "Get Started".
/// - ``AssessmentMode/editExisting``: shown from Settings, skips welcome, uses
///   a review step with "Update Plan" CTA, and surfaces a focus-reset
///   confirmation when the goal changes.
struct AssessmentFlowView: View {
    @Binding var draft: AssessmentDraft
    let mode: AssessmentMode
    /// Captured at presentation time in edit mode so we can detect goal changes.
    let originalGoal: CardioGoal?
    var onCancel: (() -> Void)?
    var onComplete: (_ resetFocus: Bool) -> Void

    @State private var stepIndex = 0
    @State private var didPreFill = false
    @State private var showingGoalResetConfirm = false

    // Shared focus state for every keyboard-bound input in the flow. Kept on
    // the parent so step transitions, Back/Continue, and flow completion all
    // dismiss the keyboard reliably — SwiftUI would otherwise strand focus
    // inside a now-invisible TabView page.
    enum Field: Hashable { case targetEvent, age, weight }
    @FocusState var focusedField: Field?

    private var steps: [AssessmentStep] { mode.steps }
    private var isLastStep: Bool { stepIndex == steps.count - 1 }

    init(
        draft: Binding<AssessmentDraft>,
        mode: AssessmentMode,
        originalGoal: CardioGoal? = nil,
        onCancel: (() -> Void)? = nil,
        onComplete: @escaping (_ resetFocus: Bool) -> Void
    ) {
        self._draft = draft
        self.mode = mode
        self.originalGoal = originalGoal
        self.onCancel = onCancel
        self.onComplete = onComplete
    }

    var body: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()

            VStack(spacing: 16) {
                header
                progressDots

                Spacer(minLength: 8)

                TabView(selection: $stepIndex) {
                    ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                        ScrollView {
                            stepView(for: step)
                                .padding(.bottom, 12)
                                // Tap outside an active text field to dismiss.
                                .contentShape(Rectangle())
                                .onTapGesture { focusedField = nil }
                        }
                        .scrollDismissesKeyboard(.interactively)
                        .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                // Any step change drops focus — covers swipe gestures, the
                // Back chevron, and programmatic advance.
                .onChange(of: stepIndex) { _, _ in focusedField = nil }
                .toolbar {
                    // NumberPad has no return key, so give every numeric
                    // field an explicit Done affordance.
                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer()
                        Button("Done") { focusedField = nil }
                    }
                }

                Spacer(minLength: 0)

                primaryButton
                    .padding(.horizontal, 24)
                    .padding(.bottom, 28)
            }
        }
        .preferredColorScheme(.dark)
        .task {
            guard !didPreFill, mode == .initialOnboarding else { return }
            didPreFill = true
            await preFillFromHealthKit()
        }
        .alert("Change your training focus?", isPresented: $showingGoalResetConfirm) {
            Button("Reset Focus", role: .destructive) { onComplete(true) }
            Button("Keep Current Focus") { onComplete(false) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Because your goal changed to \(draft.primaryGoal.displayName), your training focus will reset to \(draft.primaryGoal.initialFocus.displayName). Your workout history is preserved.")
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            if stepIndex > 0 {
                Button(action: goBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 34, height: 34)
                        .background(Color.cardBackground)
                        .clipShape(Circle())
                }
            } else if mode == .editExisting {
                Button(action: { onCancel?() }) {
                    Text("Cancel")
                        .font(.subheadline)
                        .foregroundColor(.zone2Green)
                }
            } else {
                Color.clear.frame(width: 34, height: 34)
            }

            Spacer()

            Text(mode == .editExisting ? "Update Plan" : "Set Up")
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                .foregroundColor(.gray)

            Spacer()

            // Symmetric spacer to center the title
            Color.clear.frame(width: 34, height: 34)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }

    private var progressDots: some View {
        HStack(spacing: 8) {
            ForEach(0..<steps.count, id: \.self) { i in
                Circle()
                    .fill(i <= stepIndex ? Color.zone2Green : Color.cardBorder)
                    .frame(width: 8, height: 8)
            }
        }
    }

    // MARK: - Step Body

    @ViewBuilder
    private func stepView(for step: AssessmentStep) -> some View {
        switch step {
        case .welcome:
            AssessmentWelcomeStep()
        case .goal:
            AssessmentGoalStep(draft: $draft, focus: $focusedField)
        case .fitness:
            AssessmentFitnessStep(draft: $draft)
        case .preferences:
            AssessmentPreferencesStep(draft: $draft)
        case .profile:
            AssessmentProfileStep(draft: $draft, focus: $focusedField)
        case .connect:
            AssessmentConnectStep(draft: draft)
        case .review:
            AssessmentReviewStep(draft: draft, goalChanged: goalChanged)
        }
    }

    // MARK: - Primary CTA

    private var primaryButton: some View {
        Button(action: advance) {
            Text(ctaTitle)
                .font(.headline)
                .foregroundColor(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.zone2Green)
                .cornerRadius(14)
        }
        .buttonStyle(.plain)
    }

    private var ctaTitle: String {
        if !isLastStep { return "Continue" }
        switch mode {
        case .initialOnboarding: return "Get Started"
        case .editExisting: return "Update Plan"
        }
    }

    // MARK: - Navigation

    private func goBack() {
        guard stepIndex > 0 else { return }
        focusedField = nil
        withAnimation(.easeInOut(duration: 0.25)) { stepIndex -= 1 }
    }

    private func advance() {
        focusedField = nil
        if !isLastStep {
            withAnimation(.easeInOut(duration: 0.25)) { stepIndex += 1 }
            return
        }

        // Final step — commit
        switch mode {
        case .initialOnboarding:
            onComplete(true)
        case .editExisting:
            if goalChanged {
                showingGoalResetConfirm = true
            } else {
                onComplete(false)
            }
        }
    }

    private var goalChanged: Bool {
        guard let originalGoal else { return false }
        return originalGoal != draft.primaryGoal
    }

    // MARK: - HealthKit Pre-fill

    private func preFillFromHealthKit() async {
        try? await HealthKitManager.shared.requestAuthorization()
        let chars = await HealthKitManager.shared.fetchUserCharacteristics()
        if let age = chars.age, (10...100).contains(age) {
            draft.age = age
        }
        if let weight = chars.weightLbs, weight > 0 {
            draft.weight = weight
        }
        if let totalInches = chars.heightInches, totalInches > 0 {
            draft.heightFeet = max(4, min(7, Int(totalInches) / 12))
            draft.heightInches = max(0, min(11, Int(totalInches) % 12))
        }
        if let sex = chars.biologicalSex {
            draft.biologicalSex = sex
        }
    }
}

// MARK: - Steps

enum AssessmentStep: Hashable {
    case welcome
    case goal
    case fitness
    case preferences
    case profile
    case connect
    case review
}

extension AssessmentMode {
    var steps: [AssessmentStep] {
        switch self {
        case .initialOnboarding:
            return [.welcome, .goal, .fitness, .preferences, .profile, .connect]
        case .editExisting:
            return [.goal, .fitness, .preferences, .profile, .review]
        }
    }
}

// MARK: - Welcome Step

private struct AssessmentWelcomeStep: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "heart.circle.fill")
                .font(.system(size: 80))
                .foregroundColor(.zone2Green)

            Text("ZoneTracker")
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .foregroundColor(.white)

            Text("Your personal cardio coach.\nLet's build a plan that fits your goals.")
                .font(.body)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            VStack(alignment: .leading, spacing: 14) {
                featureRow("figure.run", "Personalized coaching", "Workouts that adapt to your progress")
                featureRow("heart.fill", "Heart rate guidance", "Real-time target zone feedback on Apple Watch")
                featureRow("chart.line.uptrend.xyaxis", "Measurable progress", "Track your cardio fitness over time")
            }
            .padding(20)
            .background(Color.cardBackground)
            .cornerRadius(16)
            .padding(.horizontal, 24)
        }
    }

    private func featureRow(_ icon: String, _ title: String, _ subtitle: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(.zone2Green)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold)).foregroundColor(.white)
                Text(subtitle).font(.caption).foregroundColor(.gray)
            }
        }
    }
}

// MARK: - Goal Step

private struct AssessmentGoalStep: View {
    @Binding var draft: AssessmentDraft
    var focus: FocusState<AssessmentFlowView.Field?>.Binding

    var body: some View {
        VStack(spacing: 20) {
            Text("What's your goal?")
                .font(.title.bold())
                .foregroundColor(.white)

            Text("This shapes your entire training plan.")
                .font(.subheadline)
                .foregroundColor(.gray)

            VStack(spacing: 10) {
                ForEach(CardioGoal.allCases) { goal in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            draft.primaryGoal = goal
                        }
                    } label: {
                        goalRow(goal)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 24)

            if draft.primaryGoal == .raceTraining {
                raceDetails
                    .padding(.horizontal, 24)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private func goalRow(_ goal: CardioGoal) -> some View {
        let selected = draft.primaryGoal == goal
        return HStack(spacing: 12) {
            Image(systemName: goal.icon)
                .foregroundColor(selected ? .black : .zone2Green)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(goal.displayName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(selected ? .black : .white)
                Text(goal.tagline)
                    .font(.caption)
                    .foregroundColor(selected ? .black.opacity(0.7) : .gray)
            }
            Spacer()
            if selected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.black.opacity(0.6))
            }
        }
        .padding(14)
        .background(selected ? Color.zone2Green : Color.cardBackground)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(selected ? Color.clear : Color.cardBorder, lineWidth: 1)
        )
    }

    private var raceDetails: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Event")
                    .foregroundColor(.gray)
                    .frame(width: 70, alignment: .leading)
                TextField("e.g. 10K, Half Marathon", text: $draft.targetEvent)
                    .font(.subheadline)
                    .foregroundColor(.white)
                    .focused(focus, equals: .targetEvent)
                    .submitLabel(.done)
                    .onSubmit { focus.wrappedValue = nil }
            }
            .padding()
            .background(Color.cardBackground)
            .cornerRadius(12)

            Toggle(isOn: $draft.hasEventDate) {
                Text("I have a target date")
                    .foregroundColor(.gray)
                    .font(.subheadline)
            }
            .tint(.zone2Green)

            if draft.hasEventDate {
                DatePicker(
                    "Event Date",
                    selection: $draft.targetEventDate,
                    in: Date()...,
                    displayedComponents: .date
                )
                .datePickerStyle(.compact)
                .tint(.zone2Green)
            }
        }
    }
}

// MARK: - Fitness Step

private struct AssessmentFitnessStep: View {
    @Binding var draft: AssessmentDraft

    private let dayOptions = [2, 3, 4, 5, 6, 7]
    private let durationOptions = [20, 30, 45, 60, 75, 90]

    var body: some View {
        VStack(spacing: 20) {
            Text("Your fitness today")
                .font(.title.bold())
                .foregroundColor(.white)

            Text("No judgment — this helps calibrate your plan.")
                .font(.subheadline)
                .foregroundColor(.gray)

            VStack(spacing: 10) {
                ForEach(FitnessLevel.allCases) { level in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            draft.fitnessLevel = level
                        }
                    } label: {
                        levelRow(level)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 24)

            if !draft.isBeginner {
                routineInputs
                    .padding(.horizontal, 24)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            } else {
                beginnerNote
                    .padding(.horizontal, 24)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: draft.isBeginner)
    }

    private func levelRow(_ level: FitnessLevel) -> some View {
        let selected = draft.fitnessLevel == level
        return HStack(spacing: 12) {
            Image(systemName: level.icon)
                .foregroundColor(selected ? .black : .zone2Green)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(level.displayName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(selected ? .black : .white)
                Text(level.subtitle)
                    .font(.caption)
                    .foregroundColor(selected ? .black.opacity(0.7) : .gray)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            if selected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.black.opacity(0.6))
            }
        }
        .padding(14)
        .background(selected ? Color.zone2Green : Color.cardBackground)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(selected ? Color.clear : Color.cardBorder, lineWidth: 1)
        )
    }

    private var routineInputs: some View {
        VStack(spacing: 16) {
            chipPicker(
                title: "Sessions per week",
                options: dayOptions,
                selection: $draft.weeklyCardioFrequency,
                label: { "\($0)" }
            )

            chipPicker(
                title: "Typical session length",
                options: durationOptions,
                selection: $draft.typicalWorkoutMinutes,
                label: { "\($0) min" }
            )
        }
    }

    private var beginnerNote: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "sparkles")
                .foregroundColor(.zone2Green)
                .font(.subheadline)
            Text("We'll start you with short, easy sessions and build from there. You can change the pace anytime.")
                .font(.caption)
                .foregroundColor(.gray)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.cardBackground)
        .cornerRadius(12)
    }

    private func chipPicker<T: Hashable>(
        title: String,
        options: [T],
        selection: Binding<T>,
        label: @escaping (T) -> String
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline)
                .foregroundColor(.gray)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(options, id: \.self) { option in
                        let selected = selection.wrappedValue == option
                        Button {
                            selection.wrappedValue = option
                        } label: {
                            Text(label(option))
                                .font(.system(.subheadline, design: .monospaced).weight(.semibold))
                                .foregroundColor(selected ? .black : .white)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(selected ? Color.zone2Green : Color.cardBackground)
                                .cornerRadius(10)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(selected ? Color.clear : Color.cardBorder, lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

// MARK: - Preferences Step

private struct AssessmentPreferencesStep: View {
    @Binding var draft: AssessmentDraft

    private let dayOptions = [2, 3, 4, 5, 6, 7]

    var body: some View {
        VStack(spacing: 20) {
            Text("Training preferences")
                .font(.title.bold())
                .foregroundColor(.white)

            Text("Pick your preferred modalities.")
                .font(.subheadline)
                .foregroundColor(.gray)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 10)], spacing: 10) {
                ForEach(ExerciseType.allCases) { type in
                    modalityTile(type)
                }
            }
            .padding(.horizontal, 24)

            VStack(spacing: 16) {
                chipPicker(
                    title: "Available training days",
                    options: dayOptions,
                    selection: $draft.availableTrainingDays,
                    label: { "\($0)/week" }
                )

                VStack(alignment: .leading, spacing: 8) {
                    Text("Intensity constraints")
                        .font(.subheadline)
                        .foregroundColor(.gray)

                    ForEach(IntensityConstraint.allCases) { constraint in
                        Button {
                            draft.intensityConstraint = constraint
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: draft.intensityConstraint == constraint
                                    ? "circle.inset.filled" : "circle")
                                    .foregroundColor(.zone2Green)
                                    .font(.body)
                                Text(constraint.displayName)
                                    .font(.subheadline)
                                    .foregroundColor(.white)
                                Spacer()
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 24)
        }
    }

    private func modalityTile(_ type: ExerciseType) -> some View {
        let isSelected = draft.selectedModalities.contains(type)
        let isPrimary = draft.selectedModalities.first == type
        return Button {
            draft.toggleModality(type)
        } label: {
            VStack(spacing: 6) {
                Image(systemName: type.sfSymbol)
                    .font(.title3)
                    .foregroundColor(isSelected ? .black : .zone2Green)
                Text(type.displayName)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(isSelected ? .black : .white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .multilineTextAlignment(.center)
                if isPrimary {
                    Text("PRIMARY")
                        .font(.system(size: 9, weight: .heavy, design: .rounded))
                        .foregroundColor(.black.opacity(0.7))
                        .kerning(0.5)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 72)
            .background(isSelected ? Color.zone2Green : Color.cardBackground)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.clear : Color.cardBorder, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func chipPicker<T: Hashable>(
        title: String,
        options: [T],
        selection: Binding<T>,
        label: @escaping (T) -> String
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline)
                .foregroundColor(.gray)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(options, id: \.self) { option in
                        let selected = selection.wrappedValue == option
                        Button {
                            selection.wrappedValue = option
                        } label: {
                            Text(label(option))
                                .font(.system(.subheadline, design: .monospaced).weight(.semibold))
                                .foregroundColor(selected ? .black : .white)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(selected ? Color.zone2Green : Color.cardBackground)
                                .cornerRadius(10)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(selected ? Color.clear : Color.cardBorder, lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

// MARK: - Profile Step

private struct AssessmentProfileStep: View {
    @Binding var draft: AssessmentDraft
    var focus: FocusState<AssessmentFlowView.Field?>.Binding

    @State private var ageText: String = ""
    @State private var weightText: String = ""

    var body: some View {
        VStack(spacing: 20) {
            Text("About You")
                .font(.title.bold())
                .foregroundColor(.white)

            Text("Used to calculate your heart rate zones.")
                .font(.subheadline)
                .foregroundColor(.gray)

            VStack(spacing: 10) {
                numericCard(
                    label: "Age",
                    text: $ageText,
                    suffix: "years",
                    field: .age,
                    commit: {
                        draft.age = max(10, min(100, Int(ageText) ?? draft.age))
                    }
                )

                numericCard(
                    label: "Weight",
                    text: $weightText,
                    suffix: "lbs",
                    field: .weight,
                    commit: {
                        draft.weight = max(50, min(500, Double(weightText) ?? draft.weight))
                    }
                )

                heightCard
                sexCard
            }
            .padding(.horizontal, 24)
        }
        .onAppear {
            if ageText.isEmpty { ageText = "\(draft.age)" }
            if weightText.isEmpty { weightText = "\(Int(draft.weight))" }
        }
        .onChange(of: ageText) { _, new in
            if let value = Int(new), (10...100).contains(value) {
                draft.age = value
            }
        }
        .onChange(of: weightText) { _, new in
            if let value = Double(new), (50...500).contains(value) {
                draft.weight = value
            }
        }
    }

    private func numericCard(
        label: String,
        text: Binding<String>,
        suffix: String,
        field: AssessmentFlowView.Field,
        commit: @escaping () -> Void
    ) -> some View {
        HStack {
            Text(label)
                .foregroundColor(.gray)
                .frame(width: 70, alignment: .leading)
            TextField("", text: text)
                .keyboardType(.numberPad)
                .font(.system(.title3, design: .monospaced))
                .foregroundColor(.white)
                .focused(focus, equals: field)
                .onSubmit(commit)
            Text(suffix)
                .foregroundColor(.gray)
                .font(.subheadline)
        }
        .padding(.horizontal, 14)
        .frame(height: 52)
        .background(Color.cardBackground)
        .cornerRadius(12)
    }

    private var heightCard: some View {
        HStack(spacing: 8) {
            Text("Height")
                .foregroundColor(.gray)
                .frame(width: 70, alignment: .leading)
            Spacer()
            Picker("Feet", selection: $draft.heightFeet) {
                ForEach(4...7, id: \.self) { Text("\($0) ft").tag($0) }
            }
            .pickerStyle(.menu)
            .tint(.white)

            Picker("Inches", selection: $draft.heightInches) {
                ForEach(0...11, id: \.self) { Text("\($0) in").tag($0) }
            }
            .pickerStyle(.menu)
            .tint(.white)
        }
        .padding(.horizontal, 14)
        .frame(height: 52)
        .background(Color.cardBackground)
        .cornerRadius(12)
    }

    private var sexCard: some View {
        HStack {
            Text("Sex")
                .foregroundColor(.gray)
                .frame(width: 70, alignment: .leading)
            Picker("Sex", selection: $draft.biologicalSex) {
                Text("Not Set").tag("notSet")
                Text("Male").tag("male")
                Text("Female").tag("female")
                Text("Other").tag("other")
            }
            .pickerStyle(.menu)
            .tint(.white)
            Spacer()
        }
        .padding(.horizontal, 14)
        .frame(height: 52)
        .background(Color.cardBackground)
        .cornerRadius(12)
    }
}

// MARK: - Connect Step (initial onboarding only)

private struct AssessmentConnectStep: View {
    let draft: AssessmentDraft

    var body: some View {
        VStack(spacing: 22) {
            Image(systemName: "applewatch.and.arrow.forward")
                .font(.system(size: 60))
                .foregroundColor(.zone2Green)

            Text("Connect Health")
                .font(.title.bold())
                .foregroundColor(.white)

            Text("ZoneTracker reads heart rate data from your Apple Watch to guide coaching, measure progress, and adapt your workouts.")
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

            planSummary
                .padding(.horizontal, 24)
        }
    }

    /// Starting target for a brand-new user (week 1 = no ramp bumps yet).
    /// Mirrors `UserProfile.baselineSessionsPerWeek` logic so the connect
    /// step shows the same number the plan overview will.
    private var startingTarget: Int {
        let baseline: Int
        if draft.fitnessLevel == .beginner {
            baseline = 2
        } else {
            baseline = max(1, min(7, draft.effectiveWeeklyCardioFrequency))
        }
        let ceiling = max(1, min(7, draft.availableTrainingDays))
        return max(1, min(ceiling, baseline))
    }

    private var hasBuildHeadroom: Bool {
        let ceiling = max(1, min(7, draft.availableTrainingDays))
        return ceiling > startingTarget
    }

    private var planSummary: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("YOUR PLAN")
                .font(.system(.caption2, design: .rounded).bold())
                .foregroundColor(.gray)
                .kerning(1)

            FlexibleWrap(spacing: 8) {
                planSummaryPill(draft.primaryGoal.shortName)
                planSummaryPill(draft.fitnessLevel.displayName)
                planSummaryPill("Starting \(startingTarget)×/week")
                if hasBuildHeadroom {
                    planSummaryPill("→ \(draft.availableTrainingDays)×/week")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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

    private func planSummaryPill(_ text: String) -> some View {
        Text(text)
            .font(.system(.caption, design: .monospaced).weight(.semibold))
            .foregroundColor(.zone2Green)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.zone2Green.opacity(0.15))
            .clipShape(Capsule())
    }
}

// MARK: - Review Step (edit mode only)

private struct AssessmentReviewStep: View {
    let draft: AssessmentDraft
    let goalChanged: Bool

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 54))
                .foregroundColor(.zone2Green)

            Text("Review your plan")
                .font(.title.bold())
                .foregroundColor(.white)

            Text("Confirm the changes below and we'll update your training plan.")
                .font(.subheadline)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            VStack(spacing: 10) {
                reviewRow(label: "Goal", value: draft.primaryGoal.displayName)
                reviewRow(label: "Fitness", value: draft.fitnessLevel.displayName)
                reviewRow(label: "Training days", value: "\(draft.availableTrainingDays) per week")
                if !draft.isBeginner {
                    reviewRow(label: "Typical session", value: "\(draft.typicalWorkoutMinutes) min")
                }
                reviewRow(label: "Modalities", value: modalitySummary)
                if draft.intensityConstraint != IntensityConstraint.none {
                    reviewRow(label: "Constraint", value: draft.intensityConstraint.displayName)
                }
            }
            .padding(.horizontal, 24)

            if goalChanged {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                        .font(.subheadline)
                    Text("Your training focus will reset to \(draft.primaryGoal.initialFocus.displayName) because your goal changed. Workout history is preserved.")
                        .font(.caption)
                        .foregroundColor(.white)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.orange.opacity(0.15))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.orange.opacity(0.4), lineWidth: 1)
                )
                .cornerRadius(10)
                .padding(.horizontal, 24)
            }
        }
    }

    private var modalitySummary: String {
        draft.selectedModalities
            .map(\.displayName)
            .joined(separator: ", ")
    }

    private func reviewRow(label: String, value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.subheadline)
                .foregroundColor(.gray)
                .frame(width: 110, alignment: .leading)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.white)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.cardBackground)
        .cornerRadius(10)
    }
}

// MARK: - FlexibleWrap

/// Minimal flow layout for the plan summary pills.
private struct FlexibleWrap<Content: View>: View {
    var spacing: CGFloat = 8
    @ViewBuilder var content: () -> Content

    var body: some View {
        HStack(spacing: spacing) { content() }
    }
}
