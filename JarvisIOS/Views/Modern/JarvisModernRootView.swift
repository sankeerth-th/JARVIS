import SwiftUI

struct JarvisModernRootView: View {
    @EnvironmentObject private var appModel: JarvisPhoneAppModel

    var body: some View {
        ZStack {
            TabView(selection: Binding(
                get: { appModel.selectedTab },
                set: { appModel.handleTabSelection($0) }
            )) {
                ModernHomeTabView()
                    .tag(JarvisAppTab.home)

                AssistantTabView()
                    .tag(JarvisAppTab.assistant)

                ModernVisualIntelligenceTabView()
                    .tag(JarvisAppTab.visual)

                KnowledgeTabView()
                    .tag(JarvisAppTab.knowledge)

                SettingsTabView()
                    .tag(JarvisAppTab.settings)
            }
            .toolbar(.hidden, for: .tabBar)
            .safeAreaInset(edge: .bottom) {
                if !appModel.shouldHideFloatingTabBar {
                    JarvisModernFloatingTabBar(selection: Binding(
                        get: { appModel.selectedTab },
                        set: { appModel.handleTabSelection($0) }
                    ))
                    .padding(.bottom, 4)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }

            if shouldShowAssistantAnchor {
                JarvisFloatingAssistantHost()
                    .environmentObject(appModel)
                    .padding(.horizontal, JarvisModernTheme.screenPadding)
                    .padding(.bottom, appModel.shouldHideFloatingTabBar ? 22 : JarvisModernTheme.floatingTabBarHeight + 14)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .transition(.scale(scale: 0.96).combined(with: .opacity))
            }
        }
        .tint(JarvisModernTheme.accent)
        .animation(JarvisModernMotion.contentUpdate, value: appModel.shouldHideFloatingTabBar)
        .animation(JarvisModernMotion.surfaceExpand, value: shouldShowAssistantAnchor)
        .onChange(of: appModel.isAssistantPresented) { _, isPresented in
            guard isPresented else { return }
            appModel.isAssistantPresented = false
            appModel.apply(
                route: JarvisLaunchRoute.assistant(
                    .assistant,
                    source: .legacy,
                    shouldFocusComposer: true
                )
            )
        }
        .onChange(of: appModel.isKnowledgePresented) { _, isPresented in
            guard isPresented else { return }
            appModel.isKnowledgePresented = false
            appModel.apply(route: JarvisLaunchRoute.assistant(.knowledge, source: .legacy))
        }
        .onChange(of: appModel.isSettingsPresented) { _, isPresented in
            guard isPresented else { return }
            appModel.isSettingsPresented = false
            appModel.apply(route: JarvisLaunchRoute(action: JarvisLaunchAction.settings, source: "legacy.sheet.settings"))
        }
        .onChange(of: appModel.isVisualIntelligencePresented) { _, isPresented in
            guard isPresented else { return }
            appModel.isVisualIntelligencePresented = false
            appModel.apply(route: JarvisLaunchRoute.assistant(.visual, source: .legacy))
        }
        .sheet(isPresented: $appModel.isModelLibraryPresented) {
            NavigationStack {
                JarvisModernModelLibraryView()
            }
            .environmentObject(appModel)
        }
        .fullScreenCover(isPresented: $appModel.showSetupFlow) {
            JarvisModernSetupView()
                .interactiveDismissDisabled(appModel.needsModelSetup)
        }
    }

    private var shouldShowAssistantAnchor: Bool {
        guard !appModel.isAssistantKeyboardActive else { return false }
        return appModel.selectedTab != .assistant || appModel.assistantExperienceState != .idle
    }
}

struct ModernHomeTabView: View {
    @EnvironmentObject private var appModel: JarvisPhoneAppModel

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: JarvisModernTheme.sectionSpacing) {
                    ModernHomeGreetingHeader()
                    ModernHomeStatusCard()
                    ModernQuickActionsSection()
                    ModernHomeNowSection()
                    ModernModelStatusSection()
                    ModernRecentConversationsSection()
                }
                .padding(.horizontal, JarvisModernTheme.screenPadding)
                .padding(.top, 22)
                .padding(.bottom, 132)
            }
            .background(JarvisModernBackground())
            .toolbarBackground(.hidden, for: .navigationBar)
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

