import SwiftUI
<<<<<<< HEAD
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
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
                )
                
                // Status
                if let status = settingsVM.indexingStatus {
                    HStack {
                        ProgressView()
                            .controlSize(.small)
                        Text(status)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                }
                
                // Search status
                if !commandVM.fileSearchStatus.isEmpty {
                    HStack {
                        Text(commandVM.fileSearchStatus)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                }
            }
            .padding(16)
            
            Divider()
            
            // Results
            if commandVM.fileSearchStatus.contains("Searching") {
                ProgressView("Searching...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if commandVM.knowledgeResults.isEmpty && commandVM.fileSearchResults.isEmpty {
                if commandVM.knowledgeQuery.isEmpty {
                    EmptySearchState()
                } else {
                    NoResultsState(query: commandVM.knowledgeQuery)
                }
            } else {
                List {
                    Section(header: Text("Results").font(.caption).foregroundStyle(.secondary)) {
                        ForEach(commandVM.knowledgeResults) { doc in
                            SearchResultRow(document: doc)
                        }
                    }
                }
                .listStyle(.plain)
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
            settingsVM.indexFolder(url: url)
        }
    }
}

struct SearchResultRow: View {
    let document: IndexedDocument
    @State private var isHovered = false
    
    var body: some View {
        HStack(spacing: 12) {
            // File icon
            fileIcon
            
            // Content
            VStack(alignment: .leading, spacing: 4) {
                Text(document.title)
                    .font(.system(size: 13, weight: .medium))
                
                Text(document.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                
                if !document.extractedText.isEmpty {
                    Text(document.extractedText.prefix(100))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(2)
                }
            }
            
            Spacer()
            
            // Actions
            HStack(spacing: 8) {
                Button(action: { openDocument() }) {
                    Image(systemName: "arrow.up.forward")
                        .font(.system(size: 12))
                }
                .buttonStyle(.borderless)
                
                Button(action: { showInFinder() }) {
                    Image(systemName: "folder")
                        .font(.system(size: 12))
                }
                .buttonStyle(.borderless)
            }
            .opacity(isHovered ? 1 : 0)
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
        .contextMenu {
            Button("Open") { openDocument() }
            Button("Show in Finder") { showInFinder() }
            Button("Copy Path") { copyPath() }
        }
    }
    
    private var fileIcon: some View {
        let ext = (document.path as NSString).pathExtension.lowercased()
        let icon: String
        let color: Color
        
        switch ext {
        case "pdf":
            icon = "doc.text.fill"
            color = .red
        case "png", "jpg", "jpeg", "heic":
            icon = "photo.fill"
            color = .blue
        case "md", "txt":
            icon = "doc.text"
            color = .gray
        case "docx", "doc":
            icon = "doc.text.fill"
            color = .blue
        default:
            icon = "doc"
            color = .gray
        }
        
        return ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(color.opacity(0.15))
                .frame(width: 40, height: 40)
            
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(color)
        }
    }
    
    private func openDocument() {
        NSWorkspace.shared.open(URL(fileURLWithPath: document.path))
    }
    
    private func showInFinder() {
        NSWorkspace.shared.selectFile(document.path, inFileViewerRootedAtPath: "")
    }
    
    private func copyPath() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(document.path, forType: .string)
    }
}

struct EmptySearchState: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "folder.badge.questionmark")
                .font(.system(size: 48))
                .foregroundStyle(.secondary.opacity(0.5))
            
            Text("Search your documents")
                .font(.title3.weight(.semibold))
            
            Text("Add folders to index and search through PDFs, images, and text files")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            
            HStack(spacing: 16) {
                FeatureBadge(icon: "doc.text", title: "PDFs")
                FeatureBadge(icon: "photo", title: "Images")
                FeatureBadge(icon: "text.quote", title: "Text")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }
}

struct NoResultsState: View {
    let query: String
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "magnifyingglass.circle")
                .font(.system(size: 48))
                .foregroundStyle(.secondary.opacity(0.5))
            
            Text("No results for \"\(query)\"")
                .font(.headline)
            
            Text("Try different keywords or check your spelling")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }
}

struct FeatureBadge: View {
    let icon: String
    let title: String
    
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }
}

// Reuse the button styles from CommandPaletteView
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
=======

struct ModernSearchView: View {
    var body: some View {
        LegacyKnowledgeBaseView()
>>>>>>> f5a551d2c5aa8c8a00c5c9122826148403d5a6a2
    }
}
