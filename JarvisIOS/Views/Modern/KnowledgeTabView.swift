import SwiftUI

struct KnowledgeTabView: View {
    @EnvironmentObject private var appModel: JarvisPhoneAppModel

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: JarvisModernTheme.sectionSpacing) {
                    JarvisModernSectionHeader(
                        "Knowledge",
                        eyebrow: "Saved",
                        subtitle: "Search and reuse the answers, notes, and context you have chosen to keep local."
                    )

                    searchCard

                    if filteredResults.isEmpty {
                        emptyStateCard
                    } else {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(filteredResults) { result in
                                KnowledgeRow(result: result)
                            }
                        }
                    }
                }
                .padding(.horizontal, JarvisModernTheme.screenPadding)
                .padding(.top, 18)
                .padding(.bottom, 132)
            }
            .background(JarvisModernBackground())
            .navigationTitle("Knowledge")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if appModel.shouldShowFocusedBackButton {
                        Button {
                            appModel.returnFromFocusedExperience()
                        } label: {
                            Label(appModel.focusedBackButtonTitle, systemImage: "chevron.left")
                        }
                    }
                }
            }
        }
    }

    private var searchCard: some View {
        JarvisModernCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    JarvisModernIconBadge(systemName: "magnifyingglass", tint: JarvisModernTheme.accentSoft)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Search your local knowledge")
                            .font(.system(.subheadline, design: .rounded, weight: .semibold))
                            .foregroundStyle(JarvisModernTheme.textPrimary)
                        Text("Results stay on-device and match titles and saved content.")
                            .font(.system(.footnote, design: .rounded, weight: .medium))
                            .foregroundStyle(JarvisModernTheme.textSecondary)
                    }
                }

                TextField("Search saved knowledge...", text: $appModel.knowledgeQuery)
                    .textInputAutocapitalization(.sentences)
                    .autocorrectionDisabled(false)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color.white.opacity(0.08))
                            .overlay(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .stroke(JarvisModernTheme.border, lineWidth: 1)
                            )
                    )
                    .onChange(of: appModel.knowledgeQuery) { _, _ in
                        appModel.refreshKnowledgeResults()
                    }
            }
        }
    }

    private var emptyStateCard: some View {
        JarvisModernCard(secondary: true) {
            VStack(spacing: 14) {
                Image(systemName: "books.vertical")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(JarvisModernTheme.textPrimary)
                Text("No knowledge yet")
                    .font(.system(.headline, design: .rounded, weight: .bold))
                    .foregroundStyle(JarvisModernTheme.textPrimary)
                Text("Save useful responses from conversations to build a local knowledge base you can search later.")
                    .font(.system(.footnote, design: .rounded, weight: .medium))
                    .foregroundStyle(JarvisModernTheme.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var filteredResults: [JarvisKnowledgeItem] {
        if appModel.knowledgeQuery.isEmpty {
            return appModel.knowledgeItems
        }
        return appModel.knowledgeItems.filter {
            $0.title.localizedCaseInsensitiveContains(appModel.knowledgeQuery) ||
            $0.text.localizedCaseInsensitiveContains(appModel.knowledgeQuery)
        }
    }
}

struct KnowledgeRow: View {
    let result: JarvisKnowledgeItem

    var body: some View {
        JarvisModernCard(secondary: true, padding: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text(result.title)
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(JarvisModernTheme.textPrimary)
                Text(result.text)
                    .font(.system(.footnote, design: .rounded, weight: .medium))
                    .foregroundStyle(JarvisModernTheme.textSecondary)
                    .lineLimit(3)
                Text(result.createdAt, style: .date)
                    .font(.system(.caption2, design: .rounded, weight: .semibold))
                    .foregroundStyle(JarvisModernTheme.textTertiary)
            }
        }
    }
}

struct SettingsTabView: View {
    @EnvironmentObject private var appModel: JarvisPhoneAppModel

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: JarvisModernTheme.sectionSpacing) {
                    JarvisModernSectionHeader(
                        "Settings",
                        eyebrow: "Platform",
                        subtitle: "Tune the assistant, runtime profile, and local-device behavior without leaving the iPhone shell."
                    )

                    overviewCard
                    modelSection
                    runtimeSection
                    assistantSection
                    deviceSection
                }
                .padding(.horizontal, JarvisModernTheme.screenPadding)
                .padding(.top, 18)
                .padding(.bottom, 132)
            }
            .background(JarvisModernBackground())
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
        }
    }

    private var overviewCard: some View {
        JarvisModernCard {
            HStack(alignment: .top, spacing: 14) {
                JarvisModernIconBadge(systemName: "gearshape.fill", tint: JarvisModernTheme.accent)
                VStack(alignment: .leading, spacing: 6) {
                    let activeModelName = appModel.activeModel?.displayName ?? "None"
                    Text(appModel.runtimeState.title)
                        .font(.system(.title3, design: .rounded, weight: .bold))
                        .foregroundStyle(JarvisModernTheme.textPrimary)
                    Text("Engine: \(appModel.runtimeEngineName)\nActive model: \(activeModelName)")
                        .font(.system(.footnote, design: .rounded, weight: .medium))
                        .foregroundStyle(JarvisModernTheme.textSecondary)
                }
                Spacer()
            }
        }
    }

    private var modelSection: some View {
        JarvisModernCard(secondary: true) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Model")
                    .font(.system(.headline, design: .rounded, weight: .semibold))
                    .foregroundStyle(JarvisModernTheme.textPrimary)

                settingRow("Recommended Profile") {
                    Picker("Recommended Profile", selection: $appModel.settings.preferredModelProfile) {
                        ForEach(JarvisSupportedModelProfileID.allCases) { profileID in
                            Text(JarvisSupportedModelCatalog.profile(for: profileID)?.displayName ?? profileID.rawValue)
                                .tag(profileID)
                        }
                    }
                    .pickerStyle(.menu)
                }

                Button {
                    appModel.presentModelLibrary(beginImport: true)
                } label: {
                    Label("Import GGUF Model", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(JarvisModernSecondaryButtonStyle())

                Button {
                    appModel.presentModelLibrary()
                } label: {
                    Label("Open Model Library", systemImage: "cpu")
                }
                .buttonStyle(JarvisModernSecondaryButtonStyle())

                Toggle("Auto-warm On First Send", isOn: $appModel.settings.autoWarmOnFirstSend)
                    .tint(JarvisModernTheme.accent)
            }
        }
    }

    private var runtimeSection: some View {
        JarvisModernCard(secondary: true) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Runtime")
                    .font(.system(.headline, design: .rounded, weight: .semibold))
                    .foregroundStyle(JarvisModernTheme.textPrimary)

                settingRow("Performance") {
                    Picker("Performance", selection: $appModel.settings.performanceProfile) {
                        ForEach(JarvisRuntimePerformanceProfile.allCases) { profile in
                            Text(profile.displayName).tag(profile)
                        }
                    }
                    .pickerStyle(.menu)
                }

                settingRow("Context Window") {
                    Picker("Context Window", selection: $appModel.settings.contextWindow) {
                        ForEach(JarvisContextWindowPreset.allCases) { preset in
                            Text("\(preset.displayName) (\(preset.tokenEstimateLabel))").tag(preset)
                        }
                    }
                    .pickerStyle(.menu)
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Creativity")
                            .foregroundStyle(JarvisModernTheme.textPrimary)
                        Spacer()
                        Text(appModel.settings.creativity, format: .number.precision(.fractionLength(2)))
                            .foregroundStyle(JarvisModernTheme.textSecondary)
                    }
                    Slider(value: $appModel.settings.creativity, in: 0.0...1.2, step: 0.05)
                        .tint(JarvisModernTheme.accent)
                }

                if appModel.hasReadyModel {
                    Button {
                        appModel.warmModel()
                    } label: {
                        Label("Warm Up Model", systemImage: "flame")
                    }
                    .buttonStyle(JarvisModernSecondaryButtonStyle())

                    Button {
                        appModel.unloadActiveModel()
                    } label: {
                        Label("Unload Model", systemImage: "eject")
                    }
                    .buttonStyle(JarvisModernSecondaryButtonStyle())
                }

                if case .failed = appModel.runtimeState {
                    Button {
                        appModel.retryRuntimeWarmup()
                    } label: {
                        Label("Retry Runtime", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(JarvisModernSecondaryButtonStyle())
                }
            }
        }
    }

    private var assistantSection: some View {
        JarvisModernCard(secondary: true) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Assistant Platform")
                    .font(.system(.headline, design: .rounded, weight: .semibold))
                    .foregroundStyle(JarvisModernTheme.textPrimary)

                settingRow("Startup Destination") {
                    Picker("Startup Destination", selection: $appModel.settings.startupRoute) {
                        ForEach(JarvisStartupRoute.allCases) { route in
                            Text(route.displayName).tag(route)
                        }
                    }
                    .pickerStyle(.menu)
                }

                settingRow("Assistant Mode") {
                    Picker("Assistant Mode", selection: $appModel.settings.assistantQualityMode) {
                        ForEach(JarvisAssistantQualityMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .pickerStyle(.menu)
                }

                settingRow("Prompt Mode") {
                    Picker("Prompt Mode", selection: $appModel.settings.promptMode) {
                        ForEach(JarvisAssistantPromptMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .pickerStyle(.menu)
                }

                settingRow("Response Style") {
                    Picker("Response Style", selection: $appModel.settings.responseStyle) {
                        ForEach(JarvisAssistantResponseStyle.allCases) { style in
                            Text(style.displayName).tag(style)
                        }
                    }
                    .pickerStyle(.menu)
                }

                Toggle("Enable Memory", isOn: $appModel.settings.memoryEnabled)
                    .tint(JarvisModernTheme.accent)

                Toggle("Auto-start Voice Entry", isOn: $appModel.settings.autoStartListeningForVoiceEntry)
                    .tint(JarvisModernTheme.accent)

                Toggle("Auto-send After Speech Pause", isOn: $appModel.settings.autoSendVoiceAfterPause)
                    .tint(JarvisModernTheme.accent)

                Button(role: .destructive) {
                    appModel.clearAssistantMemory()
                } label: {
                    Label("Clear Memory", systemImage: "trash")
                }
                .buttonStyle(JarvisModernSecondaryButtonStyle())
            }
        }
    }

    private var deviceSection: some View {
        JarvisModernCard(secondary: true) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Chat & Device")
                    .font(.system(.headline, design: .rounded, weight: .semibold))
                    .foregroundStyle(JarvisModernTheme.textPrimary)

                Toggle("Auto-scroll Conversation", isOn: $appModel.settings.autoScrollConversation)
                    .tint(JarvisModernTheme.accent)
                Toggle("Enable Haptics", isOn: $appModel.settings.hapticsEnabled)
                    .tint(JarvisModernTheme.accent)
                Toggle("Unload Model In Background", isOn: $appModel.settings.unloadModelOnBackground)
                    .tint(JarvisModernTheme.accent)
                Toggle("Battery Saver Mode", isOn: $appModel.settings.batterySaverMode)
                    .tint(JarvisModernTheme.accent)
                Toggle("Enable Diagnostics", isOn: $appModel.settings.showRuntimeDiagnostics)
                    .tint(JarvisModernTheme.accent)

                Button {
                    appModel.resetAssistantState()
                } label: {
                    Label("Reset Assistant State", systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(JarvisModernSecondaryButtonStyle())
            }
        }
    }

    private func settingRow<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .center) {
            Text(title)
                .font(.system(.footnote, design: .rounded, weight: .semibold))
                .foregroundStyle(JarvisModernTheme.textPrimary)
            Spacer()
            content()
                .foregroundStyle(JarvisModernTheme.textSecondary)
        }
    }
}