struct ModernHomeGreetingHeader: View {
    @EnvironmentObject private var appModel: JarvisPhoneAppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(Date.now.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                .font(.system(.caption, design: .rounded, weight: .semibold))
                .foregroundStyle(JarvisModernTheme.accent.opacity(0.82))

            VStack(alignment: .leading, spacing: 8) {
                Text(greetingTitle)
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundStyle(JarvisModernTheme.textSecondary)
                Text("JARVIS feels ready before you ask.")
                    .font(.system(size: 36, weight: .heavy, design: .rounded))
                    .foregroundStyle(JarvisModernTheme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Voice-forward, local-first, and built to move from conversation into files, tools, and project actions without losing context.")
                    .font(.system(.subheadline, design: .rounded, weight: .medium))
                    .foregroundStyle(JarvisModernTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 8) {
                JarvisModernChip(title: "Voice First", icon: "waveform", tint: .cyan, active: true)
                JarvisModernChip(title: "Local Runtime", icon: "cpu.fill", tint: JarvisModernTheme.accentSoft, active: true)
                JarvisModernChip(title: "Action Ready", icon: "bolt.fill", tint: JarvisModernTheme.warning, active: false)
            }
        }
    }

    private var greetingTitle: String {
        let hour = Calendar.current.component(.hour, from: .now)
        if hour < 12 { return "Good morning." }
        if hour < 18 { return "Good afternoon." }
        return "Good evening."
    }
}

struct ModernHomeStatusCard: View {
    @EnvironmentObject private var appModel: JarvisPhoneAppModel

    var body: some View {
        JarvisModernCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 14) {
                    JarvisModernIconBadge(systemName: statusIcon, tint: statusColor)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(statusTitle)
                            .font(.system(.title3, design: .rounded, weight: .bold))
                            .foregroundStyle(JarvisModernTheme.textPrimary)
                        Text(statusSubtitle)
                            .font(.system(.footnote, design: .rounded, weight: .medium))
                            .foregroundStyle(JarvisModernTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer()
                }

                actionRow

                HStack(spacing: 10) {
                    statusPill(title: appModel.assistantExperienceState.title, icon: "sparkles", tint: statusColor)
                    statusPill(title: appModel.assistantInputMode == .voice ? "Voice Ready" : "Tap To Talk", icon: "waveform", tint: .cyan)
                    if let modelName = appModel.activeModel?.displayName {
                        statusPill(title: modelName, icon: "cpu", tint: JarvisModernTheme.accentSoft)
                    }
                }
            }
        }
    }

    private func statusPill(title: String, icon: String, tint: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption.weight(.semibold))
            Text(title)
                .lineLimit(1)
                .font(.system(.caption, design: .rounded, weight: .semibold))
        }
        .foregroundStyle(JarvisModernTheme.textPrimary)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            Capsule(style: .continuous)
                .fill(tint.opacity(0.12))
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(tint.opacity(0.32), lineWidth: 1)
                )
        )
    }

    @ViewBuilder
    private var actionRow: some View {
        if appModel.needsModelSetup {
            Button {
                appModel.showSetupFlow = true
            } label: {
                Label(appModel.hasReadyModel ? "Choose Model" : "Set Up Model", systemImage: "arrow.right.circle.fill")
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(JarvisModernPrimaryButtonStyle())
        } else {
            HStack(spacing: 10) {
                if canWarm {
                    Button {
                        appModel.warmModel()
                    } label: {
                        Label("Warm", systemImage: "flame.fill")
                    }
                    .buttonStyle(JarvisModernCapsuleActionStyle(tint: JarvisModernTheme.warning, emphasized: true))
                }

                Button {
                    appModel.apply(
                        route: JarvisLaunchRoute.assistant(
                            .voice,
                            task: .chat,
                            source: .inApp,
                            shouldStartListening: true
                        )
                    )
                } label: {
                    Label("Voice", systemImage: "waveform")
                }
                .buttonStyle(JarvisModernCapsuleActionStyle())

                Button {
                    appModel.apply(
                        route: JarvisLaunchRoute.assistant(
                            .visual,
                            task: .visualDescribe,
                            source: .inApp
                        )
                    )
                } label: {
                    Label("Visual", systemImage: "viewfinder")
                }
                .buttonStyle(JarvisModernCapsuleActionStyle())

                if case .failed = appModel.runtimeState {
                    Button {
                        appModel.retryRuntimeWarmup()
                    } label: {
                        Label("Retry", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(JarvisModernCapsuleActionStyle())
                }
            }
            .font(.system(.subheadline, design: .rounded, weight: .semibold))
        }
    }

    private var canWarm: Bool {
        guard appModel.canRunInference else { return false }
        switch appModel.runtimeState {
        case .cold, .failed, .paused:
            return true
        default:
            return false
        }
    }

    private var statusIcon: String {
        switch appModel.runtimeState {
        case .noModel:
            return "exclamationmark.circle.fill"
        case .runtimeUnavailable:
            return "xmark.octagon.fill"
        case .cold:
            return "snowflake.circle.fill"
        case .warming:
            return "hourglass.circle.fill"
        case .ready:
            return "checkmark.circle.fill"
        case .busy:
            return "waveform.circle.fill"
        case .paused:
            return "pause.circle.fill"
        case .failed:
            return "xmark.circle.fill"
        }
    }

    private var statusColor: Color {
        switch appModel.runtimeState {
        case .noModel:
            return .orange
        case .runtimeUnavailable:
            return .orange
        case .cold:
            return .blue
        case .warming:
            return .indigo
        case .ready:
            return .green
        case .busy:
            return .indigo
        case .paused:
            return .yellow
        case .failed:
            return .red
        }
    }

    private var statusTitle: String {
        switch appModel.runtimeState {
        case .noModel:
            return appModel.hasReadyModel ? "Activation Needed" : "Setup Needed"
        case .runtimeUnavailable:
            return "Assistant Limited"
        case .cold:
            return "Ready To Start"
        case .warming:
            return "Preparing Assistant"
        case .ready:
            return "Assistant Ready"
        case .busy:
            return "Working"
        case .paused:
            return "Paused"
        case .failed:
            return "Recovery Needed"
        }
    }

    private var statusSubtitle: String {
        switch appModel.runtimeState {
        case .noModel:
            return appModel.hasReadyModel
                ? "Activate one of your imported models. Import, activation, and warmup are separate steps now."
                : "Import a local GGUF model to unlock assistant mode."
        case .runtimeUnavailable(let reason):
            return reason
        case .cold(let modelName):
            return "\(modelName) is loaded. First request will start it."
        case .warming(let modelName, _, let detail):
            return "Preparing \(modelName): \(detail)"
        case .ready(let modelName):
            return "Using \(modelName) on-device."
        case .busy(let modelName, let detail):
            return "\(modelName): \(detail)"
        case .paused(let modelName, let detail):
            return "\(modelName ?? "Runtime"): \(detail)"
        case .failed(_, let failure):
            return failure.message
        }
    }
}

struct ModernQuickActionsSection: View {
    @EnvironmentObject private var appModel: JarvisPhoneAppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            JarvisModernSectionHeader(
                "Quick Actions",
                eyebrow: "Do",
                subtitle: "One-tap entry points for the tasks that should feel immediate."
            )

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(appModel.quickLaunchItems.prefix(6)) { item in
                        ModernQuickActionButton(item: item)
                    }
                }
            }
        }
    }
}

