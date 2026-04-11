import SwiftUI
import AppKit
import ScreenCaptureKit

// MARK: - Apple-Native Design System

private enum JarvisColors {
    static let background = Color(nsColor: .windowBackgroundColor)
    static let secondaryBackground = Color(nsColor: .controlBackgroundColor)
    static let tertiaryBackground = Color(nsColor: .underPageBackgroundColor)
    static let label = Color(nsColor: .labelColor)
    static let secondaryLabel = Color(nsColor: .secondaryLabelColor)
    static let tertiaryLabel = Color(nsColor: .tertiaryLabelColor)
    static let separator = Color(nsColor: .separatorColor)
    static let accent = Color.accentColor
}

private enum JarvisLayout {
    static let small: CGFloat = 8
    static let medium: CGFloat = 12
    static let large: CGFloat = 16
    static let cornerSmall: CGFloat = 6
    static let cornerMedium: CGFloat = 10
}

private struct JarvisPrimaryButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: JarvisLayout.cornerSmall, style: .continuous)
                    .fill(JarvisColors.accent)
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
                RoundedRectangle(cornerRadius: JarvisLayout.cornerSmall, style: .continuous)
                    .fill(JarvisColors.secondaryBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: JarvisLayout.cornerSmall, style: .continuous)
                    .stroke(JarvisColors.separator, lineWidth: 0.5)
            )
            .foregroundStyle(JarvisColors.label)
            .opacity(configuration.isPressed ? 0.7 : 1.0)
    }
}

// MARK: - App Sections

enum JarvisSection: String, CaseIterable, Identifiable {
    case chat, notifications, documents, email, search, diagnostics, privacy, macros, thinking
    
    var id: String { rawValue }
    
    var title: String {
        switch self {
        case .chat: return "Chat"
        case .notifications: return "Notifications"
        case .documents: return "Documents"
        case .email: return "Email"
        case .search: return "Search"
        case .diagnostics: return "Diagnostics"
        case .privacy: return "Privacy"
        case .macros: return "Macros"
        case .thinking: return "Thinking"
        }
    }
    
    var icon: String {
        switch self {
        case .chat: return "bubble.left.and.bubble.right"
        case .notifications: return "bell"
        case .documents: return "doc.text"
        case .email: return "envelope"
        case .search: return "magnifyingglass"
        case .diagnostics: return "stethoscope"
        case .privacy: return "hand.raised"
        case .macros: return "bolt.badge.clock"
        case .thinking: return "brain"
        }
    }
}

// MARK: - Redesigned Command Palette

struct CommandPaletteView: View {
    @EnvironmentObject private var commandVM: CommandPaletteViewModel
    @EnvironmentObject private var notificationVM: NotificationViewModel
    @EnvironmentObject private var emailVM: EmailDraftViewModel
    @EnvironmentObject private var diagnosticsVM: DiagnosticsViewModel
    @EnvironmentObject private var settingsVM: SettingsViewModel
    
    @State private var selectedSection: JarvisSection = .chat
    @State private var searchText: String = ""
    @State private var showDiagnosticsPanel: Bool = false
    
    var body: some View {
        NavigationSplitView {
            SidebarView(
                selectedSection: $selectedSection,
                ollamaReachable: commandVM.ollamaReachable
            )
            .frame(minWidth: 200, idealWidth: 220)
        } detail: {
            DetailView(
                section: selectedSection,
                showDiagnostics: $showDiagnosticsPanel
            )
            .inspector(isPresented: $showDiagnosticsPanel) {
                DiagnosticsInspector()
                    .inspectorColumnWidth(min: 280, ideal: 320)
            }
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 900, minHeight: 600)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

// MARK: - Sidebar

struct SidebarView: View {
    @Binding var selectedSection: JarvisSection
    let ollamaReachable: Bool
    
    var body: some View {
        List(JarvisSection.allCases, selection: $selectedSection) { section in
            NavigationLink(value: section) {
                Label(section.title, systemImage: section.icon)
                    .font(.system(size: 13))
                    .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
                    .padding(.vertical, 4)
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Jarvis")
        .toolbar {
            ToolbarItem {
                ConnectionStatusIndicator(isConnected: ollamaReachable)
            }
        }
        .safeAreaInset(edge: .bottom) {
            SidebarFooter()
        }
    }
}

struct ConnectionStatusIndicator: View {
    let isConnected: Bool
    
    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(isConnected ? Color.green : Color.orange)
                .frame(width: 6, height: 6)
            
            Text(isConnected ? "Ready" : "Offline")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Color.secondary.opacity(0.1))
        )
    }
}

struct SidebarFooter: View {
    @State private var showSettings = false
    
