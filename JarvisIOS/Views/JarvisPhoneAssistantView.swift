import SwiftUI

struct JarvisPhoneAssistantView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appModel: JarvisPhoneAppModel

    @FocusState private var isComposerFocused: Bool

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 10) {
                        ForEach(appModel.conversation.messages) { message in
                            messageBubble(message)
                                .id(message.id)
                        }

                        if appModel.conversation.messages.isEmpty {
                            emptyState
                                .transition(.opacity)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 32)
                }
                .background(
                    LinearGradient(
                        colors: [Color.black.opacity(0.95), Color.black.opacity(0.75)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .ignoresSafeArea()
                )
                .safeAreaInset(edge: .bottom) {
                    composerBar
                }
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Done") { dismiss() }
                            .font(.system(.body, design: .rounded, weight: .semibold))
                    }
                    ToolbarItem(placement: .principal) {
                        VStack(spacing: 2) {
                            Text("Ask Jarvis")
                                .font(.system(.headline, design: .rounded, weight: .semibold))
                            Text(appModel.runtimeState.title)
                                .font(.system(.caption2, design: .rounded, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            appModel.addKnowledgeItemFromConversation()
                        } label: {
                            Image(systemName: "bookmark")
                        }
                        .accessibilityLabel("Save latest answer")
                    }
                }
                .onChange(of: appModel.conversation.messages.count) { _, _ in
                    withAnimation(.easeOut(duration: 0.18)) {
                        if let id = appModel.conversation.messages.last?.id {
                            proxy.scrollTo(id, anchor: .bottom)
                        }
                    }
                }
                .onChange(of: appModel.shouldFocusComposer) { _, shouldFocus in
                    guard shouldFocus else { return }
                    isComposerFocused = true
                    appModel.shouldFocusComposer = false
                }
                .onAppear {
                    isComposerFocused = true
                }
            }
        }
    }

    private var composerBar: some View {
        VStack(spacing: 10) {
            if appModel.needsModelSetup {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text("Import and activate a GGUF model before sending.")
                        .font(.system(.footnote, design: .rounded, weight: .medium))
                        .foregroundStyle(.white.opacity(0.9))
                    Spacer()
                    Button("Setup") {
                        dismiss()
                        appModel.showSetupFlow = true
                    }
                    .font(.system(.footnote, design: .rounded, weight: .semibold))
                }
                .padding(.horizontal, 14)
            }

            if !appModel.canRunInference {
                HStack(spacing: 10) {
                    Image(systemName: "cpu")
                        .foregroundStyle(.orange)
                    Text(appModel.runtimeBlockedReason)
                        .font(.system(.footnote, design: .rounded, weight: .medium))
                        .foregroundStyle(.white.opacity(0.9))
                    Spacer()
                }
                .padding(.horizontal, 14)
            }

            if appModel.isSending {
                HStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Generating on-device")
                        .font(.system(.footnote, design: .rounded, weight: .medium))
                    Spacer()
                    Button("Cancel") {
                        appModel.cancelStreaming()
                    }
                    .font(.system(.footnote, design: .rounded, weight: .semibold))
                }
                .foregroundStyle(.white.opacity(0.9))
                .padding(.horizontal, 14)
            }

            HStack(spacing: 10) {
                TextField("Ask anything", text: $appModel.draft, axis: .vertical)
                    .focused($isComposerFocused)
                    .lineLimit(1...5)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.white.opacity(0.12))
                    )

                Button {
                    appModel.sendCurrentDraft()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 30, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                }
                .disabled(appModel.needsModelSetup || !appModel.canRunInference || appModel.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .tint(Color(red: 0.14, green: 0.74, blue: 0.88))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.white.opacity(0.14), lineWidth: 1)
            )
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .background(
            Color.black.opacity(0.35)
                .blur(radius: 3)
        )
    }

    private func messageBubble(_ message: JarvisChatMessage) -> some View {
        let isUser = message.role == .user

        return HStack {
            if isUser { Spacer(minLength: 40) }

            VStack(alignment: .leading, spacing: 6) {
                Text(isUser ? "You" : "Jarvis")
                    .font(.system(.caption2, design: .rounded, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))

                Text(message.text.isEmpty && message.isStreaming ? "…" : message.text)
                    .font(.system(.body, design: .rounded, weight: .medium))
                    .foregroundStyle(.white)
                    .textSelection(.enabled)
                    .animation(.easeOut(duration: 0.12), value: message.text)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isUser ? Color(red: 0.13, green: 0.49, blue: 0.80) : Color.white.opacity(0.12))
            )

            if !isUser { Spacer(minLength: 40) }
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(.white.opacity(0.8))
            Text("Ask directly and keep it short for fastest local responses.")
                .font(.system(.subheadline, design: .rounded, weight: .medium))
                .foregroundStyle(.white.opacity(0.85))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(28)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color.white.opacity(0.08)))
    }
}
