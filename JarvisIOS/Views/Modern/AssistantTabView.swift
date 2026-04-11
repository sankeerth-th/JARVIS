import SwiftUI
import UIKit

struct AssistantTabView: View {
    @EnvironmentObject private var appModel: JarvisPhoneAppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var composerFocused: Bool
    @State private var isTranscriptPinnedToBottom = true

    private let transcriptBottomAnchor = "assistant.transcript.bottom"
    private let transcriptScrollSpace = "assistant.transcript.scroll"

    var body: some View {
        NavigationStack {
            ZStack {
                JarvisModernBackground()
                    .overlay(AssistantBackdrop(state: appModel.assistantExperienceState))

                VStack(spacing: 10) {
                    assistantHeader
                    messagesPanel
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(.horizontal, 14)
                .padding(.top, 10)
                .padding(.bottom, 4)
            }
            .safeAreaInset(edge: .bottom) {
                assistantBottomDock
                    .padding(.horizontal, 14)
                    .padding(.top, 8)
                    .padding(.bottom, appModel.isAssistantKeyboardActive ? 8 : 6)
            }
            .navigationTitle("JARVIS")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if appModel.shouldShowFocusedBackButton {
                        Button {
                            composerFocused = false
                            appModel.setAssistantKeyboardActive(false)
                            appModel.returnFromFocusedExperience()
                        } label: {
                            Label(appModel.focusedBackButtonTitle, systemImage: "chevron.left")
                        }
                    }
                }
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 2) {
                        Text("Chat")
                            .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        Text(appModel.assistantExperienceState.title)
                            .font(.system(.caption2, design: .rounded, weight: .medium))
                            .foregroundStyle(JarvisModernTheme.textSecondary)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        composerFocused = false
                        appModel.setAssistantKeyboardActive(false)
                        appModel.assistantControlsPresented = true
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .onChange(of: appModel.shouldFocusComposer) { _, shouldFocus in
                if shouldFocus {
                    composerFocused = true
                    appModel.setAssistantKeyboardActive(true)
                    appModel.shouldFocusComposer = false
                } else if !shouldFocus {
                    composerFocused = false
                    appModel.setAssistantKeyboardActive(false)
                }
            }
            .onAppear {
                if appModel.assistantInputMode == .text {
                    composerFocused = true
                    appModel.setAssistantKeyboardActive(true)
                }
            }
            .onChange(of: composerFocused) { _, isFocused in
                appModel.setAssistantKeyboardActive(isFocused)
            }
            .onChange(of: appModel.selectedTab) { _, selectedTab in
                guard selectedTab != .assistant else { return }
                composerFocused = false
                appModel.setAssistantKeyboardActive(false)
            }
            .sheet(isPresented: $appModel.assistantControlsPresented) {
                AssistantControlsSheet()
                    .environmentObject(appModel)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
                    .presentationCornerRadius(24)
            }
            .simultaneousGesture(
                TapGesture().onEnded {
                    guard composerFocused else { return }
                    composerFocused = false
                    appModel.setAssistantKeyboardActive(false)
                }
            )
            .toolbarBackground(.hidden, for: .navigationBar)
            .animation(JarvisModernMotion.stateChange, value: appModel.assistantExperienceState)
            .animation(JarvisModernMotion.contentUpdate, value: appModel.assistantEntryStyle)
        }
    }

    private var assistantHeader: some View {
        VStack(spacing: 8) {
            if appModel.shouldExpandAssistantHero {
                AssistantPresenceSurface(
                    state: appModel.assistantExperienceState,
                    mode: appModel.assistantInputMode,
                    transcript: appModel.assistantLiveTranscript,
                    reduceMotion: reduceMotion
                )
            } else {
                compactStatusBanner
            }

            if appModel.shouldExpandAssistantHero,
               let assistantContinuityLabel = appModel.assistantContinuityLabel {
                continuityBadge(assistantContinuityLabel)
            }

            if appModel.shouldExpandAssistantHero {
                assistantHeroMetaRow
            }
        }
    }