    var body: some View {
        VStack(spacing: 0) {
            Divider()
            
            HStack(spacing: 8) {
                Button(action: { showSettings = true }) {
                    Image(systemName: "gear")
                        .font(.system(size: 14))
                }
                .buttonStyle(.borderless)
                .help("Settings")
                
                Spacer()
                
                Button(action: openHelp) {
                    Image(systemName: "questionmark.circle")
                        .font(.system(size: 14))
                }
                .buttonStyle(.borderless)
                .help("Help")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color(nsColor: .controlBackgroundColor))
        }
        .sheet(isPresented: $showSettings) {
            SettingsSheet()
        }
    }
    
    private func openHelp() {
        if let url = URL(string: "https://github.com/openclaw/openclaw") {
            NSWorkspace.shared.open(url)
        }
    }
}

struct SettingsSheet: View {
    @EnvironmentObject private var settingsVM: SettingsViewModel
    @EnvironmentObject private var notificationVM: NotificationViewModel
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            SettingsView()
                .navigationTitle("Settings")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") {
                            dismiss()
                        }
                    }
                }
        }
        .frame(minWidth: 500, minHeight: 400)
    }
}

// MARK: - Detail View

struct DetailView: View {
    let section: JarvisSection
    @Binding var showDiagnostics: Bool
    
    @EnvironmentObject private var commandVM: CommandPaletteViewModel
    @EnvironmentObject private var notificationVM: NotificationViewModel
    @EnvironmentObject private var emailVM: EmailDraftViewModel
    @EnvironmentObject private var diagnosticsVM: DiagnosticsViewModel
    @EnvironmentObject private var settingsVM: SettingsViewModel
    
    var body: some View {
        Group {
            switch section {
            case .chat:
                ChatSection()
            case .notifications:
                NotificationsSection()
            case .documents:
                DocumentsSection()
            case .email:
                EmailSection()
            case .search:
                SearchSection()
            case .diagnostics:
                DiagnosticsSection(showPanel: $showDiagnostics)
            case .privacy:
                PrivacySection()
            case .macros:
                MacrosSection()
            case .thinking:
                ThinkingSection()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button(action: { showDiagnostics.toggle() }) {
                    Image(systemName: "sidebar.right")
                        .font(.system(size: 14))
                }
                .buttonStyle(.borderless)
                .help("Toggle Inspector")
            }
        }
    }
}

// MARK: - Section Views