struct ModernQuickActionButton: View {
    let item: JarvisPhoneAppModel.QuickLaunchItem
    @EnvironmentObject private var appModel: JarvisPhoneAppModel

    var body: some View {
        Button {
            appModel.triggerQuickLaunch(item)
        } label: {
            HStack(spacing: 12) {
                JarvisModernIconBadge(systemName: item.icon, tint: item.route.action == .voice ? .cyan : JarvisModernTheme.accentSoft)
                    .frame(width: 40, height: 40)

                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title)
                        .lineLimit(1)
                        .foregroundStyle(JarvisModernTheme.textPrimary)
                    Text(item.subtitle)
                        .font(.system(.caption2, design: .rounded, weight: .medium))
                        .foregroundStyle(JarvisModernTheme.textSecondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
            }
            .frame(width: 230, alignment: .leading)
        }
        .buttonStyle(JarvisModernCapsuleActionStyle())
    }
}

struct ModernHomeNowSection: View {
    @EnvironmentObject private var appModel: JarvisPhoneAppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            JarvisModernSectionHeader(
                "Now",
                eyebrow: "Context",
                subtitle: "The assistant stays available without taking over the whole app."
            )

            JarvisModernCard(secondary: true, padding: 16) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top, spacing: 12) {
                        JarvisModernIconBadge(systemName: currentStateIcon, tint: currentStateTint)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(currentStateTitle)
                                .font(.system(.subheadline, design: .rounded, weight: .bold))
                                .foregroundStyle(JarvisModernTheme.textPrimary)
                            Text(currentStateSubtitle)
                                .font(.system(.footnote, design: .rounded, weight: .medium))
                                .foregroundStyle(JarvisModernTheme.textSecondary)
                        }
                        Spacer()
                    }
                }
            }
        }
    }

    private var currentStateTitle: String {
        switch appModel.assistantExperienceState {
        case .listening:
            return "Listening for your next command"
        case .thinking, .processing, .grounding, .responding:
            return "Working without blocking the app"
        case .answerReady:
            return "Latest result is ready"
        case .error:
            return "Attention is needed"
        default:
            return "Assistant is ready"
        }
    }

    private var currentStateSubtitle: String {
        switch appModel.assistantExperienceState {
        case .thinking, .processing, .grounding, .responding:
            return appModel.statusText
        case .answerReady:
            return "Open Chat to continue or refine the response."
        case .error(let message):
            return message
        case .unavailable(let reason):
            return reason
        default:
            return "Home stays calm while JARVIS remains one tap away."
        }
    }

    private var currentStateIcon: String {
        switch appModel.assistantExperienceState {
        case .listening:
            return "waveform.circle.fill"
        case .thinking, .processing, .grounding, .responding:
            return "sparkles.rectangle.stack.fill"
        case .answerReady:
            return "checkmark.circle.fill"
        case .error, .unavailable:
            return "exclamationmark.triangle.fill"
        default:
            return "sparkles"
        }
    }

    private var currentStateTint: Color {
        switch appModel.assistantExperienceState {
        case .listening:
            return .cyan
        case .thinking, .processing, .grounding, .responding:
            return JarvisModernTheme.accent
        case .answerReady:
            return JarvisModernTheme.success
        case .error, .unavailable:
            return JarvisModernTheme.warning
        default:
            return JarvisModernTheme.accentSoft
        }
    }
}

