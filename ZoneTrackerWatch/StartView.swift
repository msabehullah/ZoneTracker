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
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    header

                    if let plan = connectivity.currentPlan {
                        plannedWorkoutCard(plan: plan)
                    } else {
                        waitingForPlanCard
                    }

                    Text("Quick Start")
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
                                    .frame(width: 22)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(exerciseType.displayName)
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundColor(.white)
                                        .lineLimit(2)
                                        .fixedSize(horizontal: false, vertical: true)
                                    if let target = connectivity.companionProfile?.targetZoneRange.displayText {
                                        Text(target)
                                            .font(.system(size: 11, design: .monospaced))
                                            .foregroundColor(.gray)
                                            .lineLimit(1)
                                            .minimumScaleFactor(0.75)
                                    }
                                }

                                Spacer(minLength: 6)

                                Image(systemName: "chevron.right")
                                    .font(.caption2)
                                    .foregroundColor(.gray)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 8)
                            .padding(.horizontal, 10)
                            .background(Color(white: 0.15))
                            .cornerRadius(10)
                        }
                        .buttonStyle(.plain)
                        .disabled(connectivity.companionProfile == nil)
                    }
                }
                .frame(width: max(geometry.size.width - 8, 0), alignment: .leading)
                .padding(.vertical, 2)
            }
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
                Text(companionProfile.focus.displayName)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.gray)
            } else {
                Text("Open the iPhone app to sync your profile")
                    .font(.system(size: 12))
                    .foregroundColor(.gray)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func plannedWorkoutCard(plan: WorkoutExecutionPlan) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Next Planned Workout")
                .font(.system(.caption, design: .rounded).bold())
                .foregroundColor(.gray)

            HStack(alignment: .top, spacing: 8) {
                Image(systemName: plan.exerciseType.sfSymbol)
                    .font(.title3)
                    .foregroundColor(.green)
                    .frame(width: 22, height: 22, alignment: .topLeading)

                VStack(alignment: .leading, spacing: 4) {
                    Text(plan.sessionType.displayName)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(plan.exerciseType.displayName)
                        .font(.system(size: 12))
                        .foregroundColor(.gray)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 6) {
                    workoutBadge("\(plan.targetDurationMinutes) min")
                    workoutBadge(plan.overallTargetRange.displayText)
                    Spacer(minLength: 0)
                }

                VStack(alignment: .leading, spacing: 6) {
                    workoutBadge("\(plan.targetDurationMinutes) min")
                    workoutBadge(plan.overallTargetRange.displayText)
                }
            }

            if let firstSegment = plan.segments.first {
                Text("Starts with \(firstSegment.title)")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundColor(.orange)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button {
                Task {
                    await manager.startPlannedWorkout(plan)
                }
            } label: {
                Text("Start on Watch")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.black)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.green)
                    .cornerRadius(10)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
                .fixedSize(horizontal: false, vertical: true)
            if let target = connectivity.companionProfile?.targetZoneRange.displayText {
                Text("Quick start will use \(target)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.green)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(white: 0.12))
        .cornerRadius(14)
    }

    private func workoutBadge(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
            .foregroundColor(.green)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.green.opacity(0.14))
            .clipShape(Capsule())
    }
}
