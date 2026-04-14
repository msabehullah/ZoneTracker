import SwiftUI
import SwiftData

// MARK: - Onboarding View

struct OnboardingView: View {
    @Environment(\.modelContext) private var context
    @Bindable var profile: UserProfile
    var onComplete: () -> Void

    @State private var step = 0
    private let totalSteps = 6

    // Profile fields
    @State private var ageText = "31"
    @State private var weightText = "150"
    @State private var heightFeet = 5
    @State private var heightInches = 8
    @State private var selectedSex = "notSet"

    // Goal fields
    @State private var selectedGoal: CardioGoal = .generalFitness
    @State private var targetEvent = ""
    @State private var targetEventDate = Date()
    @State private var hasEventDate = false

    // Fitness fields
    @State private var selectedFitness: FitnessLevel = .occasional
    @State private var cardioFrequency = 2
    @State private var typicalDuration = 30

    // Preference fields
    @State private var selectedModalities: Set<ExerciseType> = [.treadmill]
    @State private var availableDays = 3
    @State private var selectedConstraint: IntensityConstraint = .none

    @State private var didPreFill = false

    var body: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()

            VStack(spacing: 24) {
                // Progress dots
                HStack(spacing: 8) {
                    ForEach(0..<totalSteps, id: \.self) { i in
                        Circle()
                            .fill(i <= step ? Color.zone2Green : Color.cardBorder)
                            .frame(width: 8, height: 8)
                    }
                }
                .padding(.top, 20)

                Spacer()

                Group {
                    switch step {
                    case 0: welcomeStep
                    case 1: goalStep
                    case 2: fitnessStep
                    case 3: preferencesStep
                    case 4: profileStep
                    case 5: connectStep
                    default: EmptyView()
                    }
                }
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)
                ))

                Spacer()

                Button(action: advance) {
                    Text(step == totalSteps - 1 ? "Get Started" : "Continue")
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
        .task {
            guard !didPreFill else { return }
            didPreFill = true
            try? await HealthKitManager.shared.requestAuthorization()
            let chars = await HealthKitManager.shared.fetchUserCharacteristics()
            if let age = chars.age, (10...100).contains(age) {
                ageText = "\(age)"
            }
            if let weight = chars.weightLbs, weight > 0 {
                weightText = "\(Int(weight))"
            }
            if let totalInches = chars.heightInches, totalInches > 0 {
                heightFeet = Int(totalInches) / 12
                heightInches = Int(totalInches) % 12
            }
            if let sex = chars.biologicalSex {
                selectedSex = sex
            }
        }
    }

    // MARK: - Step 0: Welcome

    private var welcomeStep: some View {
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

    // MARK: - Step 1: Goal

    private var goalStep: some View {
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
                            selectedGoal = goal
                        }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: goal.icon)
                                .foregroundColor(selectedGoal == goal ? .black : .zone2Green)
                                .frame(width: 24)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(goal.displayName)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundColor(selectedGoal == goal ? .black : .white)
                                Text(goal.tagline)
                                    .font(.caption)
                                    .foregroundColor(selectedGoal == goal ? .black.opacity(0.7) : .gray)
                            }
                            Spacer()
                            if selectedGoal == goal {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.black.opacity(0.6))
                            }
                        }
                        .padding(14)
                        .background(selectedGoal == goal ? Color.zone2Green : Color.cardBackground)
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(selectedGoal == goal ? Color.clear : Color.cardBorder, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 24)

            // Event details (progressive disclosure)
            if selectedGoal == .raceTraining {
                VStack(spacing: 12) {
                    HStack {
                        Text("Event")
                            .foregroundColor(.gray)
                            .frame(width: 70, alignment: .leading)
                        TextField("e.g. 10K, Half Marathon", text: $targetEvent)
                            .font(.subheadline)
                            .foregroundColor(.white)
                    }
                    .padding()
                    .background(Color.cardBackground)
                    .cornerRadius(12)

                    Toggle(isOn: $hasEventDate) {
                        Text("I have a target date")
                            .foregroundColor(.gray)
                            .font(.subheadline)
                    }
                    .tint(.zone2Green)

                    if hasEventDate {
                        DatePicker("Event Date", selection: $targetEventDate, in: Date()..., displayedComponents: .date)
                            .datePickerStyle(.compact)
                            .tint(.zone2Green)
                    }
                }
                .padding(.horizontal, 24)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    // MARK: - Step 2: Fitness Assessment

    private var fitnessStep: some View {
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
                            selectedFitness = level
                        }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: level.icon)
                                .foregroundColor(selectedFitness == level ? .black : .zone2Green)
                                .frame(width: 24)
                            Text(level.displayName)
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(selectedFitness == level ? .black : .white)
                            Spacer()
                            if selectedFitness == level {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.black.opacity(0.6))
                            }
                        }
                        .padding(14)
                        .background(selectedFitness == level ? Color.zone2Green : Color.cardBackground)
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(selectedFitness == level ? Color.clear : Color.cardBorder, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 24)

            VStack(spacing: 14) {
                HStack {
                    Text("Cardio sessions per week")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                    Spacer()
                    Stepper("\(cardioFrequency)", value: $cardioFrequency, in: 0...7)
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(.white)
                        .frame(width: 130)
                }

                HStack {
                    Text("Typical session length")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                    Spacer()
                    Stepper("\(typicalDuration) min", value: $typicalDuration, in: 15...120, step: 5)
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(.white)
                        .frame(width: 160)
                }
            }
            .padding(.horizontal, 24)
        }
    }

    // MARK: - Step 3: Preferences

    private var preferencesStep: some View {
        VStack(spacing: 20) {
            Text("Training preferences")
                .font(.title.bold())
                .foregroundColor(.white)

            Text("Pick your preferred modalities.")
                .font(.subheadline)
                .foregroundColor(.gray)

            // Exercise type grid
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 10)], spacing: 10) {
                ForEach(ExerciseType.allCases) { type in
                    let isSelected = selectedModalities.contains(type)
                    Button {
                        if isSelected {
                            selectedModalities.remove(type)
                        } else {
                            selectedModalities.insert(type)
                        }
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
            }
            .padding(.horizontal, 24)

            VStack(spacing: 14) {
                HStack {
                    Text("Available training days")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                    Spacer()
                    Stepper("\(availableDays)/week", value: $availableDays, in: 2...7)
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(.white)
                        .frame(width: 150)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Intensity constraints")
                        .font(.subheadline)
                        .foregroundColor(.gray)

                    ForEach(IntensityConstraint.allCases) { constraint in
                        Button {
                            selectedConstraint = constraint
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: selectedConstraint == constraint
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

    // MARK: - Step 4: Profile

    private var profileStep: some View {
        VStack(spacing: 24) {
            Text("About You")
                .font(.title.bold())
                .foregroundColor(.white)

            Text("Used to calculate your heart rate zones.")
                .font(.subheadline)
                .foregroundColor(.gray)

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

                HStack {
                    Text("Sex")
                        .foregroundColor(.gray)
                        .frame(width: 70, alignment: .leading)

                    Picker("Sex", selection: $selectedSex) {
                        Text("Not Set").tag("notSet")
                        Text("Male").tag("male")
                        Text("Female").tag("female")
                        Text("Other").tag("other")
                    }
                    .pickerStyle(.menu)
                    .tint(.white)

                    Spacer()
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

    // MARK: - Step 5: Connect Health

    private var connectStep: some View {
        VStack(spacing: 24) {
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

            // Quick plan summary
            VStack(alignment: .leading, spacing: 8) {
                Text("YOUR PLAN")
                    .font(.system(.caption2, design: .rounded).bold())
                    .foregroundColor(.gray)
                    .kerning(1)

                HStack(spacing: 8) {
                    planSummaryPill(selectedGoal.shortName)
                    planSummaryPill(selectedFitness.displayName)
                    planSummaryPill("\(availableDays)×/week")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
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

    private func planSummaryPill(_ text: String) -> some View {
        Text(text)
            .font(.system(.caption, design: .monospaced).weight(.semibold))
            .foregroundColor(.zone2Green)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.zone2Green.opacity(0.15))
            .clipShape(Capsule())
    }

    // MARK: - Navigation

    private func advance() {
        if step == 4 {
            applyProfile()
        }

        if step == totalSteps - 1 {
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
        profile.biologicalSex = selectedSex
    }

    private func completeOnboarding() {
        applyProfile()

        // Apply goal-driven fields
        profile.primaryGoal = selectedGoal
        profile.fitnessLevel = selectedFitness
        profile.weeklyCardioFrequency = cardioFrequency
        profile.typicalWorkoutMinutes = typicalDuration
        profile.preferredModalities = selectedModalities.map(\.rawValue)
        profile.availableTrainingDays = availableDays
        profile.intensityConstraint = selectedConstraint
        profile.focus = selectedGoal.initialFocus
        profile.phaseStartDate = Date()

        if selectedGoal == .raceTraining {
            profile.targetEvent = targetEvent.isEmpty ? nil : targetEvent
            profile.targetEventDate = hasEventDate ? targetEventDate : nil
        }

        profile.hasCompletedOnboarding = true
        profile.accountIdentifier = AccountStore.shared.appleUserID

        Task {
            try? await HealthKitManager.shared.requestAuthorization()
        }

        onComplete()
    }
}