struct ModernRecentConversationsSection: View {
    @EnvironmentObject private var appModel: JarvisPhoneAppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            JarvisModernSectionHeader(
                "Continue",
                eyebrow: "Recent",
                subtitle: "Jump back into the last conversation or keep the thread moving.",
                trailing: !appModel.conversations.isEmpty
                    ? AnyView(
                        NavigationLink("See All") {
                            ModernConversationsListView()
                        }
                        .font(.system(.footnote, design: .rounded, weight: .semibold))
                        .foregroundStyle(JarvisModernTheme.accentSoft)
                    )
                    : nil
            )

            if let latest = appModel.conversations.first {
                Button {
                    appModel.openConversation(latest, source: "home.recent")
                } label: {
                    JarvisModernCard(secondary: true, padding: 16) {
                        HStack {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(latest.title)
                                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                                    .foregroundStyle(JarvisModernTheme.textPrimary)
                                    .lineLimit(1)
                                Text(latest.updatedAt, style: .relative)
                                    .font(.system(.caption, design: .rounded, weight: .medium))
                                    .foregroundStyle(JarvisModernTheme.textSecondary)
                            }
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(JarvisModernTheme.textSecondary)
                        }
                    }
                }
                .buttonStyle(.plain)
            } else {
                Text("No conversations yet")
                    .font(.system(.subheadline, design: .rounded, weight: .medium))
                    .foregroundStyle(JarvisModernTheme.textSecondary)
                    .padding(.vertical, 8)
            }
        }
    }
}

struct ModernModelStatusSection: View {
    @EnvironmentObject private var appModel: JarvisPhoneAppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            JarvisModernSectionHeader(
                "Model Library",
                eyebrow: "Runtime",
                subtitle: "Keep the active local model visible and reachable from the home surface.",
                trailing: AnyView(
                    Button("Manage") {
                        appModel.presentModelLibrary()
                    }
                    .buttonStyle(JarvisModernSecondaryButtonStyle())
                )
            )

            JarvisModernCard(secondary: true, padding: 16) {
                HStack(alignment: .top, spacing: 12) {
                    JarvisModernIconBadge(systemName: "cpu", tint: JarvisModernTheme.accentSoft)

                    VStack(alignment: .leading, spacing: 6) {
                        if let model = appModel.activeModel {
                            Text(model.displayName)
                                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                                .foregroundStyle(JarvisModernTheme.textPrimary)
                            Text("\(model.format.displayName) • \(model.importState.displayName) • \(model.activationEligibility.displayName)")
                                .font(.system(.caption, design: .rounded, weight: .medium))
                                .foregroundStyle(JarvisModernTheme.textSecondary)
                        } else {
                            Text("No active model")
                                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                                .foregroundStyle(JarvisModernTheme.textPrimary)
                            Text("Import and activate a GGUF model to unlock local assistant mode.")
                                .font(.system(.caption, design: .rounded, weight: .medium))
                                .foregroundStyle(JarvisModernTheme.textSecondary)
                        }
                    }

                    Spacer()
                }
            }
        }
    }
}