    private var assistantHeroMetaRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                assistantMetaChip(title: modeTitle, icon: modeIcon, tint: JarvisModernTheme.accentSoft)
                assistantMetaChip(title: appModel.assistantTask.displayName, icon: taskIcon, tint: .cyan)
                assistantMetaChip(title: compactStatusTitle, icon: runtimeIcon, tint: runtimeTint)
                if let activeModel = appModel.activeModel?.displayName {
                    assistantMetaChip(title: activeModel, icon: "cpu.fill", tint: JarvisModernTheme.success)
                }
            }
            .padding(.horizontal, 2)
        }
    }

    private func continuityBadge(_ text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "memorychip")
                .font(.caption2.weight(.semibold))
            Text(text)
                .font(.caption2.weight(.semibold))
        }
        .foregroundStyle(JarvisModernTheme.textPrimary)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule(style: .continuous)
                .fill(Color.white.opacity(0.54))
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(JarvisModernTheme.borderStrong, lineWidth: 1)
                )
        )
    }

    private var compactStatusBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: runtimeIcon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(runtimeTint)
                .frame(width: 28, height: 28)
                .background(runtimeTint.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(compactStatusTitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(JarvisModernTheme.textPrimary)
                Text(compactStatusSubtitle)
                    .font(.caption2)
                    .foregroundStyle(JarvisModernTheme.textSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            if let assistantContinuityLabel = appModel.assistantContinuityLabel {
                continuityBadge(assistantContinuityLabel)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(JarvisModernTheme.cardElevated)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(JarvisModernTheme.border, lineWidth: 1)
                )
        )
    }

    private var compactInlineBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: compactStatusIcon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(compactStatusTint)

            VStack(alignment: .leading, spacing: 2) {
                Text(compactStatusTitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(JarvisModernTheme.textPrimary)
                Text(compactStatusSubtitle)
                    .font(.caption2)
                    .foregroundStyle(JarvisModernTheme.textSecondary)
                    .lineLimit(2)
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(JarvisModernTheme.cardElevated)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(JarvisModernTheme.border, lineWidth: 1)
                )
        )
    }

    private var compactStatusTitle: String {
        switch appModel.assistantTask {
        case .knowledgeAnswer:
            return "Knowledge Answer"
        case .quickCapture:
            return "Quick Capture"
        case .reply:
            return "Draft Reply"
        case .summarize:
            return "Summarize"
        default:
            return appModel.assistantExperienceState.title
        }
    }

    private var compactStatusSubtitle: String {
        switch appModel.assistantSurfaceState {
        case .idle:
            return "Ready for your next message."
        case .typing:
            return "Type naturally. Jarvis will keep the conversation in view."
        case .responding:
            return appModel.statusText
        case .reviewing:
            return "Latest reply is ready with follow-up actions."
        case .error:
            return appModel.statusText
        }
    }

    private var compactStatusIcon: String {
        switch appModel.assistantSurfaceState {
        case .idle:
            return "sparkles"
        case .typing:
            return "keyboard"
        case .responding:
            return "waveform.path"
        case .reviewing:
            return "checkmark.circle"
        case .error:
            return "exclamationmark.triangle.fill"
        }
    }

    private var compactStatusTint: Color {
        switch appModel.assistantSurfaceState {
        case .idle:
            return .cyan
        case .typing:
            return .blue
        case .responding:
            return .indigo
        case .reviewing:
            return .green
        case .error:
            return .orange
        }
    }

    private func assistantMetaChip(title: String, icon: String, tint: Color) -> some View {
        Label(title, systemImage: icon)
            .font(.caption.weight(.semibold))
            .foregroundStyle(JarvisModernTheme.textPrimary)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                Capsule(style: .continuous)
                    .fill(tint.opacity(0.12))
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(tint.opacity(0.32), lineWidth: 1)
                    )
            )
    }

    private var assistantBottomDock: some View {
        VStack(spacing: 8) {
            composerPanel
        }
    }

    private var voiceTranscriptPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Voice session", systemImage: "waveform")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(JarvisModernTheme.textSecondary)
                Spacer()
                Text(voiceStateLabel)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(JarvisModernTheme.textPrimary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(JarvisModernTheme.panelGlass, in: Capsule())
                Button(listeningActive ? "Stop" : "Listen") {
                    if listeningActive {
                        appModel.stopVoicePreview(commit: false)
                    } else {
                        appModel.startVoicePreview()
                    }
                }
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background((listeningActive ? Color.orange : Color.cyan).opacity(0.16), in: Capsule())
            }
            AssistantVoiceMeter(
                state: appModel.assistantExperienceState,
                speechState: appModel.speechState
            )
            TextField("Transcript appears here (voice pipeline can feed this directly)", text: $appModel.assistantLiveTranscript, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(2...4)
                .padding(10)
                .background(JarvisModernTheme.panelGlass, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(JarvisModernTheme.borderStrong, lineWidth: 1)
                )

            if !appModel.speechPermissions.isGranted {
                Text("Microphone + Speech access is required for voice mode.")
                    .font(.caption2)
                    .foregroundStyle(.orange.opacity(0.95))
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(JarvisModernTheme.cardSecondary)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(JarvisModernTheme.borderStrong, lineWidth: 1)
                )
        )
    }

    private var transcriptScrollSignature: String {
        let messages = appModel.conversation.messages
        guard let last = messages.last else {
            return "empty-\(appModel.isSending)-\(appModel.assistantExperienceState.title)-\(appModel.streamingRevision)"
        }
        return "\(messages.count)-\(last.id.uuidString)-\(last.text.count)-\(last.isStreaming)-\(appModel.isSending)-\(appModel.streamingRevision)"
    }

    private func scrollTranscriptToBottom(_ proxy: ScrollViewProxy, animated: Bool) {
        let action = {
            proxy.scrollTo(transcriptBottomAnchor, anchor: .bottom)
        }
        if animated {
            withAnimation(.easeOut(duration: 0.18), action)
        } else {
            action()
        }
    }

    private var shouldShowEntryContext: Bool {
        guard appModel.selectedTab == .assistant else { return false }
        return appModel.assistantEntryStyle != .standard
    }

    private var entryContextBadge: some View {
        HStack(spacing: 8) {
            Image(systemName: entryIcon)
                .font(.caption.weight(.semibold))
            VStack(alignment: .leading, spacing: 2) {
                Text(entryTitle)
                    .font(.caption.weight(.semibold))
                Text(entrySubtitle)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.76))
            }
            Spacer()
        }
        .foregroundStyle(.white.opacity(0.92))
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.white.opacity(0.16), lineWidth: 1)
                )
        )
    }

    private var entryTitle: String {
        switch appModel.assistantEntryStyle {
        case .standard:
            return "Assistant"
        case .assistant:
            return "Assistant Entry"
        case .chat:
            return "Chat"
        case .quickAsk:
            return "Quick Ask"
        case .quickCapture:
            return "Quick Capture"
        case .draftReply:
            return "Draft Reply"
        case .summarize:
            return "Summarize"
        case .continueConversation:
            return "Continue Session"
        case .voiceFirst:
            return "Voice Entry"
        case .visualPreview:
            return "Visual Preview"
        case .systemAssistant:
            return "System Assistant"
        }
    }

    private var entrySubtitle: String {
        switch appModel.assistantEntryStyle {
        case .standard:
            return "Ready for input."
        case .assistant:
            return "Unified assistant entry surface."
        case .chat:
            return "Direct chat route."
        case .quickAsk:
            return "Focused one-shot assistant invocation."
        case .quickCapture:
            return "Capture context now, refine next."
        case .draftReply:
            return "Reply-focused drafting mode."
        case .summarize:
            return "Draft prepared for concise output."
        case .continueConversation:
            return "Resuming recent assistant context."
        case .voiceFirst:
            return "Hands-free listening mode."
        case .visualPreview:
            return "Honest preview while vision runtime is staged."
        case .systemAssistant:
            return "System-triggered assistant entry."
        }
    }

    private var entryIcon: String {
        switch appModel.assistantEntryStyle {
        case .standard:
            return "sparkles"
        case .assistant:
            return "bolt.badge.sparkles"
        case .chat:
            return "bubble.left.and.text.bubble.right.fill"
        case .quickAsk:
            return "bolt.fill"
        case .quickCapture:
            return "square.and.pencil"
        case .draftReply:
            return "arrowshape.turn.up.left.fill"
        case .summarize:
            return "text.quote"
        case .continueConversation:
            return "arrow.uturn.forward.circle"
        case .voiceFirst:
            return "waveform"
        case .visualPreview:
            return "viewfinder"
        case .systemAssistant:
            return "sparkles.tv"
        }
    }

    private var taskIcon: String {
        switch appModel.assistantTask {
        case .chat:
            return "bubble.left.and.text.bubble.right"
        case .summarize:
            return "text.quote"
        case .reply:
            return "arrowshape.turn.up.left"
        case .draftEmail:
            return "envelope"
        case .analyzeText:
            return "doc.text.magnifyingglass"
        case .visualDescribe:
            return "viewfinder"
        case .prioritizeNotifications:
            return "bell.badge"
        case .quickCapture:
            return "square.and.pencil"
        case .knowledgeAnswer:
            return "books.vertical"
        }
    }

    private var modeTitle: String {
        switch appModel.assistantInputMode {
        case .text:
            return "Text"
        case .voice:
            return "Voice"
        case .visual:
            return "Visual"
        }
    }

    private var modeIcon: String {
        switch appModel.assistantInputMode {
        case .text:
            return "text.bubble"
        case .voice:
            return "waveform"
        case .visual:
            return "viewfinder"
        }
    }

    private var runtimeIcon: String {
        switch appModel.runtimeState {
        case .noModel:
            return "exclamationmark.circle"
        case .runtimeUnavailable:
            return "xmark.octagon"
        case .cold:
            return "snowflake"
        case .warming:
            return "hourglass"
        case .ready:
            return "checkmark.circle"
        case .busy:
            return "waveform.path"
        case .paused:
            return "pause.circle"
        case .failed:
            return "exclamationmark.triangle"
        }
    }

    private var runtimeTint: Color {
        switch appModel.runtimeState {
        case .ready:
            return .green
        case .warming, .busy:
            return .indigo
        case .failed:
            return .red
        case .runtimeUnavailable, .noModel:
            return .orange
        case .cold:
            return .blue
        case .paused:
            return .yellow
        }
    }

    private var assistantStateTimeline: some View {
        HStack(spacing: 8) {
            timelineChip("Listen", icon: "waveform", active: timelinePhase >= 1)
            timelineConnector(active: timelinePhase >= 2)
            timelineChip("Think", icon: "brain.head.profile", active: timelinePhase >= 2)
            timelineConnector(active: timelinePhase >= 3)
            timelineChip("Answer", icon: "sparkles.rectangle.stack", active: timelinePhase >= 3)
        }
    }

    private func timelineChip(_ title: String, icon: String, active: Bool) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.caption2.weight(.semibold))
            Text(title)
                .font(.caption2.weight(.semibold))
        }
        .foregroundStyle(active ? .white.opacity(0.92) : .white.opacity(0.58))
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(active ? Color.white.opacity(0.14) : Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(active ? Color.white.opacity(0.24) : Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }

    private func timelineConnector(active: Bool) -> some View {
        Capsule(style: .continuous)
            .fill(active ? Color.white.opacity(0.44) : Color.white.opacity(0.16))
            .frame(width: 18, height: 2)
    }

    private var timelinePhase: Int {
        switch appModel.assistantExperienceState {
        case .idle, .armed, .unavailable:
            return 0
        case .listening, .transcribing:
            return 1
        case .thinking, .processing, .grounding:
            return 2
        case .responding, .answerReady, .error:
            return 3
        }
    }

    private var listeningActive: Bool {
        switch appModel.assistantExperienceState {
        case .listening, .transcribing:
            return true
        default:
            return false
        }
    }

    private var voiceStateLabel: String {
        switch appModel.speechState {
        case .idle:
            return "Idle"
        case .requestingPermission:
            return "Perms"
        case .ready:
            return "Ready"
        case .listening:
            return "Listening"
        case .transcribing:
            return "Transcribing"
        case .stopping:
            return "Stopping"
        case .failed:
            return "Blocked"
        }
    }

    private var messagesPanel: some View {
        let messages = appModel.conversation.messages
        return GeometryReader { scrollBounds in
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 10) {
                        if !appModel.shouldExpandAssistantHero {
                            compactInlineBanner
                        }

                        if shouldShowExecutionSnapshot {
                            executionSnapshotPanel
                        }

                        if shouldShowVoiceSupportPanel {
                            voiceTranscriptPanel
                        }

                        if showGroundingContext {
                            groundingContextPanel
                        }

                        if appModel.settings.showRuntimeDiagnostics && shouldShowDiagnosticsPanel {
                            diagnosticsPanel
                        }

                        messageList(messages: messages)

                        GeometryReader { geometry in
                            Color.clear
                                .preference(
                                    key: AssistantTranscriptBottomOffsetPreferenceKey.self,
                                    value: geometry.frame(in: .named(transcriptScrollSpace)).maxY - scrollBounds.size.height
                                )
                        }
                        .frame(height: 1)
                        .id(transcriptBottomAnchor)
                    }
                    .padding(10)
                }
                .coordinateSpace(name: transcriptScrollSpace)
                .scrollDismissesKeyboard(.interactively)
                .background(
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .fill(JarvisModernTheme.cardElevated.opacity(0.84))
                        .overlay(
                            RoundedRectangle(cornerRadius: 26, style: .continuous)
                                .stroke(JarvisModernTheme.border, lineWidth: 1)
                        )
                )
                .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                .onAppear {
                    guard appModel.settings.autoScrollConversation else { return }
                    scrollTranscriptToBottom(proxy, animated: false)
                }
                .onChange(of: transcriptScrollSignature) { _, _ in
                    guard appModel.settings.autoScrollConversation,
                          isTranscriptPinnedToBottom || appModel.isSending || composerFocused else { return }
                    scrollTranscriptToBottom(proxy, animated: !reduceMotion)
                }
                .onPreferenceChange(AssistantTranscriptBottomOffsetPreferenceKey.self) { offset in
                    isTranscriptPinnedToBottom = offset < 96
                }
                .onTapGesture {
                    guard composerFocused else { return }
                    composerFocused = false
                    appModel.setAssistantKeyboardActive(false)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func messageList(messages: [JarvisChatMessage]) -> some View {
        LazyVStack(spacing: 10) {
            if messages.isEmpty {
                AssistantEmptyState()
            }

            ForEach(messages) { message in
                VStack(alignment: .leading, spacing: 8) {
                    AssistantMessageRow(message: message)
                    if shouldAttachFollowUpChips(to: message) {
                        contextualFollowUpChips
                            .padding(.leading, 8)
                    }
                }
                    .id(message.id)
            }
        }
    }

    private var showGroundingContext: Bool {
        switch appModel.assistantExperienceState {
        case .grounding, .responding, .answerReady:
            return !contextPreviewResults.isEmpty
        default:
            return false
        }
    }

    private var contextPreviewResults: [JarvisKnowledgeResult] {
        if !appModel.knowledgeResults.isEmpty {
            return Array(appModel.knowledgeResults.prefix(3))
        }
        return Array(appModel.knowledgeItems.prefix(3)).map {
            JarvisKnowledgeResult(item: $0, score: 0.5, snippet: String($0.text.prefix(140)))
        }
    }

    private var groundingContextPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Local context", systemImage: "books.vertical")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.85))
                Spacer()
                Button("Open Knowledge") {
                    appModel.apply(route: JarvisLaunchRoute.assistant(.knowledge, source: .inApp))
                }
                .font(.caption2.weight(.semibold))
                .buttonStyle(.plain)
                .foregroundStyle(.cyan)
            }

            ForEach(contextPreviewResults, id: \.item.id) { result in
                VStack(alignment: .leading, spacing: 3) {
                    Text(result.item.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.92))
                        .lineLimit(1)
                    Text(result.snippet)
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.72))
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 5)
                .padding(.horizontal, 8)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.white.opacity(0.14), lineWidth: 1)
                )
        )
    }

    private var latestAssistantText: String? {
        let latestAssistant = appModel.conversation.messages.last { message in
            message.role == JarvisChatRole.assistant
        }
        let trimmed = (latestAssistant?.text ?? "").trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private var latestAssistantMessageID: UUID? {
        appModel.conversation.messages.last(where: { $0.role == .assistant })?.id
    }

    private func shouldAttachFollowUpChips(to message: JarvisChatMessage) -> Bool {
        guard appModel.shouldShowAssistantFollowUpChips,
              message.role == .assistant,
              message.id == latestAssistantMessageID else {
            return false
        }
        return latestAssistantText != nil
    }

    private var contextualFollowUpChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                if !appModel.assistantSuggestions.isEmpty {
                    ForEach(Array(appModel.assistantSuggestions.prefix(3))) { suggestion in
                        actionButton(suggestion.title, icon: suggestion.icon) {
                            appModel.performAssistantSuggestion(suggestion)
                        }
                    }
                } else {
                    actionButton("Follow-up", icon: "arrow.turn.down.right") {
                        appModel.setAssistantInputMode(.text)
                        appModel.draft = "Can you expand your last answer with one practical next step?"
                        appModel.shouldFocusComposer = true
                    }
                    actionButton("Rephrase", icon: "textformat.alt") {
                        appModel.setAssistantInputMode(.text)
                        appModel.draft = "Rephrase your last answer in simpler language."
                        appModel.shouldFocusComposer = true
                    }
                    actionButton("Search More", icon: "magnifyingglass") {
                        let payload = latestAssistantText.map { String($0.prefix(120)) }
                        appModel.apply(route: JarvisLaunchRoute(action: .knowledge, query: payload, source: JarvisAssistantEntrySource.inApp.rawValue, assistantTask: .knowledgeAnswer))
                    }
                }
            }
            .padding(.horizontal, 2)
        }
    }

    private var shouldShowExecutionSnapshot: Bool {
        switch appModel.assistantExperienceState {
        case .thinking, .processing, .grounding, .responding, .answerReady, .error:
            return true
        default:
            return false
        }
    }

    private var shouldShowVoiceSupportPanel: Bool {
        appModel.assistantInputMode == .voice || listeningActive
    }

    private var shouldShowDiagnosticsPanel: Bool {
        appModel.assistantExperienceState != .idle || appModel.runtimeFailure != nil
    }

    private var executionSnapshotPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                JarvisModernIconBadge(systemName: executionSnapshotIcon, tint: executionSnapshotTint)

                VStack(alignment: .leading, spacing: 4) {
                    Text(executionSnapshotTitle)
                        .font(.system(.subheadline, design: .rounded, weight: .bold))
                        .foregroundStyle(JarvisModernTheme.textPrimary)
                    Text(executionSnapshotSubtitle)
                        .font(.system(.caption, design: .rounded, weight: .medium))
                        .foregroundStyle(JarvisModernTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }

            assistantStateTimeline

            if let plan = appModel.lastExecutionPlan {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        executionTag(title: plan.mode.rawValue.replacingOccurrences(of: "_", with: " ").capitalized, icon: "point.topleft.down.curvedto.point.bottomright.up")
                        if let lane = plan.selectedModelLane?.rawValue {
                            executionTag(title: lane.replacingOccurrences(of: "_", with: " ").capitalized, icon: "cpu")
                        }
                        executionTag(title: "\(plan.steps.count) step\(plan.steps.count == 1 ? "" : "s")", icon: "list.number")
                    }
                    .padding(.horizontal, 2)
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(JarvisModernTheme.cardPrimary.opacity(0.96))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(JarvisModernTheme.borderStrong, lineWidth: 1)
                )
        )
    }

    private func executionTag(title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.system(.caption2, design: .rounded, weight: .semibold))
            .foregroundStyle(JarvisModernTheme.textPrimary)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                Capsule(style: .continuous)
                    .fill(JarvisModernTheme.panelGlass)
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(JarvisModernTheme.border, lineWidth: 1)
                    )
            )
    }

    private var executionSnapshotTitle: String {
        switch appModel.assistantExperienceState {
        case .thinking:
            return "Planning the response"
        case .processing:
            return "Preparing the turn"
        case .grounding:
            return "Gathering local context"
        case .responding:
            return "Streaming the answer"
        case .answerReady:
            return "Turn completed"
        case .error:
            return "Turn needs attention"
        default:
            return "Assistant status"
        }
    }

    private var executionSnapshotSubtitle: String {
        if !appModel.statusText.isEmpty {
            return appModel.statusText
        }
        return "The assistant is coordinating response, context, and output."
    }

    private var executionSnapshotIcon: String {
        switch appModel.assistantExperienceState {
        case .thinking, .processing:
            return "brain.head.profile"
        case .grounding:
            return "books.vertical.fill"
        case .responding:
            return "sparkles.rectangle.stack.fill"
        case .answerReady:
            return "checkmark.circle.fill"
        case .error:
            return "exclamationmark.triangle.fill"
        default:
            return "sparkles"
        }
    }

    private var executionSnapshotTint: Color {
        switch appModel.assistantExperienceState {
        case .thinking, .processing, .grounding, .responding:
            return JarvisModernTheme.accent
        case .answerReady:
            return JarvisModernTheme.success
        case .error:
            return JarvisModernTheme.warning
        default:
            return JarvisModernTheme.accentSoft
        }
    }

    private func actionButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.system(.caption, design: .rounded, weight: .semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.08), in: Capsule())
                .overlay(
                    Capsule()
                        .stroke(JarvisModernTheme.border, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var composerField: some View {
        switch appModel.assistantInputMode {
        case .text:
            TextField(composerPlaceholder, text: $appModel.draft, axis: .vertical)
                .focused($composerFocused)
                .lineLimit(1...4)
                .textFieldStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        case .voice:
            TextField("Speak, then review the transcript here", text: $appModel.assistantLiveTranscript, axis: .vertical)
                .lineLimit(1...4)
                .textFieldStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        case .visual:
            Button {
                appModel.apply(
                    route: JarvisLaunchRoute.assistant(
                        .visual,
                        task: .visualDescribe,
                        source: .inApp
                    )
                )
            } label: {
                HStack {
                    Label("Open visual workspace", systemImage: "viewfinder")
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.white.opacity(0.9))
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
                .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    private var composerActionButton: some View {
        Button {
            if appModel.assistantInputMode == .voice {
                if listeningActive {
                    appModel.stopVoicePreview(commit: true)
                } else {
                    appModel.startVoicePreview()
                }
            } else if appModel.assistantInputMode == .visual {
                appModel.apply(
                    route: JarvisLaunchRoute.assistant(
                        .visual,
                        task: .visualDescribe,
                        source: .inApp
                    )
                )
            } else {
                appModel.sendCurrentDraft()
            }
        } label: {
            Image(systemName: sendIcon)
                .font(.system(size: 21, weight: .bold))
                .symbolRenderingMode(.hierarchical)
                .frame(width: 44, height: 44)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(canSend ? JarvisModernTheme.accent.opacity(0.22) : Color.white.opacity(0.06))
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(canSend ? JarvisModernTheme.accent.opacity(0.42) : JarvisModernTheme.border, lineWidth: 1)
                        )
                )
        }
        .disabled(!canSend)
        .tint(canSend ? JarvisModernTheme.accent : JarvisModernTheme.textSecondary)
        .opacity(1)
    }

    private var composerPanel: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                modeButton(title: "Text", icon: "text.bubble", mode: .text)
                modeButton(title: "Voice", icon: "waveform", mode: .voice)
                modeButton(title: "Visual", icon: "viewfinder", mode: .visual)
            }

            if !appModel.shouldShowAssistantFollowUpChips {
                quickCommandRail
            }

            HStack(spacing: 10) {
                voiceShortcutButton
                composerField
                composerActionButton
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(JarvisModernTheme.cardPrimary.opacity(0.98))
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(JarvisModernTheme.borderStrong, lineWidth: 1)
                )
                .shadow(color: JarvisModernTheme.shadow, radius: 22, x: 0, y: 16)
        )
    }

    private var voiceShortcutButton: some View {
        Button {
            if appModel.assistantInputMode == .voice {
                if listeningActive {
                    appModel.stopVoicePreview(commit: false)
                } else {
                    appModel.startVoicePreview()
                }
            } else {
                composerFocused = false
                appModel.setAssistantKeyboardActive(false)
                appModel.setAssistantInputMode(.voice)
                appModel.startVoicePreview()
            }
        } label: {
            ZStack {
                Circle()
                    .fill((listeningActive ? Color.cyan : JarvisModernTheme.accentSoft).opacity(0.20))
                    .frame(width: 50, height: 50)
                Circle()
                    .stroke((listeningActive ? Color.cyan : JarvisModernTheme.accentSoft).opacity(0.48), lineWidth: 1)
                    .frame(width: 44, height: 44)
                Image(systemName: listeningActive ? "waveform.circle.fill" : "mic.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(JarvisModernTheme.textPrimary)
            }
        }
        .buttonStyle(.plain)
    }

    private var quickCommandRail: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                actionButton("Talk to Jarvis", icon: "waveform") {
                    composerFocused = false
                    appModel.setAssistantKeyboardActive(false)
                    appModel.setAssistantInputMode(.voice)
                    appModel.startVoicePreview()
                }
                actionButton("Summarize", icon: "text.quote") {
                    appModel.apply(route: JarvisLaunchRoute(action: .summarize, source: "assistant.composer", assistantTask: .summarize, shouldFocusComposer: true))
                }
                actionButton("Capture", icon: "square.and.pencil") {
                    appModel.apply(route: JarvisLaunchRoute(action: .quickCapture, source: "assistant.composer", assistantTask: .quickCapture, shouldFocusComposer: true))
                }
                actionButton("Knowledge", icon: "books.vertical") {
                    appModel.apply(route: JarvisLaunchRoute.assistant(.knowledge, source: .inApp))
                }
            }
            .padding(.horizontal, 2)
        }
    }

    private var diagnosticsPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Runtime diagnostics")
                .font(.system(.caption, design: .rounded, weight: .bold))
                .foregroundStyle(JarvisModernTheme.textPrimary)
            diagnosticsRow
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(JarvisModernTheme.cardSecondary)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(JarvisModernTheme.border, lineWidth: 1)
                )
        )
    }

    private var diagnosticsRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: "waveform.path.ecg")
                    .foregroundStyle(.cyan)
                Text(appModel.runtimeState.title)
                    .font(.caption.weight(.semibold))
                Spacer()
                Text(appModel.lastTaskClassification.category.displayName)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.78))
                Text(appModel.lastGenerationPreset.rawValue.capitalized)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.cyan.opacity(0.85))
                Text(appModel.runtimeEngineName)
                    .font(.caption2)
                    .foregroundStyle(JarvisModernTheme.textSecondary)
            }

            Text("\(appModel.modelFileAccessState.title): \(appModel.modelFileAccessDetail)")
                .font(.caption2)
                .foregroundStyle(JarvisModernTheme.textSecondary)

            Text("Assistant gate: \(appModel.assistantRuntimeGateStatus.detail)")
                .font(.caption2)
                .foregroundStyle(JarvisModernTheme.textSecondary)

            if !appModel.lastPromptDebugSummary.isEmpty {
                Text("Prompt pipeline: \(appModel.lastPromptDebugSummary)")
                    .font(.caption2)
                    .foregroundStyle(JarvisModernTheme.textSecondary)
            }

            if let failure = appModel.runtimeFailure {
                Text("Failure: \(failure.kind.rawValue) - \(failure.message)")
                    .font(.caption2)
                .foregroundStyle(.orange.opacity(0.9))
            }
        }
        .foregroundStyle(JarvisModernTheme.textPrimary)
        .padding(.horizontal, 10)
    }

    private var canSend: Bool {
        if appModel.assistantInputMode == .voice {
            return listeningActive || !appModel.assistantLiveTranscript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        if appModel.assistantInputMode == .visual {
            return true
        }
        return !appModel.needsModelSetup &&
        appModel.canRunInference &&
        !appModel.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !appModel.isSending
    }

    private var composerPlaceholder: String {
        switch appModel.assistantTask {
        case .chat:
            return appModel.assistantEntryStyle == .quickAsk ? "Ask directly" : "Ask anything"
        case .summarize:
            return "Paste text to summarize"
        case .reply:
            return "What should the reply say?"
        case .draftEmail:
            return "Draft the email"
        case .analyzeText:
            return "Paste the text to analyze"
        case .visualDescribe:
            return "Ask about what you captured"
        case .prioritizeNotifications:
            return "Paste the updates to rank"
        case .quickCapture:
            return "Capture the thought before you lose it"
        case .knowledgeAnswer:
            return "Ask using your saved knowledge"
        }
    }

    private var sendIcon: String {
        switch appModel.assistantInputMode {
        case .text:
            return "arrow.up.circle.fill"
        case .voice:
            return listeningActive ? "stop.circle.fill" : "waveform.circle.fill"
        case .visual:
            return "arrow.up.right.circle.fill"
        }
    }

    private func modeButton(title: String, icon: String, mode: JarvisPhoneAppModel.AssistantInputMode) -> some View {
        let isActive = appModel.assistantInputMode == mode
        return Button {
            appModel.setAssistantInputMode(mode)
            if mode == .text {
                composerFocused = true
                appModel.setAssistantKeyboardActive(true)
            }
        } label: {
            Label(title, systemImage: icon)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
                .background(isActive ? JarvisModernTheme.accent.opacity(0.20) : JarvisModernTheme.panelMuted, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .stroke(isActive ? JarvisModernTheme.accent.opacity(0.56) : JarvisModernTheme.border, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    private func stateInfoRow(icon: String, text: String, tint: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(tint)
            Text(text)
                .font(.caption)
                .lineLimit(2)
                .foregroundStyle(.white.opacity(0.86))
            Spacer()
        }
        .padding(.horizontal, 10)
    }
}

private struct AssistantBackdrop: View {
    let state: JarvisPhoneAppModel.AssistantExperienceState

    var body: some View {
        RadialGradient(
            colors: [topColor, .clear],
            center: .top,
            startRadius: 16,
            endRadius: 380
        )
        .ignoresSafeArea()
    }

    private var topColor: Color {
        switch state {
        case .listening, .transcribing:
            return Color.cyan.opacity(0.18)
        case .thinking, .processing, .grounding, .responding:
            return JarvisModernTheme.accent.opacity(0.18)
        case .error:
            return JarvisModernTheme.danger.opacity(0.16)
        default:
            return JarvisModernTheme.accentSoft.opacity(0.15)
        }
    }
}

private struct AssistantPresenceSurface: View {
    let state: JarvisPhoneAppModel.AssistantExperienceState
    let mode: JarvisPhoneAppModel.AssistantInputMode
    let transcript: String
    let reduceMotion: Bool
    @State private var pulse = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(orbTint.opacity(0.12))
                        .frame(width: pulse ? 116 : 98, height: pulse ? 116 : 98)
                        .blur(radius: 14)
                    Circle()
                        .stroke(orbTint.opacity(0.30), lineWidth: 1.2)
                        .frame(width: pulse ? 96 : 84, height: pulse ? 96 : 84)
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [orbTint.opacity(0.96), orbTint.opacity(0.58)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 60, height: 60)
                        .overlay(
                            Image(systemName: icon)
                                .font(.system(size: 22, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.95))
                        )
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(headline)
                        .font(.system(.title3, design: .rounded, weight: .bold))
                        .foregroundStyle(JarvisModernTheme.textPrimary)
                    Text(subline)
                        .font(.system(.footnote, design: .rounded, weight: .medium))
                        .foregroundStyle(JarvisModernTheme.textSecondary)
                        .lineLimit(3)
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 8) {
                presenceChip(title: modeTitle, icon: icon, tint: orbTint)
                presenceChip(title: stateTag, icon: stateIcon, tint: orbTint.opacity(0.9))
                if !transcriptPreview.isEmpty {
                    presenceChip(title: transcriptPreview, icon: "quote.opening", tint: .cyan)
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(JarvisModernTheme.cardPrimary.opacity(0.96))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(JarvisModernTheme.borderStrong, lineWidth: 1)
                )
        )
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(JarvisModernMotion.idle) {
                pulse = true
            }
        }
    }

    private func presenceChip(title: String, icon: String, tint: Color) -> some View {
        Label(title, systemImage: icon)
            .lineLimit(1)
            .font(.system(.caption2, design: .rounded, weight: .semibold))
            .foregroundStyle(JarvisModernTheme.textPrimary)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                Capsule(style: .continuous)
                    .fill(tint.opacity(0.12))
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(tint.opacity(0.26), lineWidth: 1)
                    )
            )
    }

    private var headline: String {
        state.title
    }

    private var subline: String {
        switch state {
        case .idle:
            return "Assistant standing by."
        case .armed:
            return "Choose text, voice, or visual entry."
        case .listening:
            return "Capturing voice input."
        case .transcribing:
            return transcript.isEmpty ? "Converting speech into text…" : transcript
        case .thinking:
            return "Reasoning on-device."
        case .processing:
            return "Preparing your request."
        case .grounding:
            return "Retrieving local context."
        case .responding:
            return "Streaming answer."
        case .answerReady:
            return "Answer ready with follow-up actions."
        case .error(let message):
            return message
        case .unavailable(let reason):
            return reason
        }
    }

    private var icon: String {
        switch mode {
        case .text:
            return "bubble.left.and.text.bubble.right.fill"
        case .voice:
            return "waveform"
        case .visual:
            return "viewfinder"
        }
    }

    private var orbTint: Color {
        switch state {
        case .listening, .transcribing:
            return .cyan
        case .thinking, .processing, .grounding, .responding:
            return JarvisModernTheme.accent
        case .answerReady:
            return JarvisModernTheme.success
        case .error:
            return JarvisModernTheme.danger
        case .unavailable:
            return JarvisModernTheme.warning
        default:
            return JarvisModernTheme.accentSoft
        }
    }

    private var modeTitle: String {
        switch mode {
        case .text:
            return "Text"
        case .voice:
            return "Voice"
        case .visual:
            return "Visual"
        }
    }

    private var stateTag: String {
        switch state {
        case .idle, .armed:
            return "Standing by"
        case .listening:
            return "Listening live"
        case .transcribing:
            return "Speech to text"
        case .thinking, .processing:
            return "Planning"
        case .grounding:
            return "Grounding"
        case .responding:
            return "Streaming"
        case .answerReady:
            return "Ready"
        case .error:
            return "Needs review"
        case .unavailable:
            return "Unavailable"
        }
    }

    private var stateIcon: String {
        switch state {
        case .idle, .armed:
            return "sparkles"
        case .listening:
            return "waveform"
        case .transcribing:
            return "text.bubble"
        case .thinking, .processing:
            return "brain.head.profile"
        case .grounding:
            return "books.vertical"
        case .responding:
            return "sparkles.rectangle.stack"
        case .answerReady:
            return "checkmark.circle"
        case .error:
            return "exclamationmark.triangle"
        case .unavailable:
            return "xmark.octagon"
        }
    }

    private var transcriptPreview: String {
        String(transcript.trimmingCharacters(in: .whitespacesAndNewlines).prefix(28))
    }
}

