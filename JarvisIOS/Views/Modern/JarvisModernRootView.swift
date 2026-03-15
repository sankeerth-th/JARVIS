import SwiftUI

struct JarvisModernRootView: View {
    @EnvironmentObject private var appModel: JarvisPhoneAppModel

    var body: some View {
        TabView(selection: Binding(
            get: { appModel.selectedTab },
            set: { appModel.handleTabSelection($0) }
        )) {
            ModernHomeTabView()
                .tabItem {
                    Label(JarvisAppTab.home.title, systemImage: JarvisAppTab.home.icon)
                }
                .tag(JarvisAppTab.home)

            AssistantTabView()
                .tabItem {
                    Label(JarvisAppTab.assistant.title, systemImage: JarvisAppTab.assistant.icon)
                }
                .tag(JarvisAppTab.assistant)

            ModernVisualIntelligenceTabView()
                .tabItem {
                    Label(JarvisAppTab.visual.title, systemImage: JarvisAppTab.visual.icon)
                }
                .tag(JarvisAppTab.visual)

            KnowledgeTabView()
                .tabItem {
                    Label(JarvisAppTab.knowledge.title, systemImage: JarvisAppTab.knowledge.icon)
                }
                .tag(JarvisAppTab.knowledge)

            SettingsTabView()
                .tabItem {
                    Label(JarvisAppTab.settings.title, systemImage: JarvisAppTab.settings.icon)
                }
                .tag(JarvisAppTab.settings)
        }
        .tint(.indigo)
        .onChange(of: appModel.isAssistantPresented) { _, isPresented in
            guard isPresented else { return }
            appModel.isAssistantPresented = false
            appModel.apply(route: .assistant(.assistant, source: .legacy, shouldFocusComposer: true))
        }
        .onChange(of: appModel.isKnowledgePresented) { _, isPresented in
            guard isPresented else { return }
            appModel.isKnowledgePresented = false
            appModel.apply(route: .assistant(.knowledge, source: .legacy))
        }
        .onChange(of: appModel.isSettingsPresented) { _, isPresented in
            guard isPresented else { return }
            appModel.isSettingsPresented = false
            appModel.apply(route: JarvisLaunchRoute(action: .settings, source: "legacy.sheet.settings"))
        }
        .onChange(of: appModel.isVisualIntelligencePresented) { _, isPresented in
            guard isPresented else { return }
            appModel.isVisualIntelligencePresented = false
            appModel.apply(route: .assistant(.visual, source: .legacy))
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
}

struct ModernHomeTabView: View {
    @EnvironmentObject private var appModel: JarvisPhoneAppModel

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    ModernHomeStatusCard()
                    ModernQuickActionsSection()
                    ModernRecentConversationsSection()
                    ModernModelStatusSection()
                }
                .padding()
            }
            .navigationTitle("Jarvis")
            .background(Color(.systemGroupedBackground))
        }
    }
}

