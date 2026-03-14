import SwiftUI
import AppKit

struct ModernSearchView: View {
    @EnvironmentObject private var commandVM: CommandPaletteViewModel
    @EnvironmentObject private var settingsVM: SettingsViewModel
    @State private var searchText: String = ""
    
    var body: some View {
        VStack(spacing: 0) {
            // Search header
            VStack(spacing: 16) {
                HStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.secondary)
                    
                    TextField("Search documents...", text: $commandVM.knowledgeQuery)
                        .font(.system(size: 14))
                        .textFieldStyle(.plain)
                        .onSubmit {
                            commandVM.searchKnowledgeBase()
                        }
                    
                    if !commandVM.knowledgeQuery.isEmpty {
                        Button(action: { commandVM.knowledgeQuery = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    
                    Button(action: { commandVM.searchKnowledgeBase() }) {
                        Text("Search")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .buttonStyle(JarvisPrimaryButton())
                    .disabled(commandVM.knowledgeQuery.isEmpty)
                    
                    Button(action: pickFolder) {
                        Image(systemName: "folder.badge.plus")
                            .font(.system(size: 14))
                    }
                    .buttonStyle(JarvisSecondaryButton())
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor))
                        .shadow(color: .black.opacity(0.03), radius: 2, x: 0, y: 1)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
                )
                
                // Results count
                if !commandVM.knowledgeResults.isEmpty {
                    HStack {
                        let count = commandVM.knowledgeResults.count
                        Text("\(count) result\(count == 1 ? "" : "s")")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            
            // Results list
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(commandVM.knowledgeResults) { document in
                        KnowledgeResultRow(document: document)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                openDocument(document)
                            }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            
            if commandVM.knowledgeResults.isEmpty {
                Spacer()
                EmptySearchState()
                Spacer()
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
    
    private func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Add to Index"
        
        if panel.runModal() == .OK, let url = panel.urls.first {
            // Folder selection handled by CommandPaletteViewModel
        }
    }
    
    private func openDocument(_ document: IndexedDocument) {
        NSWorkspace.shared.open(URL(fileURLWithPath: document.path))
    }
}

private struct KnowledgeResultRow: View {
    let document: IndexedDocument
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: iconName)
                .font(.system(size: 24))
                .foregroundStyle(Color.accentColor)
                .frame(width: 40, height: 40)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.accentColor.opacity(0.1))
                )
            
            VStack(alignment: .leading, spacing: 4) {
                Text(document.title)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                
                Text(document.path)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                
                if !document.extractedText.isEmpty {
                    Text(document.extractedText.prefix(120))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .padding(.top, 2)
                }
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.tertiary)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
        )
    }
    
    private var iconName: String {
        let ext = URL(fileURLWithPath: document.path).pathExtension.lowercased()
        switch ext {
        case "pdf": return "doc.text"
        case "txt", "md", "markdown": return "doc.text"
        case "docx", "doc": return "doc.text.fill"
        case "png", "jpg", "jpeg", "heic": return "photo"
        default: return "doc"
        }
    }
}

private struct EmptySearchState: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass.circle")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            
            Text("Search your documents")
                .font(.system(size: 16, weight: .semibold))
            
            Text("Add folders to index and search across your files")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(32)
    }
}

private struct JarvisPrimaryButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.accentColor)
            )
            .foregroundStyle(.white)
            .opacity(configuration.isPressed ? 0.8 : 1.0)
    }
}

private struct JarvisSecondaryButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
            )
            .foregroundStyle(Color(nsColor: .labelColor))
            .opacity(configuration.isPressed ? 0.7 : 1.0)
    }
}
