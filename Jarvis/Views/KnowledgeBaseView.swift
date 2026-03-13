import SwiftUI
import AppKit

struct KnowledgeBaseView: View {
    @EnvironmentObject private var commandVM: CommandPaletteViewModel
    @EnvironmentObject private var settingsVM: SettingsViewModel

    var body: some View {
        ModernSearchView()
            .environmentObject(commandVM)
            .environmentObject(settingsVM)
    }
}

// Legacy view kept for reference - can be deleted after ModernSearchView is fully tested
struct LegacyKnowledgeBaseView: View {
    @EnvironmentObject private var commandVM: CommandPaletteViewModel
    @EnvironmentObject private var settingsVM: SettingsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            JarvisSectionHeader(title: "Knowledge base", subtitle: "Search OCR-indexed local documents")
            HStack {
                TextField("Search local docs", text: $commandVM.knowledgeQuery)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { commandVM.searchKnowledgeBase() }
                Button("Search", action: commandVM.searchKnowledgeBase)
                    .buttonStyle(JarvisButtonStyle(tone: .primary))
                Button("Add folder", action: pickFolder)
                    .buttonStyle(JarvisButtonStyle(tone: .secondary))
            }

            Text("PDF and image files are OCR-indexed locally for search.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if let status = settingsVM.indexingStatus {
                Text(status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(8)
                    .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }

            List(commandVM.knowledgeResults) { doc in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(doc.title)
                            .font(.body.weight(.semibold))
                        Text(doc.path)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Open") {
                        let url = URL(fileURLWithPath: doc.path)
                        NSWorkspace.shared.open(url)
                    }
                    .buttonStyle(JarvisButtonStyle(tone: .secondary))
                }
                .listRowBackground(Color.clear)
            }
            .scrollContentBackground(.hidden)
            .background(Color.clear)
        }
        .padding(10)
        .jarvisCard(fill: JarvisPalette.panelMuted, border: JarvisPalette.border, shadowOpacity: 0.02)
    }

    private func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.urls.first {
            settingsVM.indexFolder(url: url)
        }
    }
}