struct ChatSection: View {
    @EnvironmentObject private var commandVM: CommandPaletteViewModel
    @FocusState private var isInputFocused: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            // Messages area
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 16) {
                        ForEach(commandVM.conversation.messages) { message in
                            MessageBubble(message: message)
                                .id(message.id)
                        }
                        if commandVM.isStreaming {
                            TypingIndicator()
                                .id("typing")
                        }
                    }
                    .padding(24)
                }
                .onChange(of: commandVM.conversation.messages.count) { _ in
                    if let last = commandVM.conversation.messages.last {
                        withAnimation {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
                .onChange(of: commandVM.streamingBuffer) { _ in
                    withAnimation {
                        proxy.scrollTo("typing", anchor: .bottom)
                    }
                }
            }
            
            Divider()
            
            // Input area
            VStack(spacing: 12) {
                if let voiceStatus = commandVM.voiceStatusLabel ?? commandVM.statusMessage {
                    HStack(spacing: 8) {
                        Image(systemName: commandVM.isVoiceListening ? "waveform" : "info.circle")
                            .foregroundStyle(commandVM.isVoiceListening ? JarvisColors.accent : .secondary)
                        Text(voiceStatus)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal, 18)
                }
                HStack(spacing: 12) {
                    Button(action: { isInputFocused = false }) {
                        Image(systemName: "plus")
                            .font(.system(size: 14, weight: .medium))
                    }
                    .buttonStyle(.borderless)

                    Button(action: { commandVM.toggleVoiceListening() }) {
                        Image(systemName: commandVM.isVoiceListening ? "mic.fill" : "mic")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(commandVM.isVoiceListening ? JarvisColors.accent : JarvisColors.secondaryLabel)
                    }
                    .buttonStyle(.borderless)
                    .help(commandVM.isVoiceListening ? "Stop listening" : "Start listening")
                    
                    TextField("Message Jarvis...", text: $commandVM.inputText, axis: .vertical)
                        .font(.system(size: 13))
                        .textFieldStyle(.plain)
                        .lineLimit(1...5)
                        .focused($isInputFocused)
                        .onSubmit {
                            sendMessage()
                        }
                    
                    Button(action: toggleSpeechPlayback) {
                        Image(systemName: commandVM.isSpeakingResponse ? "speaker.slash.fill" : "speaker.wave.2.fill")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(JarvisColors.secondaryLabel)
                    }
                    .buttonStyle(.borderless)
                    .disabled(commandVM.latestAssistantMessage?.isEmpty ?? true)
                    .help(commandVM.isSpeakingResponse ? "Stop speaking" : "Speak latest reply")

                    Button(action: sendMessage) {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 14, weight: .semibold))
                            .frame(width: 28, height: 28)
                            .background(
                                Circle()
                                    .fill(commandVM.inputText.isEmpty ? Color.secondary.opacity(0.2) : JarvisColors.accent)
                            )
                            .foregroundStyle(commandVM.inputText.isEmpty ? Color.secondary : Color.white)
                    }
                    .buttonStyle(.plain)
                    .disabled(commandVM.inputText.isEmpty || commandVM.isStreaming)
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
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(Color(nsColor: .controlBackgroundColor))
        }
    }
    
    private func sendMessage() {
        guard !commandVM.inputText.isEmpty else { return }
        commandVM.sendCurrentPrompt()
    }

    private func toggleSpeechPlayback() {
        if commandVM.isSpeakingResponse {
            commandVM.stopSpeaking()
        } else {
            commandVM.speakLatestAssistantMessage()
        }
    }
}

struct TypingIndicator: View {
    @State private var dotCount = 0
    
    var body: some View {
        HStack {
            Spacer(minLength: 60)
            HStack(spacing: 4) {
                ForEach(0..<3) { i in
                    Circle()
                        .fill(Color.secondary)
                        .frame(width: 6, height: 6)
                        .opacity(dotCount == i ? 1.0 : 0.3)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            Spacer(minLength: 60)
        }
        .onAppear {
            Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { _ in
                dotCount = (dotCount + 1) % 3
            }
        }
    }
}

struct MessageBubble: View {
    let message: ChatMessage
    
    var body: some View {
        HStack {
            if message.role == .assistant {
                Spacer(minLength: 60)
            }
            
            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                Text(message.text)
                    .font(.system(size: 13))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(message.role == .user ? JarvisColors.accent.opacity(0.9) : Color(nsColor: .controlBackgroundColor))
                    )
                    .foregroundStyle(message.role == .user ? Color.white : JarvisColors.label)
            }
            
            if message.role == .user {
                Spacer(minLength: 60)
            }
        }
    }
}