struct ModernConversationsListView: View {
    @EnvironmentObject private var appModel: JarvisPhoneAppModel

    var body: some View {
        List(appModel.conversations) { conversation in
            Button {
                appModel.openConversation(conversation, source: "conversations.list")
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(conversation.title)
                        .font(.subheadline.weight(.medium))
                    Text(conversation.updatedAt, style: .date)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Conversations")
        .scrollContentBackground(.hidden)
        .background(JarvisModernBackground())
    }
}

private struct JarvisFloatingAssistantHost: View {
    @EnvironmentObject private var appModel: JarvisPhoneAppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    var body: some View {
        Button {
            appModel.apply(
                route: JarvisLaunchRoute.assistant(
                    .assistant,
                    source: .inApp,
                    shouldFocusComposer: true
                )
            )
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(JarvisModernTheme.glowPrimary)
                        .frame(width: pulse ? 76 : 64, height: pulse ? 76 : 64)
                        .blur(radius: 10)
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [JarvisModernTheme.accent, JarvisModernTheme.accentSoft],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: JarvisModernTheme.assistantAnchorSize, height: JarvisModernTheme.assistantAnchorSize)
                        .overlay(
                            Image(systemName: appModel.assistantExperienceState == .listening ? "waveform" : "sparkles")
                                .font(.system(size: 19, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.95))
                        )
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(anchorTitle)
                        .font(.system(.footnote, design: .rounded, weight: .bold))
                        .foregroundStyle(JarvisModernTheme.textPrimary)
                    Text(anchorSubtitle)
                        .font(.system(.caption2, design: .rounded, weight: .medium))
                        .foregroundStyle(JarvisModernTheme.textSecondary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
            .background(
                Capsule(style: .continuous)
                    .fill(JarvisModernTheme.cardPrimary.opacity(0.94))
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(JarvisModernTheme.borderStrong, lineWidth: 1)
                    )
                    .shadow(color: JarvisModernTheme.shadow, radius: 20, x: 0, y: 14)
            )
        }
        .buttonStyle(.plain)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(JarvisModernMotion.idle) {
                pulse = true
            }
        }
    }

    private var anchorTitle: String {
        switch appModel.assistantExperienceState {
        case .listening, .transcribing:
            return "JARVIS is listening"
        case .thinking, .processing, .grounding, .responding:
            return "JARVIS is active"
        case .answerReady:
            return "Answer is ready"
        default:
            return "Ask JARVIS"
        }
    }

    private var anchorSubtitle: String {
        switch appModel.assistantExperienceState {
        case .listening, .transcribing:
            return "Tap to return to the live voice surface"
        case .thinking, .processing, .grounding, .responding:
            return appModel.statusText
        case .answerReady:
            return "Continue, refine, or save the result"
        default:
            return "Voice, files, knowledge, and actions in one surface"
        }
    }
}

struct ModernVisualIntelligenceTabView: View {
    @EnvironmentObject private var appModel: JarvisPhoneAppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var stage: VisualStage = .ready
    @State private var selectedSource: VisualSource?
    @State private var simulatedInsight: String = ""
    @State private var analysisTask: Task<Void, Never>?

    private enum VisualStage {
        case ready
        case analyzing
        case result
    }

    private enum VisualSource: String, CaseIterable, Identifiable {
        case camera = "Live Camera"
        case photo = "Photo Library"
        case screenshot = "Screenshot"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .camera: return "camera.viewfinder"
            case .photo: return "photo.on.rectangle"
            case .screenshot: return "rectangle.on.rectangle"
            }
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    visualHero
                    stageTimeline