private struct AssistantMessageRow: View {
    let message: JarvisChatMessage

    var body: some View {
        let isUser = message.role == .user
        HStack {
            if isUser { Spacer(minLength: 42) }
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(isUser ? "You" : "Jarvis")
                    .font(.system(.caption2, design: .rounded, weight: .semibold))
                    .foregroundStyle(JarvisModernTheme.textTertiary)
                    if !isUser && message.isStreaming {
                        Label("Live", systemImage: "waveform")
                            .font(.system(.caption2, design: .rounded, weight: .semibold))
                            .foregroundStyle(.cyan)
                    }
                }
                if message.isStreaming && message.text.isEmpty {
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.small)
                        Text("JARVIS is composing…")
                            .font(.caption)
                            .foregroundStyle(JarvisModernTheme.textSecondary)
                    }
                } else {
                    Text(message.text)
                        .font(.system(.body, design: .rounded, weight: .medium))
                        .foregroundStyle(JarvisModernTheme.textPrimary)
                        .textSelection(.enabled)
                    if let displayText = message.memoryAttribution?.displayText, !displayText.isEmpty {
                        Label(displayText, systemImage: "memorychip")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(JarvisModernTheme.textSecondary)
                            .padding(.top, 2)
                    }
                    if let structuredOutput = message.structuredOutput, !structuredOutput.isEmpty {
                        AssistantStructuredOutputView(output: structuredOutput)
                    }
                }
            }
            .frame(maxWidth: 296, alignment: .leading)
            .padding(15)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(isUser ? JarvisModernTheme.accent.opacity(0.18) : JarvisModernTheme.cardPrimary)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(isUser ? JarvisModernTheme.accent.opacity(0.54) : JarvisModernTheme.borderStrong, lineWidth: 1)
            )
            if !isUser { Spacer(minLength: 42) }
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