struct NotificationsSection: View {
    @EnvironmentObject private var notificationVM: NotificationViewModel
    
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0, pinnedViews: .sectionHeaders) {
                Section {
                    ForEach(notificationVM.notifications) { notification in
                        NotificationListRow(notification: notification)
                        Divider()
                    }
                } header: {
                    HStack {
                        Text("Recent")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                        
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color(nsColor: .windowBackgroundColor))
                }
            }
        }
    }
}

struct NotificationListRow: View {
    let notification: NotificationItem
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: iconForPriority(notification.priority))
                .font(.system(size: 18))
                .foregroundStyle(colorForPriority(notification.priority))
                .frame(width: 32, height: 32)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(notification.title)
                    .font(.system(size: 13, weight: .medium))
                
                Text(notification.body)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            
            Spacer()
            
            Text(notification.date, style: .time)
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }
    
    private func iconForPriority(_ priority: NotificationItem.Priority) -> String {
        switch priority {
        case .urgent: return "exclamationmark.circle.fill"
        case .needsReply: return "bell.badge.fill"
        case .fyi: return "bell.fill"
        case .low: return "bell"
        }
    }
    
    private func colorForPriority(_ priority: NotificationItem.Priority) -> Color {
        switch priority {
        case .urgent: return .red
        case .needsReply: return .orange
        case .fyi: return .blue
        case .low: return .gray
        }
    }
}

struct DocumentsSection: View {
    var body: some View {
        ModernSearchView()
    }
}

struct EmailSection: View {
    @EnvironmentObject private var emailVM: EmailDraftViewModel
    @State private var captureError: String?
    
    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack(spacing: 12) {
                Button(action: { emailVM.captureActiveWindow() }) {
                    Label("Capture Window", systemImage: "macwindow")
                }
                .buttonStyle(JarvisSecondaryButton())
                
                Button(action: captureFullScreen) {
                    Label("Capture Screen", systemImage: "display")
                }
                .buttonStyle(JarvisSecondaryButton())
                
                Spacer()
                
                if emailVM.isCapturing {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .padding(16)
            
            Divider()
            
            // Error message
            if let error = captureError {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(error)
                        .font(.caption)
                    Spacer()
                    Button("Dismiss") {
                        captureError = nil
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.orange.opacity(0.1))
            }
            
            // Content
            ScrollView {
                VStack(spacing: 20) {
                    // OCR Result
                    if !emailVM.extractedText.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Extracted Text")
                                    .font(.system(size: 13, weight: .semibold))
                                
                                Spacer()
                                
                                Button("Copy") {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(emailVM.extractedText, forType: .string)
                                }
                                .buttonStyle(.borderless)
                                .font(.caption)
                            }
                            
                            Text(emailVM.extractedText)
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                .padding(12)
                                .background(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(Color(nsColor: .controlBackgroundColor))
                                )
                        }
                        .padding(.horizontal, 16)
                    }
                    
                    // Draft
                    if !emailVM.draft.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Draft Reply")
                                    .font(.system(size: 13, weight: .semibold))
                                
                                Spacer()
                                
                                Button("Copy") {
                                    emailVM.copyDraft()
                                }
                                .buttonStyle(.borderless)
                                .font(.caption)
                            }
                            
                            Text(emailVM.draft)
                                .font(.system(size: 12))
                                .padding(12)
                                .background(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(Color(nsColor: .controlBackgroundColor))
                                )
                        }
                        .padding(.horizontal, 16)
                    }
                }
                .padding(.vertical, 16)
            }
        }
    }
    
    private func captureFullScreen() {
        emailVM.captureFullScreen()
    }
}

struct SearchSection: View {
    var body: some View {
        ModernSearchView()
    }
}

struct DiagnosticsSection: View {
    @Binding var showPanel: Bool
    @EnvironmentObject private var diagnosticsVM: DiagnosticsViewModel
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Quick stats
                HStack(spacing: 16) {
                    StatCard(title: "Latency", value: String(format: "%.0f ms", diagnosticsVM.latency * 1000), isGood: diagnosticsVM.latency < 1.0)
                    StatCard(title: "Modules", value: "\(diagnosticsVM.moduleHealth.count)", isGood: true)
                    StatCard(title: "Events", value: "\(diagnosticsVM.routingEvents.count)", isGood: true)
                }
                .padding(.horizontal, 16)
                
