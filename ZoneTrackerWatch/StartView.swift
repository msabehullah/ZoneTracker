import SwiftUI
import HealthKit

struct StartView: View {
    @EnvironmentObject var manager: WatchWorkoutManager
    @State private var navigateToWorkout = false
    @State private var navigateToSummary = false

    private let exercises: [(name: String, icon: String, type: HKWorkoutActivityType)] = [
        ("Treadmill", "figure.run", .running),
        ("Elliptical", "figure.elliptical", .elliptical),
        ("Stair Climber", "figure.stairs", .stairClimbing),
        ("Bike", "figure.indoor.cycle", .cycling),
        ("Rowing", "figure.rowing", .rowing),
        ("Outdoor Run", "figure.run.circle", .running),
        ("Rucking", "figure.hiking", .hiking)
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                Text("ZoneTracker")
                    .font(.system(.headline, design: .rounded))
                    .foregroundColor(.green)

                ForEach(exercises, id: \.name) { exercise in
                    Button {
                        startWorkout(type: exercise.type)
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: exercise.icon)
                                .font(.body)
                                .foregroundColor(.green)
                                .frame(width: 24)

                            Text(exercise.name)
                                .font(.system(size: 15))
                                .foregroundColor(.white)

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

    private func startWorkout(type: HKWorkoutActivityType) {
        Task {
            await manager.startWorkout(activityType: type)
        }
    }
}