private struct AssistantStructuredOutputView: View {
    let output: JarvisAssistantStructuredOutput

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(output.capabilitySurfaces) { surface in
                AssistantCapabilitySurfaceCard(surface: surface)
            }

            ForEach(output.cards) { card in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: icon(for: card.kind))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(JarvisModernTheme.accent)
                        Text(card.title)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(JarvisModernTheme.textPrimary)
                    }

                    if !card.body.isEmpty {
                        Text(card.body)
                            .font(.caption)
                            .foregroundStyle(JarvisModernTheme.textSecondary)
                            .textSelection(.enabled)
                    }

                    if !card.items.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(Array(card.items.enumerated()), id: \.offset) { index, item in
                                HStack(alignment: .top, spacing: 6) {
                                    Text("\(index + 1).")
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(JarvisModernTheme.accent)
                                    Text(item)
                                        .font(.caption)
                                        .foregroundStyle(JarvisModernTheme.textSecondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }

                    if let callout = card.callout, !callout.isEmpty {
                        Text(callout)
                            .font(.caption2)
                            .foregroundStyle(JarvisModernTheme.textTertiary)
                    }
                }
                .padding(10)
                .background(Color.white.opacity(0.52), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(JarvisModernTheme.borderStrong, lineWidth: 1)
                )
            }
        }
        .padding(.top, 4)
    }

    private func icon(for kind: JarvisAssistantCardKind) -> String {
        switch kind {
        case .draft:
            return "square.and.pencil"
        case .action:
            return "bolt.fill"
        case .checklist:
            return "checklist"
        case .clarification:
            return "questionmark.bubble"
        case .summary:
            return "text.quote"
        case .codeAnswer:
            return "chevron.left.forwardslash.chevron.right"
        case .codeBlock:
            return "curlybraces"
        case .knowledgeAnswer:
            return "books.vertical"
        case .decisionTree:
            return "arrow.triangle.branch"
        case .prosCons:
            return "scale.3d"
        case .brainstorm:
            return "lightbulb"
        case .multiStepPlan:
            return "list.number"
        }
    }
}

