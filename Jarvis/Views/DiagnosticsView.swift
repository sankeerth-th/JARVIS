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
                LatencyPill(milliseconds: viewModel.latency * 1000)
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

            VStack(alignment: .leading, spacing: 8) {
                Text("Module Health")
                    .font(.headline)
                ForEach(viewModel.moduleHealth) { module in
                    HStack(spacing: 8) {
                        Circle()
                            .fill(module.enabled ? Color.green : Color.gray)
                            .frame(width: 8, height: 8)
                        Text(module.module)
                            .font(.subheadline)
                        Spacer()
                        Text(module.permissionsOK ? "Permissions OK" : "Permissions missing")
                            .font(.caption)
                            .foregroundStyle(module.permissionsOK ? .green : .orange)
                        Text(module.lastRun?.formatted(date: .abbreviated, time: .shortened) ?? "Never run")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }
            }
            .padding(10)
            .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.white.opacity(0.10), lineWidth: 1)
            )
        }
        .padding(10)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.11), lineWidth: 1)
        )
    }
}
