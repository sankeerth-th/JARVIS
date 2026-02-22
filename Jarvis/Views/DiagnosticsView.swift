import SwiftUI

struct DiagnosticsView: View {
    @EnvironmentObject private var viewModel: DiagnosticsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button("Refresh", action: viewModel.refresh)
                    .buttonStyle(.borderedProminent)
                if let updated = viewModel.lastUpdated {
                    Text("Updated \(updated.formatted(date: .omitted, time: .standard))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("Latency: \(String(format: "%.2fs", viewModel.latency))")
                    .font(.headline)
            }

            List(viewModel.statuses) { status in
                HStack {
                    Circle()
                        .fill(status.isHealthy ? Color.green : Color.red)
                        .frame(width: 10, height: 10)
                    Text(status.name)
                    Spacer()
                    Text(status.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
                .listRowBackground(Color.clear)
            }
            .scrollContentBackground(.hidden)
            .background(Color.clear)
        }
        .padding(10)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.11), lineWidth: 1)
        )
    }
}
