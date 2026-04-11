import SwiftUI

struct JarvisPhoneSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appModel: JarvisPhoneAppModel

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [Color.black.opacity(0.96), Color.black.opacity(0.85)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                Form {
                    Section("Model") {
                        Picker("Backend", selection: $appModel.settings.runtimeBackend) {
                            ForEach(JarvisRuntimeBackend.allCases) { backend in
                                Text(backend.displayName).tag(backend)
                            }
                        }

                        LabeledContent("Runtime", value: appModel.runtimeState.title)
                        LabeledContent("Engine", value: appModel.runtimeEngineName)
                        LabeledContent("Inference") {
                            Text(appModel.canRunInference ? "Available" : "Unavailable")
                                .foregroundStyle(appModel.canRunInference ? .green : .orange)
                        }
                        LabeledContent("Active") {
                            Text(appModel.usesRemoteOllamaRuntime ? appModel.remoteRuntimeDisplayName : (appModel.activeModel?.displayName ?? "None"))
                                .foregroundStyle((appModel.usesRemoteOllamaRuntime || appModel.activeModel != nil) ? Color.primary : Color.orange)
                        }
                        if appModel.usesRemoteOllamaRuntime {
                            LabeledContent("Server") {
                                Text(appModel.ollamaConfiguration.baseURLString.isEmpty ? "Not Configured" : appModel.ollamaConfiguration.baseURLString)
                                    .foregroundStyle(appModel.ollamaConfiguration.baseURLString.isEmpty ? .orange : .primary)
                            }
                            Text("Ollama runs on your Mac, server, or LAN device. Jarvis connects over HTTP(S); this is not on-device inference.")
                                .font(.footnote)
                        } else if let activeModel = appModel.activeModel {
                            LabeledContent("Import State", value: activeModel.importState.displayName)
                            LabeledContent("Activation", value: activeModel.activationEligibility.displayName)
                        }
                        LabeledContent("Supported") {
                            Text(appModel.usesRemoteOllamaRuntime ? "Remote Ollama chat backend" : appModel.supportedModelFormatText)
                        }

                        if !appModel.canRunInference {
                            Text(appModel.runtimeBlockedReason)
                                .font(.footnote)
                                .foregroundStyle(.orange)
                        }

                        if appModel.usesRemoteOllamaRuntime {
                            TextField("Ollama Server URL", text: $appModel.settings.ollama.baseURLString)
                                .textInputAutocapitalization(.never)
                                .disableAutocorrection(true)
                                .keyboardType(.URL)

                            TextField("Model Name", text: $appModel.settings.ollama.modelName)
                                .textInputAutocapitalization(.never)
                                .disableAutocorrection(true)

                            VStack(alignment: .leading, spacing: 6) {
                                Text("Examples")
                                    .font(.caption.weight(.semibold))
                                Text("http://192.168.1.10:11434")
                                    .font(.caption.monospaced())
                                Text("qwen2.5:3b-instruct or llama3.2:3b")
                                    .font(.caption.monospaced())
                            }
                            .foregroundStyle(.secondary)
                        } else {
                            Button("Import Model from Files") {
                                appModel.beginModelImport()
                            }

                            Button("Open Model Library") {
                                appModel.presentModelLibrary()
                            }
                        }

                        Button("Warm Active Model") {
                            appModel.warmModel()
                        }
                        .disabled(appModel.needsModelSetup || !appModel.canRunInference)
                    }

                    Section("Quick Launch") {
                        Text("Jarvis actions are available in Shortcuts and can be assigned to the Action button on supported iPhones.")
                            .font(.footnote)
                        Text("Recommended: assign Ask Jarvis for fastest entry.")
                            .font(.footnote)
                    }

                    Section("Behavior") {
                        Text("If no ready model is active, Jarvis routes to setup/import instead of a broken assistant screen.")
                            .font(.footnote)
                        Text(appModel.usesRemoteOllamaRuntime
                             ? "Remote mode sends prompts to your configured Ollama server. Jarvis does not silently fall back between local and remote backends."
                             : "All inference stays local. No hidden network fallback.")
                            .font(.footnote)
                    }

                    Section("Assistant Memory") {
                        Toggle("Enable Long-Term Memory", isOn: $appModel.settings.memoryEnabled)
                        Text("When enabled, Jarvis stores durable local facts like preferences, project context, and recurring goals.")
                            .font(.footnote)

                        Button("Clear Assistant Memory", role: .destructive) {
                            appModel.clearAssistantMemory()
                        }

                        Button("Clear Conversation Summaries", role: .destructive) {
                            appModel.clearConversationSummaries()
                        }
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .sheet(isPresented: $appModel.isModelImporterPresented) {
            JarvisGGUFImportPicker(
                isPresented: $appModel.isModelImporterPresented,
                onCompletion: appModel.handleModelImportResult
            )
        }
    }
}
