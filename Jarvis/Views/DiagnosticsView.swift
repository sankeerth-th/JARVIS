import SwiftUI

struct DiagnosticsView: View {
    @EnvironmentObject private var viewModel: DiagnosticsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                JarvisSectionHeader(title: "System diagnostics", subtitle: "Service health and module status")
                Spacer()
                if let updated = viewModel.lastUpdated {
                    Text("Updated \(updated.formatted(date: .omitted, time: .standard))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(String(format: "%.0f ms", viewModel.latency * 1000))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Refresh", action: viewModel.refresh)
                    .buttonStyle(JarvisButtonStyle(tone: .primary))
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Services")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                List(viewModel.statuses) { status in
                    JarvisResultRow(
                        title: status.name,
                        subtitle: status.isHealthy ? "Healthy" : "Needs attention",
                        metadata: status.detail,
                        trailing: {
                            AnyView(
                                HStack(spacing: 6) {
                                    Image(systemName: status.isHealthy ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                        .foregroundStyle(status.isHealthy ? Color.green : Color.orange)
                                    Text(status.isHealthy ? "Operational" : "Investigate")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            )
                        }
                    )
                    .listRowBackground(Color.clear)
                }
                .scrollContentBackground(.hidden)
                .listStyle(.plain)
                .frame(minHeight: 150)
            }
            .padding(10)
            .jarvisCard(fill: JarvisPalette.panel, border: JarvisPalette.border, shadowOpacity: 0.03)

            VStack(alignment: .leading, spacing: 8) {
                Text("Modules")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(viewModel.moduleHealth) { module in
                    JarvisResultRow(
                        title: module.module,
                        subtitle: module.enabled ? "Enabled" : "Disabled",
                        metadata: module.lastRun?.formatted(date: .abbreviated, time: .shortened) ?? "Never run",
                        trailing: {
                            AnyView(
                                Label(
                                    module.permissionsOK ? "Permissions OK" : "Permissions missing",
                                    systemImage: module.permissionsOK ? "checkmark.shield" : "shield"
                                )
                                .font(.caption2)
                                .foregroundStyle(module.permissionsOK ? Color.green : Color.orange)
                            )
                        }
                    )
                }
            }
            .padding(10)
            .jarvisCard(fill: JarvisPalette.panel, border: JarvisPalette.border, shadowOpacity: 0.03)

            VStack(alignment: .leading, spacing: 8) {
                Text("Routing events")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if viewModel.routingEvents.isEmpty {
                    JarvisEmptyStateRow(
                        title: "No recent route events",
                        subtitle: "Events will appear as Jarvis handles tab and prompt routing."
                    )
                } else {
                    ForEach(viewModel.routingEvents.prefix(8)) { event in
                        JarvisResultRow(
                            title: event.summary,
                            subtitle: event.type,
                            metadata: event.createdAt.formatted(date: .omitted, time: .standard)
                        )
                    }
                }
            }
            .padding(10)
            .jarvisCard(fill: JarvisPalette.panel, border: JarvisPalette.border, shadowOpacity: 0.03)
        }
        .padding(10)
        .jarvisCard(fill: JarvisPalette.panelMuted, border: JarvisPalette.border, shadowOpacity: 0.02)
    }
}
