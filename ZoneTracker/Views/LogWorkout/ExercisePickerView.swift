import SwiftUI

// MARK: - Exercise Picker View

struct ExercisePickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selected: ExerciseType
    var onChange: () -> Void

    private let columns = [
        GridItem(.flexible()),
        GridItem(.flexible()),
        GridItem(.flexible())
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(ExerciseType.allCases) { exercise in
                        Button {
                            selected = exercise
                            onChange()
                            dismiss()
                        } label: {
                            VStack(spacing: 10) {
                                Image(systemName: exercise.sfSymbol)
                                    .font(.system(size: 32))
                                    .foregroundColor(selected == exercise ? .black : .zone2Green)

                                Text(exercise.displayName)
                                    .font(.caption)
                                    .foregroundColor(selected == exercise ? .black : .white)
                                    .multilineTextAlignment(.center)
                                    .lineLimit(2)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 20)
                            .background(selected == exercise ? Color.zone2Green : Color.cardBackground)
                            .cornerRadius(16)
                        }
                    }
                }
                .padding()
            }
            .background(Color.appBackground)
            .navigationTitle("Exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .foregroundColor(.zone2Green)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}
