import SwiftUI
import AppKit

struct KnowledgeBaseView: View {
    @EnvironmentObject private var commandVM: CommandPaletteViewModel
    @EnvironmentObject private var settingsVM: SettingsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                TextField("Search local docs", text: $commandVM.knowledgeQuery)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { commandVM.searchKnowledgeBase() }
                Button("Search", action: commandVM.searchKnowledgeBase)
                Button("Add folder", action: pickFolder)
            }
            if let status = settingsVM.indexingStatus {
                Text(status).font(.caption).foregroundStyle(.secondary)
            }
            List(commandVM.knowledgeResults) { doc in
                VStack(alignment: .leading) {
                    Text(doc.title).bold()
                    Text(doc.path).font(.caption2)
                }
            }
        }
        .padding(8)
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