struct ModernHomeStatusCard: View {
    @EnvironmentObject private var appModel: JarvisPhoneAppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: statusIcon)
                    .font(.title2)
                    .foregroundStyle(statusColor)

                VStack(alignment: .leading, spacing: 2) {
                    Text(statusTitle)
                        .font(.headline)
                    Text(statusSubtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            actionRow
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    @ViewBuilder
    private var actionRow: some View {
        if appModel.needsModelSetup {
            Button {
                appModel.showSetupFlow = true
            } label: {
                Label(appModel.hasReadyModel ? "Choose Model" : "Set Up Model", systemImage: "arrow.right.circle.fill")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.borderedProminent)
            .tint(.indigo)
        } else {
            HStack(spacing: 10) {
                if canWarm {
                    Button {
                        appModel.warmModel()
                    } label: {
                        Label("Warm", systemImage: "flame.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.indigo)
                }

                Button {
                    appModel.apply(route: .assistant(.voice, task: .chat, source: .inApp, shouldStartListening: true))
                } label: {
                    Label("Voice", systemImage: "waveform")
                }
                .buttonStyle(.bordered)

                Button {
                    appModel.apply(route: .assistant(.visual, task: .visualDescribe, source: .inApp))
                } label: {
                    Label("Visual", systemImage: "viewfinder")
                }
                .buttonStyle(.bordered)

                if case .failed = appModel.runtimeState {
                    Button {
                        appModel.retryRuntimeWarmup()
                    } label: {
                        Label("Retry", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                }
            }
            .font(.subheadline.weight(.semibold))
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

    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quick Actions")
                .font(.headline)

            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(appModel.quickLaunchItems.prefix(6)) { item in
                    ModernQuickActionButton(item: item)
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
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: item.icon)
                    .font(.title3)
                    .foregroundStyle(.indigo)
                Text(item.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(item.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}

struct ModernRecentConversationsSection: View {
    @EnvironmentObject private var appModel: JarvisPhoneAppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Recent")
                    .font(.headline)
                Spacer()
                if !appModel.conversations.isEmpty {
                    NavigationLink("See All") {
                        ModernConversationsListView()
                    }
                    .font(.subheadline)
                }
            }

            if let latest = appModel.conversations.first {
                Button {
                    appModel.openConversation(latest, source: "home.recent")
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(latest.title)
                                .font(.subheadline.weight(.medium))
                                .lineLimit(1)
                            Text(latest.updatedAt, style: .relative)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
            } else {
                Text("No conversations yet")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            }
        }
    }
}

struct ModernModelStatusSection: View {
    @EnvironmentObject private var appModel: JarvisPhoneAppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Model Library")
                    .font(.headline)
                Spacer()
                Button("Manage") {
                    appModel.presentModelLibrary()
                }
                .font(.subheadline)
            }

            HStack {
                Image(systemName: "cpu")
                    .font(.title3)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 2) {
                    if let model = appModel.activeModel {
                        Text(model.displayName)
                            .font(.subheadline.weight(.medium))
                        Text("\(model.format.displayName) • \(model.importState.displayName) • \(model.activationEligibility.displayName)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("No model imported")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Button {
                    appModel.presentModelLibrary(beginImport: true)
                } label: {
                    Image(systemName: "plus")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.bordered)
            }
            .padding()
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
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
                .padding()
            }
            .navigationTitle("Visual")
            .background(Color(.systemGroupedBackground))
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
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Visual Intelligence")
                        .font(.title2.weight(.semibold))
                    Text("Capture, inspect, and ask follow-up questions on visual inputs. This route is intentionally exposed now, but Jarvis only claims full visual support when the active local runtime can actually execute it.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "viewfinder.circle.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(.indigo)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
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
        .foregroundStyle(active ? .primary : .secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(active ? Color.indigo.opacity(0.16) : Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(active ? Color.indigo.opacity(0.35) : Color.secondary.opacity(0.15), lineWidth: 1)
        )
    }

    private func timelineConnector(active: Bool) -> some View {
        Capsule(style: .continuous)
            .fill(active ? Color.indigo.opacity(0.55) : Color.secondary.opacity(0.2))
            .frame(width: 18, height: 2)
    }

    private var unavailableCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Visual assistant is in preview", systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(.orange)
            Text(appModel.visualAssistantStatusText)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                if appModel.needsModelSetup {
                    Button("Set Up Model") {
                        appModel.showSetupFlow = true
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.indigo)
                } else {
                    Button("Warm Model") {
                        appModel.retryRuntimeWarmup()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.indigo)
                }

                Button("Model Library") {
                    appModel.presentModelLibrary()
                }
                .buttonStyle(.bordered)
            }
            .font(.subheadline.weight(.semibold))
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var sourcePickerCard: some View {
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
                                .foregroundStyle(.indigo)
                        }
                    }
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.bordered)
            }

            Text("This is a production shell preview. It does not claim private system visual powers.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    @ViewBuilder
    private var stageCard: some View {
        switch stage {
        case .ready:
            VStack(alignment: .leading, spacing: 10) {
                Text("Ready")
                    .font(.headline)
                Text("Choose a source to begin visual analysis flow.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16))

        case .analyzing:
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Analyzing visual context")
                        .font(.headline)
                }
                Text("Preparing assistant-ready understanding from \(selectedSource?.rawValue ?? "input").")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16))

        case .result:
            VStack(alignment: .leading, spacing: 12) {
                Label("Visual Summary", systemImage: "text.magnifyingglass")
                    .font(.headline)
                Text(simulatedInsight)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    Button("Ask Follow-up") {
                        let source = selectedSource?.rawValue.lowercased() ?? "visual input"
                        appModel.apply(
                            route: JarvisLaunchRoute(
                                action: .chat,
                                payload: "Based on this \(source), what should I do next?",
                                source: JarvisAssistantEntrySource.inApp.rawValue,
                                assistantTask: .analyzeText,
                                shouldFocusComposer: true
                            )
                        )
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.indigo)

                    Button("Search Knowledge") {
                        let payload = selectedSource?.rawValue ?? "visual analysis"
                        appModel.apply(route: JarvisLaunchRoute(action: .knowledge, query: payload, source: JarvisAssistantEntrySource.inApp.rawValue, assistantTask: .knowledgeAnswer))
                    }
                    .buttonStyle(.bordered)
                }
                .font(.subheadline.weight(.semibold))
            }
            .padding()
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16))
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
