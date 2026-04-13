import SwiftUI

struct StartView: View {
    @EnvironmentObject var manager: WatchWorkoutManager
    @EnvironmentObject var connectivity: WatchConnectivityManager

    @State private var navigateToWorkout = false
    @State private var navigateToSummary = false

    private let freeWorkoutOptions: [ExerciseType] = [
        .treadmill,
        .elliptical,
        .stairClimber,
        .bike,
        .rowing,
        .outdoorRun,
        .rucking
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                header

                if let plan = connectivity.currentPlan {
                    plannedWorkoutCard(plan: plan)
                } else {
                    waitingForPlanCard
                }

                Text("Free Workout")
                    .font(.system(.caption, design: .rounded).bold())
                    .foregroundColor(.gray)
                    .padding(.top, 4)

                ForEach(freeWorkoutOptions) { exerciseType in
                    Button {
                        Task {
                            await manager.startFreeWorkout(exerciseType: exerciseType)
                        }
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: exerciseType.sfSymbol)
                                .font(.body)
                                .foregroundColor(.green)
                                .frame(width: 24)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(exerciseType.displayName)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(.white)
                                if let zone2 = connectivity.companionProfile?.zone2TargetRange.displayText {
                                    Text(zone2)
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundColor(.gray)
                                }
                            }

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.caption2)
                                .foregroundColor(.gray)
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 10)
                        .background(Color(white: 0.15))
                        .cornerRadius(10)
                    }
                    .buttonStyle(.plain)
                    .disabled(connectivity.companionProfile == nil)
                }
            }
            .padding(.horizontal, 4)
        }
        .navigationDestination(isPresented: $navigateToWorkout) {
            LiveWorkoutView()
        }
        .navigationDestination(isPresented: $navigateToSummary) {
            WorkoutSummaryView()
        }
        .task {
            await manager.requestAuthorization()
            manager.updateCompanionProfile(connectivity.companionProfile)
        }
        .onChange(of: connectivity.companionProfile) { _, newValue in
            manager.updateCompanionProfile(newValue)
        }
        .onChange(of: manager.sessionState) { _, newState in
            if newState == .running || newState == .paused {
                navigateToWorkout = true
                navigateToSummary = false
            } else if newState == .ended || newState == .stopped {
                navigateToWorkout = false
                navigateToSummary = true
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("ZoneTracker")
                .font(.system(.headline, design: .rounded))
                .foregroundColor(.green)
            if let companionProfile = connectivity.companionProfile {
                Text(companionProfile.phase.displayName)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.gray)
            } else {
                Text("Open the iPhone app to sync your profile")
                    .font(.system(size: 12))
                    .foregroundColor(.gray)
            }
        }
    }

    private func plannedWorkoutCard(plan: WorkoutExecutionPlan) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Next Planned Workout")
                .font(.system(.caption, design: .rounded).bold())
                .foregroundColor(.gray)

            HStack(alignment: .top, spacing: 10) {
                Image(systemName: plan.exerciseType.sfSymbol)
                    .font(.title2)
                    .foregroundColor(.green)

                VStack(alignment: .leading, spacing: 4) {
                    Text(plan.sessionType.displayName)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                    Text(plan.exerciseType.displayName)
                        .font(.system(size: 12))
                        .foregroundColor(.gray)
                    Text("\(plan.targetDurationMinutes) min · \(plan.overallTargetRange.displayText)")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.green)
                    if let firstSegment = plan.segments.first {
                        Text(firstSegment.title)
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundColor(.orange)
                    }
                }

                Spacer()
            }

            Button {
                Task {
                    await manager.startPlannedWorkout(plan)
                }
            } label: {
                Text("Start on Watch")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.green)
                    .cornerRadius(10)
            }
        }
        .padding(12)
        .background(Color(white: 0.12))
        .cornerRadius(14)
    }

    private var waitingForPlanCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Next Planned Workout")
                .font(.system(.caption, design: .rounded).bold())
                .foregroundColor(.gray)
            Text("Open the iPhone app and send your next planned workout to the watch.")
                .font(.system(size: 13))
                .foregroundColor(.white)
            if let zone2 = connectivity.companionProfile?.zone2TargetRange.displayText {
                Text("Free workouts will use \(zone2)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.green)
            }
        }
        .padding(12)
        .background(Color(white: 0.12))
        .cornerRadius(14)
    }
}
