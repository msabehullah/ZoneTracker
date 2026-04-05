import SwiftUI
import Charts

// MARK: - Resting HR Sparkline

struct RestingHRSparkline: View {
    let data: [(date: Date, bpm: Int)]

    var body: some View {
        Chart {
            ForEach(data.indices, id: \.self) { i in
                LineMark(
                    x: .value("Date", data[i].date),
                    y: .value("BPM", data[i].bpm)
                )
                .foregroundStyle(Color.zone2Green.gradient)
                .interpolationMethod(.catmullRom)

                AreaMark(
                    x: .value("Date", data[i].date),
                    y: .value("BPM", data[i].bpm)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color.zone2Green.opacity(0.3), Color.zone2Green.opacity(0.0)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .interpolationMethod(.catmullRom)
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartYScale(domain: yDomain)
    }

    private var yDomain: ClosedRange<Int> {
        let bpms = data.map(\.bpm)
        let lo = (bpms.min() ?? 50) - 5
        let hi = (bpms.max() ?? 80) + 5
        return lo...hi
    }
}
