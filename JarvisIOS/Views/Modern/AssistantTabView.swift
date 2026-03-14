import SwiftUI
import UIKit

struct AssistantTabView: View {
    @EnvironmentObject private var appModel: JarvisPhoneAppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var composerFocused: Bool

    var body: some View {
        NavigationStack {
            ZStack {
                AssistantBackdrop(state: appModel.assistantExperienceState)

                VStack(spacing: 14) {
                    AssistantPresenceSurface(
                        state: appModel.assistantExperienceState,
                        mode: appModel.assistantInputMode,
                        transcript: appModel.assistantLiveTranscript,
                        reduceMotion: reduceMotion
                    )

                    if appModel.assistantInputMode == .voice {
                        voiceTranscriptPanel
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }

                    messagesPanel

                    if showGroundingContext {
                        groundingContextPanel
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }

                    if !appModel.assistantSuggestions.isEmpty,
                       appModel.assistantExperienceState == .groundedAnswerReady {
                        suggestionStrip
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }

                    composerPanel
                }
                .padding(.horizontal, 14)
                .padding(.top, 10)
                .padding(.bottom, 8)
            }
            .navigationTitle("Assistant")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if appModel.shouldShowAssistantBackButton {
                        Button {
                            appModel.returnFromAssistant()
                        } label: {
                            Label("Back", systemImage: "chevron.left")
                        }
                    }
                }
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 2) {
                        Text("Assistant")
                            .font(.subheadline.weight(.semibold))
                        Text(appModel.assistantExperienceState.title)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            appModel.addKnowledgeItemFromConversation()
                        } label: {
                            Label("Save to Knowledge", systemImage: "bookmark")
                        }

                        Button(role: .destructive) {
                            appModel.startNewConversation()
                        } label: {
                            Label("Clear Conversation", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .onChange(of: appModel.shouldFocusComposer) { _, shouldFocus in
                guard shouldFocus else { return }
                composerFocused = true
                appModel.shouldFocusComposer = false
            }
            .onAppear {
                if appModel.assistantInputMode == .text {
                    composerFocused = true
                }
            }
            .animation(.spring(response: 0.42, dampingFraction: 0.86), value: appModel.assistantExperienceState)
        }
    }

