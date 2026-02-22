import SwiftUI

struct DiagnosticsView: View {
    @EnvironmentObject private var viewModel: DiagnosticsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button("Refresh", action: viewModel.refresh)
                if let updated = viewModel.lastUpdated {
                    Text("Updated \(updated.formatted(date: .omitted, time: .standard))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("Latency: \(String(format: "%.2fs", viewModel.latency))")
            }
            List(viewModel.statuses) { status in
                HStack {
                    Circle()
                        .fill(status.isHealthy ? Color.green : Color.red)
                        .frame(width: 8, height: 8)
                    Text(status.name)
                    Spacer()
                    Text(status.detail)
                        .font(.caption)
                }
            }
        }
        .padding(8)
    }
}
