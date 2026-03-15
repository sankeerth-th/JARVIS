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
                        LabeledContent("Runtime", value: appModel.runtimeState.title)
                        LabeledContent("Engine", value: appModel.runtimeEngineName)
                        LabeledContent("Inference") {
                            Text(appModel.canRunInference ? "Available" : "Unavailable")
                                .foregroundStyle(appModel.canRunInference ? .green : .orange)
                        }
                        LabeledContent("Active") {
                            Text(appModel.activeModel?.displayName ?? "None")
                                .foregroundStyle(appModel.activeModel == nil ? .orange : .primary)
                        }
                        if let activeModel = appModel.activeModel {
                            LabeledContent("Import State", value: activeModel.importState.displayName)
                            LabeledContent("Activation", value: activeModel.activationEligibility.displayName)
                        }
                        LabeledContent("Supported") {
                            Text(appModel.supportedModelFormatText)
                        }

                        if !appModel.canRunInference {
                            Text(appModel.runtimeBlockedReason)
                                .font(.footnote)
                                .foregroundStyle(.orange)
                        }

                        Button("Import Model from Files") {
                            appModel.beginModelImport()
                        }

                        Button("Open Model Library") {
                            appModel.presentModelLibrary()
                        }

                        Button("Warm Active Model") {
                            appModel.warmModel()
                        }
                        .disabled(!appModel.hasReadyModel || !appModel.canRunInference)
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
                        Text("All inference stays local. No hidden network fallback.")
                            .font(.footnote)
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