private struct AssistantCapabilitySurfaceCard: View {
    let surface: JarvisAssistantCapabilitySurface

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerView
            entriesView
            previewView

            if let approval = surface.approval {
                AssistantApprovalPanel(approval: approval)
            }

            footnoteView
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(borderColor, lineWidth: 1)
        )
    }

    @ViewBuilder
    private var headerView: some View {
        HStack(alignment: .top, spacing: 10) {
            headerIcon

            VStack(alignment: .leading, spacing: 4) {
                Text(surface.title)
                    .font(.system(.caption, design: .rounded, weight: .bold))
                    .foregroundStyle(JarvisModernTheme.textPrimary)
                if !surface.summary.isEmpty {
                    Text(surface.summary)
                        .font(.system(.caption, design: .rounded, weight: .medium))
                        .foregroundStyle(JarvisModernTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 8)

            AssistantCapabilityStatusChip(status: surface.status)
        }
    }

    private var headerIcon: some View {
        Image(systemName: iconName)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(accentColor)
            .frame(width: 28, height: 28)
            .background(accentColor.opacity(0.14), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    @ViewBuilder
    private var entriesView: some View {
        if !surface.entries.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(surface.entries) { entry in
                    entryView(entry)
                }
            }
        }
    }

    private func entryView(_ entry: JarvisAssistantCapabilityEntry) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(entry.title)
                .font(.system(.caption, design: .rounded, weight: .semibold))
                .foregroundStyle(JarvisModernTheme.textPrimary)
            if let subtitle = entry.subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.system(.caption2, design: .rounded, weight: .medium))
                    .foregroundStyle(JarvisModernTheme.textTertiary)
                    .textSelection(.enabled)
            }
            if !entry.facts.isEmpty {
                FlexibleFactWrap(facts: entry.facts)
            }
        }
        .padding(10)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    @ViewBuilder
    private var previewView: some View {
        if let previewText = surface.previewText, !previewText.isEmpty {
            Text(previewText)
                .font(.system(.caption, design: .monospaced, weight: .medium))
                .foregroundStyle(JarvisModernTheme.textSecondary)
                .textSelection(.enabled)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(JarvisModernTheme.border, lineWidth: 1)
                )
        }
    }

    @ViewBuilder
    private var footnoteView: some View {
        if let footnote = surface.footnote, !footnote.isEmpty {
            Text(footnote)
                .font(.system(.caption2, design: .rounded, weight: .medium))
                .foregroundStyle(JarvisModernTheme.textTertiary)
        }
    }

    private var accentColor: Color {
        switch surface.kind {
        case .fileSearchResults, .filePreview, .allowedRoots:
            return .cyan
        case .patchApproval, .projectAction:
            return JarvisModernTheme.accent
        case .macAction:
            return .mint
        case .shellResult:
            return .orange
        }
    }

    private var borderColor: Color {
        switch surface.status {
        case .pending:
            return JarvisModernTheme.accent.opacity(0.42)
        case .success:
            return Color.cyan.opacity(0.32)
        case .failed, .denied:
            return JarvisModernTheme.warning.opacity(0.42)
        case .unsupported, .cancelled:
            return JarvisModernTheme.borderStrong
        case .executing:
            return accentColor.opacity(0.48)
        }
    }

    private var iconName: String {
        switch surface.kind {
        case .fileSearchResults:
            return "doc.text.magnifyingglass"
        case .filePreview:
            return "doc.text"
        case .patchApproval:
            return "square.and.pencil"
        case .allowedRoots:
            return "folder.badge.checkmark"
        case .macAction:
            return "macwindow"
        case .shellResult:
            return "terminal"
        case .projectAction:
            return "shippingbox"
        }
    }
}

