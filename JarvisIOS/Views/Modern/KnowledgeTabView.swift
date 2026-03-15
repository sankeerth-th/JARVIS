import SwiftUI

/// Modern knowledge base/search tab
struct KnowledgeTabView: View {
    @EnvironmentObject private var appModel: JarvisPhoneAppModel
    
    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(filteredResults) { result in
                        KnowledgeRow(result: result)
                    }
                } header: {
                    Text("Saved Knowledge")
                } footer: {
                    if appModel.knowledgeItems.isEmpty {
                        Text("Save useful responses from conversations to build your knowledge base.")
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Knowledge")
            .searchable(text: $appModel.knowledgeQuery, prompt: "Search saved knowledge...")
            .onChange(of: appModel.knowledgeQuery) { _, _ in
                appModel.refreshKnowledgeResults()
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    EditButton()
                }
            }
            .overlay {
                if appModel.knowledgeItems.isEmpty {
                    ContentUnavailableView {
                        Label("No Knowledge Yet", systemImage: "books.vertical")
                    } description: {
                        Text("Save helpful responses from conversations to build your personal knowledge base.")
                    }
                }
            }
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
        VStack(alignment: .leading, spacing: 4) {
            Text(result.title)
                .font(.subheadline.weight(.medium))
            Text(result.text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Text(result.createdAt, style: .date)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Settings Tab

struct SettingsTabView: View {
    @EnvironmentObject private var appModel: JarvisPhoneAppModel
    
    var body: some View {
        NavigationStack {
            List {
                Section("Model") {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(appModel.supportedModelDisplayName)
                            .font(.subheadline.weight(.semibold))
                        Text(appModel.supportedModelShortDescription)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("\(appModel.supportedModelClassificationText) • \(appModel.supportedModelCapabilitySummary)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    NavigationLink {
                        JarvisModernModelLibraryView()
                    } label: {
                        HStack {
                            Image(systemName: "cpu")
                                .foregroundStyle(.indigo)
                            VStack(alignment: .leading, spacing: 2) {
                                if let model = appModel.activeModel {
                                    Text(model.displayName)
                                        .font(.subheadline.weight(.medium))
                                    Text(appModel.activeModelSupportStatusText)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                } else {
                                    Text("No Model")
                                        .font(.subheadline)
                                    Text("Import and activate a local GGUF model")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }

                    Picker("Recommended Profile", selection: $appModel.settings.preferredModelProfile) {
                        ForEach(JarvisSupportedModelProfileID.allCases) { profileID in
                            Text(JarvisSupportedModelCatalog.profile(for: profileID)?.displayName ?? profileID.rawValue)
                                .tag(profileID)
                        }
                    }
                    
                    Button {
                        appModel.presentModelLibrary(beginImport: true)
                    } label: {
                        Label("Import GGUF Model", systemImage: "square.and.arrow.down")
                    }

                    Toggle("Auto-warm On First Send", isOn: $appModel.settings.autoWarmOnFirstSend)
                    Toggle("Warm Active Model On Launch", isOn: $appModel.settings.autoWarmOnLaunch)
                }
                
                Section("Runtime Profile") {
                    HStack {
                        Label("Status", systemImage: "checkmark.circle")
                        Spacer()
                        Text(appModel.runtimeState.title)
                            .foregroundStyle(.secondary)
                    }
                    
                    HStack {
                        Label("Engine", systemImage: "gearshape.2")
                        Spacer()
                        Text(appModel.runtimeEngineName)
                            .foregroundStyle(.secondary)
                    }

                    Picker("Performance", selection: $appModel.settings.performanceProfile) {
                        ForEach(JarvisRuntimePerformanceProfile.allCases) { profile in
                            Text(profile.displayName).tag(profile)
                        }
                    }

                    Picker("Context Window", selection: $appModel.settings.contextWindow) {
                        ForEach(JarvisContextWindowPreset.allCases) { preset in
                            Text("\(preset.displayName) (\(preset.tokenEstimateLabel))").tag(preset)
                        }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Creativity")
                            Spacer()
                            Text(appModel.settings.creativity, format: .number.precision(.fractionLength(2)))
                                .foregroundStyle(.secondary)
                        }
                        Slider(value: $appModel.settings.creativity, in: 0.0...1.2, step: 0.05)
                    }

                    if appModel.hasReadyModel {
                        Button {
                            appModel.warmModel()
                        } label: {
                            Label("Warm Up Model", systemImage: "flame")
                        }

                        Button {
                            appModel.unloadActiveModel()
                        } label: {
                            Label("Unload Model", systemImage: "eject")
                        }
                    }

                    if case .failed = appModel.runtimeState {
                        Button {
                            appModel.retryRuntimeWarmup()
                        } label: {
                            Label("Retry Runtime", systemImage: "arrow.clockwise")
                        }
                    }
                }

                Section("Assistant") {
                    Picker("Startup Destination", selection: $appModel.settings.startupRoute) {
                        ForEach(JarvisStartupRoute.allCases) { route in
                            Text(route.displayName).tag(route)
                        }
                    }

                    LabeledContent("Recommended Profile", value: appModel.supportedModelDisplayName)

                    Picker("Response Style", selection: $appModel.settings.responseStyle) {
                        ForEach(JarvisAssistantResponseStyle.allCases) { style in
                            Text(style.displayName).tag(style)
                        }
                    }

                    Toggle("Auto-start Voice Entry", isOn: $appModel.settings.autoStartListeningForVoiceEntry)
                    Toggle("Auto-send After Speech Pause", isOn: $appModel.settings.autoSendVoiceAfterPause)

                    TextField("Speech Locale (optional, e.g. en-US)", text: Binding(
                        get: { appModel.settings.speechLocaleIdentifier ?? "" },
                        set: { appModel.settings.speechLocaleIdentifier = $0.isEmpty ? nil : $0 }
                    ))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                }

                Section("Chat & Device") {
                    Toggle("Auto-scroll Conversation", isOn: $appModel.settings.autoScrollConversation)
                    Toggle("Show Runtime Diagnostics", isOn: $appModel.settings.showRuntimeDiagnostics)
                    Toggle("Enable Haptics", isOn: $appModel.settings.hapticsEnabled)
                    Toggle("Unload Model In Background", isOn: $appModel.settings.unloadModelOnBackground)
                    Toggle("Battery Saver Mode", isOn: $appModel.settings.batterySaverMode)
                }

                Section("Diagnostics") {
                    NavigationLink("Runtime Diagnostics") {
                        RuntimeDiagnosticsView()
                    }

                    if !appModel.canRunInference {
                        Text(appModel.runtimeBlockedReason)
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
                }
            }
            .navigationTitle("Settings")
        }
    }
}

// MARK: - Runtime Diagnostics

struct RuntimeDiagnosticsView: View {
    @EnvironmentObject private var appModel: JarvisPhoneAppModel
    
    var body: some View {
        List {
            Section("Engine Status") {
                LabeledContent("Engine", value: appModel.runtimeEngineName)
                LabeledContent("Available", value: appModel.canRunInference ? "Yes" : "No")
                if !appModel.canRunInference {
                    LabeledContent("Reason", value: appModel.runtimeBlockedReason)
                }
            }
            
            Section("Model") {
                if let model = appModel.activeModel {
                    LabeledContent("Name", value: model.displayName)
                    LabeledContent("Format", value: model.format.displayName)
                    LabeledContent("Import", value: model.importState.displayName)
                    LabeledContent("Activation", value: model.activationEligibility.displayName)
                    LabeledContent("Profile", value: appModel.activeModelSupportStatusText)
                    LabeledContent("Family", value: model.inferredFamily ?? "Unknown")
                    LabeledContent("Modality", value: model.modality.displayName)
                    LabeledContent("Visual Readiness", value: appModel.activeModelVisualStatusText)
                    LabeledContent("Projector", value: model.hasProjectorAttached ? "Attached" : "Not attached")
                    LabeledContent("Size", value: ByteCountFormatter.string(fromByteCount: model.fileSizeBytes, countStyle: .file))
                } else {
                    Text("No active model")
                        .foregroundStyle(.secondary)
                }
            }
            
            Section("Runtime State") {
                LabeledContent("State", value: appModel.runtimeState.title)
                LabeledContent("File Access", value: appModel.modelFileAccessState.title)
                Text(appModel.modelFileAccessDetail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let diagnostics = appModel.runtimeLoadDiagnostics {
                Section("Load Path") {
                    LabeledContent("Model", value: diagnostics.modelName)
                    LabeledContent("Sandbox Copy", value: diagnostics.usesSandboxCopy ? "Yes" : "No")
                    LabeledContent("Exists", value: diagnostics.fileExists ? "Yes" : "No")
                    LabeledContent("Extension", value: diagnostics.pathExtension.uppercased())
                    LabeledContent("Size", value: ByteCountFormatter.string(fromByteCount: diagnostics.fileSizeBytes, countStyle: .file))
                    Text(diagnostics.modelPath)
                        .font(.caption2.monospaced())
                        .textSelection(.enabled)
                    if let projectorPath = diagnostics.projectorPath {
                        Text(projectorPath)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
            }

            Section("Configured Behavior") {
                LabeledContent("Startup", value: appModel.settings.startupRoute.displayName)
                LabeledContent("Recommended Profile", value: appModel.supportedModelDisplayName)
                LabeledContent("Performance", value: appModel.settings.performanceProfile.displayName)
                LabeledContent("Context", value: appModel.settings.contextWindow.displayName)
                LabeledContent("Response Style", value: appModel.settings.responseStyle.displayName)
                LabeledContent("Creativity", value: appModel.settings.creativity.formatted(.number.precision(.fractionLength(2))))
                LabeledContent("Auto-Warm On First Send", value: appModel.settings.autoWarmOnFirstSend ? "On" : "Off")
            }
            
            Section("Availability") {
                Text(JarvisGGUFEngineFactory.availabilityDiagnostics())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Diagnostics")
    }
}