                // Statuses
                VStack(alignment: .leading, spacing: 12) {
                    Text("System Status")
                        .font(.system(size: 13, weight: .semibold))
                        .padding(.horizontal, 16)
                    
                    if diagnosticsVM.statuses.isEmpty {
                        Text("No status data available")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 16)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(diagnosticsVM.statuses) { status in
                                StatusRow(status: status)
                                if status.id != diagnosticsVM.statuses.last?.id {
                                    Divider()
                                }
                            }
                        }
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color(nsColor: .controlBackgroundColor))
                        )
                        .padding(.horizontal, 16)
                    }
                }
                
                // Module Health
                if !diagnosticsVM.moduleHealth.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Module Health")
                            .font(.system(size: 13, weight: .semibold))
                            .padding(.horizontal, 16)
                        
                        VStack(spacing: 0) {
                            ForEach(diagnosticsVM.moduleHealth) { module in
                                ModuleHealthRow(module: module)
                                if module.id != diagnosticsVM.moduleHealth.last?.id {
                                    Divider()
                                }
                            }
                        }
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color(nsColor: .controlBackgroundColor))
                        )
                        .padding(.horizontal, 16)
                    }
                }
            }
            .padding(.vertical, 16)
        }
        .toolbar {
            ToolbarItem {
                Button(action: { diagnosticsVM.refresh() }) {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
            }
            ToolbarItem {
                Button(action: { showPanel.toggle() }) {
                    Image(systemName: "sidebar.right")
                }
                .buttonStyle(.borderless)
            }
        }
        .onAppear {
            diagnosticsVM.refresh()
        }
    }
}

struct StatCard: View {
    let title: String
    let value: String
    let isGood: Bool
    
    var body: some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            
            Text(value)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(isGood ? Color.primary : Color.red)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }
}

struct StatusRow: View {
    let status: DiagnosticStatus
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: status.isHealthy ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 16))
                .foregroundStyle(status.isHealthy ? .green : .orange)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(status.name)
                    .font(.system(size: 13))
                
                Text(status.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}

struct ModuleHealthRow: View {
    let module: ModuleHealthStatus
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: module.enabled && module.permissionsOK ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 16))
                .foregroundStyle(module.enabled && module.permissionsOK ? .green : .orange)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(module.module)
                    .font(.system(size: 13))
                
                if let lastRun = module.lastRun {
                    Text("Last run: \(lastRun.formatted(date: .omitted, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text(module.enabled ? "Enabled" : "Disabled")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}

struct PrivacySection: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                PrivacyCard(
                    title: "Screen Recording",
                    description: "Jarvis needs screen recording access to capture windows and screens for OCR.",
                    icon: "display",
                    status: "Granted"
                )
                
                PrivacyCard(
                    title: "Accessibility",
                    description: "Required for detecting the active window and global hotkeys.",
                    icon: "accessibility",
                    status: "Granted"
                )
                
                PrivacyCard(
                    title: "Local Processing",
                    description: "All AI processing happens on your device. No data leaves your Mac.",
                    icon: "lock.shield",
                    status: "Enabled"
                )
            }
            .padding(16)
        }
    }
}

struct PrivacyCard: View {
    let title: String
    let description: String
    let icon: String
    let status: String
    
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundStyle(.secondary)
                .frame(width: 40)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                
                Text(description)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            Text(status)
                .font(.caption.weight(.medium))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(Color.green.opacity(0.15))
                )
                .foregroundStyle(.green)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }
}

struct MacrosSection: View {
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Macros")
                    .font(.title3.weight(.semibold))
                
                Spacer()
                