private struct FlexibleFactWrap: View {
    let facts: [JarvisAssistantCapabilityFact]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(stride(from: 0, to: facts.count, by: 2)), id: \.self) { start in
                let row = Array(facts[start..<min(start + 2, facts.count)])
                HStack(spacing: 6) {
                    ForEach(row) { fact in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(fact.label.uppercased())
                                .font(.system(size: 9, weight: .bold, design: .rounded))
                                .foregroundStyle(JarvisModernTheme.textTertiary)
                            Text(fact.value)
                                .font(.system(.caption2, design: .rounded, weight: .semibold))
                                .foregroundStyle(JarvisModernTheme.textPrimary)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    if row.count == 1 {
                        Spacer(minLength: 0)
                    }
                }
            }
        }
    }
}

private struct AssistantCapabilityStatusChip: View {
    let status: JarvisAssistantCapabilityStatus

    var body: some View {
        Text(label)
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(color.opacity(0.14), in: Capsule())
            .overlay(
                Capsule()
                    .stroke(color.opacity(0.36), lineWidth: 1)
            )
    }

    private var label: String {
        switch status {
        case .pending:
            return "Pending"
        case .executing:
            return "Executing"
        case .success:
            return "Success"
        case .failed:
            return "Failed"
        case .denied:
            return "Denied"
        case .unsupported:
            return "Unsupported"
        case .cancelled:
            return "Cancelled"
        }
    }

