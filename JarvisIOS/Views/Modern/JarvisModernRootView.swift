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
            appModel.apply(route: JarvisLaunchRoute(action: .ask, source: "legacy.sheet.assistant"))
        }
        .onChange(of: appModel.isKnowledgePresented) { _, isPresented in
            guard isPresented else { return }
            appModel.isKnowledgePresented = false
            appModel.apply(route: JarvisLaunchRoute(action: .search, source: "legacy.sheet.knowledge"))
        }
        .onChange(of: appModel.isSettingsPresented) { _, isPresented in
            guard isPresented else { return }
            appModel.isSettingsPresented = false
            appModel.apply(route: JarvisLaunchRoute(action: .settings, source: "legacy.sheet.settings"))
        }
        .onChange(of: appModel.isVisualIntelligencePresented) { _, isPresented in
            guard isPresented else { return }
            appModel.isVisualIntelligencePresented = false
            appModel.apply(route: JarvisLaunchRoute(action: .visualIntelligence, source: "legacy.sheet.visual"))
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
                    appModel.apply(route: JarvisLaunchRoute(action: .voice, source: "home.status"))
                } label: {
                    Label("Voice", systemImage: "waveform")
                }
                .buttonStyle(.bordered)

                Button {
                    appModel.apply(route: JarvisLaunchRoute(action: .visualIntelligence, source: "home.status"))
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
                : "Import a bookmark-backed GGUF model to unlock assistant mode."
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
        case .failed(_, let message):
            return message
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
                        Text("\(model.format.displayName) • \(model.status.displayName)")
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

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Visual Intelligence")
                            .font(.title2.weight(.semibold))
                        Text("A premium shell for upcoming camera, screenshot, and file-aware assistant workflows. This mode is intentionally real now so future intelligence features land without another navigation rewrite.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 16))

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Available now")
                            .font(.headline)
                        Button {
                            appModel.apply(route: JarvisLaunchRoute(action: .ask, source: "visual.placeholder"))
                        } label: {
                            Label("Open Assistant", systemImage: "bubble.left")
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.indigo)

                        Button {
                            appModel.apply(route: JarvisLaunchRoute(action: .search, source: "visual.placeholder"))
                        } label: {
                            Label("Search Local Knowledge", systemImage: "magnifyingglass")
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding()
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 16))

                    VStack(alignment: .leading, spacing: 10) {
                        Label("Planned visual actions", systemImage: "sparkles")
                            .font(.headline)
                        Text("1. Capture screen context\n2. Ask visual follow-up\n3. Save insight to knowledge")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                .padding()
            }
            .navigationTitle("Visual")
            .background(Color(.systemGroupedBackground))
        }
    }
}