                Button(action: {}) {
                    Image(systemName: "plus")
                    Text("New Macro")
                }
                .buttonStyle(JarvisPrimaryButton())
            }
            .padding(16)
            
            Divider()
            
            List {
                Section("Recent") {
                    MacroRow(name: "Morning Routine", icon: "sunrise", lastRun: "2 hours ago")
                    MacroRow(name: "Email Summary", icon: "envelope", lastRun: "Yesterday")
                }
                
                Section("All Macros") {
                    MacroRow(name: "Screenshot to Notes", icon: "camera", lastRun: "3 days ago")
                    MacroRow(name: "Daily Report", icon: "chart.bar", lastRun: "1 week ago")
                }
            }
            .listStyle(.plain)
        }
    }
}

struct MacroRow: View {
    let name: String
    let icon: String
    let lastRun: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.secondary.opacity(0.1))
                )
            
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.system(size: 13))
                
                Text(lastRun)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            Button(action: {}) {
                Image(systemName: "play.fill")
                    .font(.system(size: 12))
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 4)
    }
}

struct ThinkingSection: View {
    @EnvironmentObject private var commandVM: CommandPaletteViewModel
    @State private var problemStatement: String = ""
    @State private var showThinkingResult: Bool = false
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 8) {
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 32))
                        .foregroundStyle(JarvisColors.accent)
                    
                    Text("Thinking Mode")
                        .font(.title3.weight(.semibold))
                    
                    Text("Break down complex problems step by step")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 20)
                
                // Input
                VStack(alignment: .leading, spacing: 8) {
                    Text("What would you like to think through?")
                        .font(.system(size: 13, weight: .medium))
                    
                    TextEditor(text: $problemStatement)
                        .font(.system(size: 13))
                        .frame(minHeight: 100)
                        .padding(8)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color(nsColor: .controlBackgroundColor))
                        )
                    
                    HStack {
                        Spacer()
                        Button(action: startThinking) {
                            Label("Start Thinking", systemImage: "brain")
                        }
                        .buttonStyle(JarvisPrimaryButton())
                        .disabled(problemStatement.isEmpty || commandVM.isWhyRunning)
                    }
                }
                .padding(.horizontal, 16)
                
                // Results
                if commandVM.isWhyRunning {
                    ProgressView("Analyzing...")
                        .padding()
                } else if !commandVM.whyReport.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Analysis")
                                .font(.system(size: 13, weight: .semibold))
                            Spacer()
                            Button("Copy") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(commandVM.whyReport, forType: .string)
                            }
                            .buttonStyle(.borderless)
                            .font(.caption)
                        }
                        
                        Text(commandVM.whyReport)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .padding(12)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color(nsColor: .controlBackgroundColor))
                            )
                    }
                    .padding(.horizontal, 16)
                }
            }
            .padding(.vertical, 16)
        }
    }
    
    private func startThinking() {
        commandVM.thinkProblemStatement = problemStatement
        // Trigger thinking analysis via the command system
        commandVM.inputText = "/think \(problemStatement)"
        commandVM.sendCurrentPrompt()
    }
}

// MARK: - Inspector

struct DiagnosticsInspector: View {
    @EnvironmentObject private var diagnosticsVM: DiagnosticsViewModel
    
    var body: some View {
        List {
            Section("Performance") {
                HStack {
                    Text("Latency")
                    Spacer()
                    Text(String(format: "%.0f ms", diagnosticsVM.latency * 1000))
                }
            }
            
            Section("Statuses") {
                ForEach(diagnosticsVM.statuses) { status in
                    HStack {
                        Image(systemName: status.isHealthy ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(status.isHealthy ? .green : .orange)
                        Text(status.name)
                        Spacer()
                    }
                }
            }
            
            Section("Modules") {
                ForEach(diagnosticsVM.moduleHealth) { module in
                    HStack {
                        Image(systemName: module.enabled && module.permissionsOK ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(module.enabled && module.permissionsOK ? .green : .orange)
                        Text(module.module)
                        Spacer()
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Diagnostics")
    }
}

// MARK: - Preview

#Preview {
    CommandPaletteView()
        .frame(width: 1000, height: 700)
}