                    if !isVisualRuntimeReady {
                        unavailableCard
                    } else {
                        sourcePickerCard
                        stageCard
                    }
                }
                .padding(.horizontal, JarvisModernTheme.screenPadding)
                .padding(.top, 18)
                .padding(.bottom, 132)
            }
            .navigationTitle("Voice")
            .background(JarvisModernBackground())
            .toolbarBackground(.hidden, for: .navigationBar)
            .onDisappear {
                analysisTask?.cancel()
                analysisTask = nil
            }
        }
    }

    private var isVisualRuntimeReady: Bool {
        appModel.canRunVisualAssistant
    }

    private var visualHero: some View {
        JarvisModernCard {
            HStack(alignment: .top, spacing: 14) {
                JarvisModernIconBadge(systemName: "waveform.circle.fill", tint: JarvisModernTheme.accentSoft)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Voice And Command")
                        .font(.system(.title3, design: .rounded, weight: .bold))
                        .foregroundStyle(JarvisModernTheme.textPrimary)
                    Text("This route stays focused: listen, confirm, and branch into visual capture only when the task actually needs it.")
                        .font(.system(.footnote, design: .rounded, weight: .medium))
                        .foregroundStyle(JarvisModernTheme.textSecondary)
                }
                Spacer()
            }
        }
    }

    private var stageTimeline: some View {
        HStack(spacing: 8) {
            stageChip("Capture", icon: "camera.aperture", active: stageIndex >= 1)
            timelineConnector(active: stageIndex >= 2)
            stageChip("Analyze", icon: "sparkles", active: stageIndex >= 2)
            timelineConnector(active: stageIndex >= 3)
            stageChip("Result", icon: "text.magnifyingglass", active: stageIndex >= 3)
        }
        .padding(.horizontal, 2)
    }

    private var stageIndex: Int {
        switch stage {
        case .ready:
            return 1
        case .analyzing:
            return 2
        case .result:
            return 3
        }
    }

    private func stageChip(_ title: String, icon: String, active: Bool) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.caption2.weight(.semibold))
            Text(title)
                .font(.caption2.weight(.semibold))
        }
        .foregroundStyle(active ? JarvisModernTheme.textPrimary : JarvisModernTheme.textSecondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(active ? JarvisModernTheme.accent.opacity(0.16) : JarvisModernTheme.cardSecondary, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(active ? JarvisModernTheme.accent.opacity(0.35) : JarvisModernTheme.border, lineWidth: 1)
        )
    }

    private func timelineConnector(active: Bool) -> some View {
        Capsule(style: .continuous)
            .fill(active ? JarvisModernTheme.accent.opacity(0.55) : JarvisModernTheme.textTertiary.opacity(0.2))
            .frame(width: 18, height: 2)
    }

    private var unavailableCard: some View {
        JarvisModernCard(secondary: true) {
            VStack(alignment: .leading, spacing: 10) {
                Label("Visual assistant is in preview", systemImage: "exclamationmark.triangle.fill")
                    .font(.headline)
                    .foregroundStyle(.orange)
                Text(appModel.visualAssistantStatusText)
                    .font(.subheadline)
                    .foregroundStyle(JarvisModernTheme.textSecondary)
            }
        }
    }

    private var sourcePickerCard: some View {
        JarvisModernCard(secondary: true) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Input Source")
                    .font(.headline)

                ForEach(VisualSource.allCases) { source in
                    Button {
                        selectedSource = source
                        runVisualFlow(source: source)
                    } label: {
                        HStack {
                            Label(source.rawValue, systemImage: source.icon)
                            Spacer()
                            if selectedSource == source {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(JarvisModernTheme.accent)
                            }
                        }
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    @ViewBuilder
    private var stageCard: some View {
        switch stage {
        case .ready:
            JarvisModernCard(secondary: true) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Ready")
                        .font(.headline)
                    Text("Choose a source to begin the visual analysis flow.")
                        .font(.subheadline)
                        .foregroundStyle(JarvisModernTheme.textSecondary)
                }
            }

        case .analyzing:
            JarvisModernCard(secondary: true) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Analyzing visual context")
                            .font(.headline)
                    }
                    Text("Preparing assistant-ready understanding from \(selectedSource?.rawValue ?? "input").")
                        .font(.subheadline)
                        .foregroundStyle(JarvisModernTheme.textSecondary)
                }
            }

        case .result:
            JarvisModernCard(secondary: true) {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Visual Summary", systemImage: "text.magnifyingglass")
                        .font(.headline)
                    Text(simulatedInsight)
                        .font(.subheadline)
                        .foregroundStyle(JarvisModernTheme.textSecondary)
                }
            }
            .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .bottom)))
        }
    }

    private func runVisualFlow(source: VisualSource) {
        guard isVisualRuntimeReady else { return }
        analysisTask?.cancel()
        stage = .analyzing
        JarvisHaptics.selection()

        analysisTask = Task {
            try? await Task.sleep(nanoseconds: 1_100_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                simulatedInsight = "\(source.rawValue) captured. Visual shell is ready to hand this context into grounded assistant reasoning once analyzer integration is enabled."
                stage = .result
                JarvisHaptics.success()
            }
        }
    }
}