    private var color: Color {
        switch status {
        case .pending:
            return JarvisModernTheme.accent
        case .executing:
            return .cyan
        case .success:
            return .mint
        case .failed, .denied:
            return JarvisModernTheme.warning
        case .unsupported, .cancelled:
            return JarvisModernTheme.textSecondary
        }
    }
}

private struct AssistantApprovalPanel: View {
    let approval: JarvisAssistantApprovalSurface

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.shield")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(JarvisModernTheme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(approval.title)
                        .font(.system(.caption, design: .rounded, weight: .bold))
                        .foregroundStyle(JarvisModernTheme.textPrimary)
                    Text(approval.message)
                        .font(.system(.caption2, design: .rounded, weight: .medium))
                        .foregroundStyle(JarvisModernTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                AssistantApprovalDecisionChip(decision: approval.decision)
            }

            HStack(spacing: 8) {
                Button(approval.approveTitle) {}
                    .buttonStyle(JarvisModernPrimaryButtonStyle())
                    .disabled(!approval.runtimeHookAvailable || approval.decision != .pending)

                Button(approval.denyTitle) {}
                    .buttonStyle(JarvisModernSecondaryButtonStyle())
                    .disabled(!approval.runtimeHookAvailable || approval.decision != .pending)
            }

            if !approval.runtimeHookAvailable && approval.decision == .pending {
                Text("Approval controls are staged in the UI and waiting on the runtime decision hook.")
                    .font(.system(.caption2, design: .rounded, weight: .medium))
                    .foregroundStyle(JarvisModernTheme.textTertiary)
            }
        }
        .padding(12)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(JarvisModernTheme.borderStrong, lineWidth: 1)
        )
    }
}

private struct AssistantApprovalDecisionChip: View {
    let decision: JarvisAssistantApprovalDecision

    var body: some View {
        Text(label)
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(color.opacity(0.14), in: Capsule())
    }

    private var label: String {
        switch decision {
        case .pending:
            return "Awaiting"
        case .approved:
            return "Approved"
        case .denied:
            return "Denied"
        }
    }

    private var color: Color {
        switch decision {
        case .pending:
            return JarvisModernTheme.accent
        case .approved:
            return .mint
        case .denied:
            return JarvisModernTheme.warning
        }
    }
}

private struct AssistantEmptyState: View {
    @EnvironmentObject private var appModel: JarvisPhoneAppModel