    private var voiceTranscriptPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Live transcript", systemImage: "waveform")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(voiceStateLabel)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.78))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color.white.opacity(0.10), in: Capsule())
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
            TextField("Transcript appears here (voice pipeline can feed this directly)", text: $appModel.assistantLiveTranscript, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(2...4)
                .padding(10)
                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.white.opacity(0.16), lineWidth: 1)
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
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.white.opacity(0.16), lineWidth: 1)
                )
        )
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
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 10) {
                    if appModel.conversation.messages.isEmpty {
                        AssistantEmptyState()
                    }

                    ForEach(appModel.conversation.messages) { message in
                        AssistantMessageRow(message: message)
                            .id(message.id)
                    }
                }
                .padding(10)
            }
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.black.opacity(0.22))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(Color.white.opacity(0.14), lineWidth: 1)
                    )
            )
            .onAppear {
                guard appModel.settings.autoScrollConversation,
                      let last = appModel.conversation.messages.last?.id else { return }
                proxy.scrollTo(last, anchor: .bottom)
            }
            .onChange(of: appModel.conversation.messages.count) { _, _ in
                guard appModel.settings.autoScrollConversation else { return }
                guard let last = appModel.conversation.messages.last?.id else { return }
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo(last, anchor: .bottom)
                }
            }
        }
    }

    private var showGroundingContext: Bool {
        switch appModel.assistantExperienceState {
        case .grounding, .responding, .groundedAnswerReady:
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
                    appModel.apply(route: JarvisLaunchRoute(action: .search, source: "assistant.context"))
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

    private var suggestionStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(appModel.assistantSuggestions) { suggestion in
                    Button {
                        appModel.performAssistantSuggestion(suggestion)
                    } label: {
                        Label(suggestion.title, systemImage: suggestion.icon)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(Color.white.opacity(0.12), in: Capsule())
                            .overlay(
                                Capsule()
                                    .stroke(Color.white.opacity(0.20), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 2)
        }
    }

    private var composerPanel: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                modeButton(title: "Text", icon: "text.bubble", mode: .text)
                modeButton(title: "Voice", icon: "waveform", mode: .voice)
                modeButton(title: "Visual", icon: "viewfinder", mode: .visual)
            }

            if case .unavailable(let reason) = appModel.assistantExperienceState {
                stateInfoRow(icon: "exclamationmark.triangle.fill", text: reason, tint: .orange)
                recoveryActionsRow
            } else if case .error(let message) = appModel.assistantExperienceState {
                stateInfoRow(icon: "xmark.octagon.fill", text: message, tint: .red)
                recoveryActionsRow
            } else if appModel.assistantExperienceState == .grounding {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Searching local context for grounded output")
                        .font(.caption.weight(.medium))
                    Spacer()
                }
                .foregroundStyle(.white.opacity(0.92))
                .padding(.horizontal, 10)
            } else if appModel.isSending {
                HStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Generating locally")
                        .font(.caption.weight(.medium))
                    Spacer()
                    Button("Cancel") {
                        appModel.cancelStreaming()
                    }
                    .font(.caption.weight(.semibold))
                }
                .foregroundStyle(.white.opacity(0.92))
                .padding(.horizontal, 10)
            }

            if case .warming(_, let progress, _) = appModel.runtimeState {
                VStack(alignment: .leading, spacing: 6) {
                    ProgressView(value: progress)
                        .tint(.cyan)
                    Text("Preparing assistant engine")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.82))
                }
                .padding(.horizontal, 10)
            }

            if appModel.settings.showRuntimeDiagnostics {
                diagnosticsRow
            }

            HStack(spacing: 10) {
                TextField("Ask Jarvis", text: $appModel.draft, axis: .vertical)
                    .focused($composerFocused)
                    .lineLimit(1...5)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 11)
                    .background(Color.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                Button {
                    if appModel.assistantInputMode == .voice {
                        appModel.stopVoicePreview(commit: true)
                    } else {
                        appModel.sendCurrentDraft()
                    }
                } label: {
                    Image(systemName: sendIcon)
                        .font(.system(size: 27, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                }
                .disabled(!canSend)
                .tint(.cyan)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.white.opacity(0.18), lineWidth: 1)
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
                Text(appModel.runtimeEngineName)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.72))
            }

            Text("\(appModel.modelFileAccessState.title): \(appModel.modelFileAccessDetail)")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.72))
        }
        .foregroundStyle(.white.opacity(0.88))
        .padding(.horizontal, 10)
    }

    private var recoveryActionsRow: some View {
        HStack(spacing: 8) {
            if appModel.needsModelSetup {
                Button("Set Up") {
                    appModel.showSetupFlow = true
                }
            } else {
                if !appModel.speechPermissions.isGranted {
                    Button("Voice Access") {
                        guard let settingsURL = URL(string: UIApplication.openSettingsURLString) else { return }
                        UIApplication.shared.open(settingsURL)
                    }
                }
                if appModel.canRunInference {
                    Button("Retry Warm") {
                        appModel.retryRuntimeWarmup()
                    }
                }
                Button("Models") {
                    appModel.presentModelLibrary()
                }
            }
        }
        .font(.caption.weight(.semibold))
        .buttonStyle(.bordered)
        .padding(.horizontal, 10)
    }

    private var canSend: Bool {
        if appModel.assistantInputMode == .voice {
            return !appModel.assistantLiveTranscript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return !appModel.needsModelSetup &&
        appModel.canRunInference &&
        !appModel.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !appModel.isSending
    }

    private var sendIcon: String {
        appModel.assistantInputMode == .voice ? "waveform.circle.fill" : "arrow.up.circle.fill"
    }

    private func modeButton(title: String, icon: String, mode: JarvisPhoneAppModel.AssistantInputMode) -> some View {
        let isActive = appModel.assistantInputMode == mode
        return Button {
            appModel.setAssistantInputMode(mode)
            if mode == .text {
                composerFocused = true
            }
        } label: {
            Label(title, systemImage: icon)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
                .background(isActive ? Color.cyan.opacity(0.22) : Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .stroke(isActive ? Color.cyan.opacity(0.6) : Color.white.opacity(0.16), lineWidth: 1)
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
        LinearGradient(
            colors: [
                Color.black,
                Color(red: 0.05, green: 0.08, blue: 0.16),
                Color(red: 0.03, green: 0.04, blue: 0.12)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay(
            RadialGradient(
                colors: [topColor, .clear],
                center: .top,
                startRadius: 16,
                endRadius: 380
            )
        )
        .ignoresSafeArea()
    }

    private var topColor: Color {
        switch state {
        case .listening, .transcribing:
            return Color.cyan.opacity(0.28)
        case .thinking, .grounding, .responding:
            return Color.indigo.opacity(0.30)
        case .error:
            return Color.red.opacity(0.24)
        default:
            return Color.blue.opacity(0.20)
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
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(orbTint.opacity(0.22))
                    .frame(width: pulse ? 96 : 84, height: pulse ? 96 : 84)
                    .blur(radius: 10)
                Circle()
                    .stroke(orbTint.opacity(0.55), lineWidth: 1.4)
                    .frame(width: pulse ? 88 : 76, height: pulse ? 88 : 76)
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [orbTint.opacity(0.92), orbTint.opacity(0.34)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 54, height: 54)
                    .overlay(
                        Image(systemName: icon)
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.95))
                    )
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(headline)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white)
                Text(subline)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.78))
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.white.opacity(0.18), lineWidth: 1)
                )
        )
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
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
        case .grounding:
            return "Retrieving local context."
        case .responding:
            return "Streaming answer."
        case .groundedAnswerReady:
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
        case .thinking, .grounding, .responding:
            return .indigo
        case .groundedAnswerReady:
            return .green
        case .error:
            return .red
        case .unavailable:
            return .orange
        default:
            return .blue
        }
    }
}

private struct AssistantMessageRow: View {
    let message: JarvisChatMessage

    var body: some View {
        let isUser = message.role == .user
        HStack {
            if isUser { Spacer(minLength: 42) }
            VStack(alignment: .leading, spacing: 6) {
                Text(isUser ? "You" : "Jarvis")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.72))
                if message.isStreaming && message.text.isEmpty {
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Thinking…")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.72))
                    }
                } else {
                    Text(message.text)
                        .font(.body)
                        .foregroundStyle(.white)
                        .textSelection(.enabled)
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isUser ? Color.indigo.opacity(0.34) : Color.white.opacity(0.10))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(isUser ? Color.indigo.opacity(0.7) : Color.white.opacity(0.15), lineWidth: 1)
            )
            if !isUser { Spacer(minLength: 42) }
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

private struct AssistantEmptyState: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "sparkles.rectangle.stack.fill")
                .font(.system(size: 34))
                .foregroundStyle(.white.opacity(0.82))
            Text("Start in text, voice, or visual mode.")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white.opacity(0.90))
            Text("Assistant states and transitions adapt as you listen, think, and answer.")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.72))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
    }
}