    var body: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle()
                    .fill(JarvisModernTheme.glowPrimary)
                    .frame(width: 88, height: 88)
                    .blur(radius: 12)
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [JarvisModernTheme.accent, JarvisModernTheme.accentSoft],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 58, height: 58)
                    .overlay(
                        Image(systemName: "sparkles")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.95))
                    )
            }
            Text("Ask, speak, or hand off the next action.")
                .font(.system(.title3, design: .rounded, weight: .bold))
                .foregroundStyle(JarvisModernTheme.textPrimary)
            Text("JARVIS is set up for direct answers now, and the surface is ready for voice, files, tools, memory, and project actions as those lanes come online.")
                .font(.system(.footnote, design: .rounded, weight: .medium))
                .foregroundStyle(JarvisModernTheme.textSecondary)
                .multilineTextAlignment(.center)

            VStack(spacing: 8) {
                starterButton("Talk to JARVIS", icon: "waveform") {
                    appModel.setAssistantInputMode(.voice)
                    appModel.startVoicePreview()
                }
                starterButton("Summarize pasted text", icon: "text.quote") {
                    appModel.apply(route: JarvisLaunchRoute(action: .summarize, source: "assistant.empty"))
                }
                starterButton("Draft a reply", icon: "arrowshape.turn.up.left") {
                    appModel.apply(route: JarvisLaunchRoute(action: .draftReply, source: "assistant.empty"))
                }
                starterButton("Search my local knowledge", icon: "books.vertical") {
                    appModel.apply(route: JarvisLaunchRoute(action: .knowledge, source: "assistant.empty"))
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
    }

    private func starterButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.system(.caption, design: .rounded, weight: .semibold))
                .foregroundStyle(JarvisModernTheme.textPrimary)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .frame(maxWidth: .infinity)
                .background(JarvisModernTheme.cardSecondary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(JarvisModernTheme.borderStrong, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}

private struct AssistantVoiceMeter: View {
    let state: JarvisPhoneAppModel.AssistantExperienceState
    let speechState: JarvisSpeechState

    var body: some View {
        HStack(spacing: 5) {
            ForEach(Array(levels.enumerated()), id: \.offset) { index, level in
                Capsule(style: .continuous)
                    .fill(tint.opacity(0.35 + (Double(index) * 0.08)))
                    .frame(maxWidth: .infinity)
                    .frame(height: level)
            }
        }
        .frame(height: 24)
    }

    private var tint: Color {
        switch state {
        case .listening, .transcribing:
            return .cyan
        case .responding:
            return .mint
        case .processing, .thinking, .grounding:
            return JarvisModernTheme.accent
        case .error:
            return JarvisModernTheme.warning
        default:
            return JarvisModernTheme.textSecondary
        }
    }

    private var levels: [CGFloat] {
        if state == .responding {
            return [12, 20, 26, 18, 24, 16, 22]
        }

        switch speechState {
        case .listening:
            return [10, 18, 24, 16, 22, 14, 20]
        case .transcribing:
            return [8, 14, 18, 22, 18, 14, 8]
        case .stopping:
            return [6, 10, 12, 10, 8, 7, 6]
        case .ready, .requestingPermission:
            return [6, 10, 14, 18, 14, 10, 6]
        case .failed:
            return [8, 8, 8, 8, 8, 8, 8]
        case .idle:
            return [6, 9, 12, 16, 12, 9, 6]
        }
    }
}

private struct AssistantControlsSheet: View {
    @EnvironmentObject private var appModel: JarvisPhoneAppModel
    @Environment(\.dismiss) private var dismiss

    private var selectedTask: JarvisAssistantTask {
        appModel.assistantTask == .knowledgeAnswer ? .knowledgeAnswer : .chat
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    JarvisModernSectionHeader("Assistant Controls", eyebrow: "Adjust", subtitle: "Keep the main chat surface clean and move secondary controls here.")

                    JarvisModernCard {
                        VStack(alignment: .leading, spacing: 14) {
                            Text("Source")
                                .font(.system(.headline, design: .rounded, weight: .semibold))
                                .foregroundStyle(JarvisModernTheme.textPrimary)
                    Picker("Assistant Source", selection: Binding(
                        get: { selectedTask },
                        set: { appModel.selectAssistantSurfaceTask($0) }
                    )) {
                        Text("Chat").tag(JarvisAssistantTask.chat)
                        Text("Knowledge").tag(JarvisAssistantTask.knowledgeAnswer)
                    }
                    .pickerStyle(.segmented)
                        }
                    }

                    JarvisModernCard(secondary: true) {
                        VStack(alignment: .leading, spacing: 14) {
                            Text("Model")
                                .font(.system(.headline, design: .rounded, weight: .semibold))
                                .foregroundStyle(JarvisModernTheme.textPrimary)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(appModel.activeModel?.displayName ?? "No active model")
                            .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        Text(appModel.runtimeState.title)
                            .font(.system(.caption, design: .rounded, weight: .medium))
                            .foregroundStyle(JarvisModernTheme.textSecondary)
                    }

                    Button {
                        dismiss()
                        appModel.presentModelLibrary()
                    } label: {
                        Label("Open Model Library", systemImage: "cpu")
                    }
                    .buttonStyle(JarvisModernSecondaryButtonStyle())
                        }
                    }

                    JarvisModernCard(secondary: true) {
                        VStack(alignment: .leading, spacing: 14) {
                            Text("Assistant Style")
                                .font(.system(.headline, design: .rounded, weight: .semibold))
                                .foregroundStyle(JarvisModernTheme.textPrimary)
                    Picker("Response Style", selection: $appModel.settings.responseStyle) {
                        ForEach(JarvisAssistantResponseStyle.allCases) { style in
                            Text(style.displayName).tag(style)
                        }
                    }

                    Toggle("Enable Memory", isOn: $appModel.settings.memoryEnabled)
                    Toggle("Enable Diagnostics", isOn: $appModel.settings.showRuntimeDiagnostics)
                        }
                    }

                    JarvisModernCard(secondary: true) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Conversation")
                                .font(.system(.headline, design: .rounded, weight: .semibold))
                                .foregroundStyle(JarvisModernTheme.textPrimary)

                            Button {
                                dismiss()
                                appModel.startNewConversation()
                            } label: {
                                Label("New Conversation", systemImage: "square.and.pencil")
                            }
                            .buttonStyle(JarvisModernSecondaryButtonStyle())

                            Button {
                                dismiss()
                                appModel.addKnowledgeItemFromConversation()
                            } label: {
                                Label("Save Latest Reply", systemImage: "bookmark")
                            }
                            .disabled(appModel.conversation.messages.last(where: { $0.role == .assistant }) == nil)
                            .buttonStyle(JarvisModernSecondaryButtonStyle())

                            Button {
                                dismiss()
                                appModel.apply(route: JarvisLaunchRoute(action: JarvisLaunchAction.settings, source: "assistant.controls"))
                            } label: {
                                Label("Open Full Settings", systemImage: "gearshape")
                            }
                            .buttonStyle(JarvisModernSecondaryButtonStyle())
                        }
                    }

                    if appModel.settings.showRuntimeDiagnostics {
                        JarvisModernCard(secondary: true) {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Diagnostics")
                                    .font(.system(.headline, design: .rounded, weight: .semibold))
                                    .foregroundStyle(JarvisModernTheme.textPrimary)
                                LabeledContent("Runtime", value: appModel.runtimeState.title)
                                LabeledContent("Task", value: appModel.assistantTask.displayName)
                                if !appModel.lastPromptDebugSummary.isEmpty {
                                    Text(appModel.lastPromptDebugSummary)
                                        .font(.system(.caption, design: .rounded, weight: .medium))
                                        .foregroundStyle(JarvisModernTheme.textSecondary)
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, JarvisModernTheme.screenPadding)
            .padding(.top, 18)
            .padding(.bottom, 28)
            .background(JarvisModernBackground())
            .navigationTitle("Assistant Controls")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct AssistantTranscriptBottomOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
