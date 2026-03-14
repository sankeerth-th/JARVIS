import SwiftUI
import UniformTypeIdentifiers

/// Modern model library view with improved UX
struct JarvisModernModelLibraryView: View {
    @EnvironmentObject private var appModel: JarvisPhoneAppModel
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        List {
            Section {
                SupportedProfileCard()
            } header: {
                Text("Recommended on iPhone")
            } footer: {
                Text("Jarvis now imports bookmark-backed GGUF files generally. The curated profile below is the recommended Gemma path for serious on-device use.")
            }

            Section {
                ForEach(appModel.models) { model in
                    ModelRow(model: model)
                }
                .onDelete { indexSet in
                    for index in indexSet {
                        let model = appModel.models[index]
                        appModel.removeModel(id: model.id)
                    }
                }
            } header: {
                Text("Imported Models")
            } footer: {
                Text("Import, activation, and warmup are separate. Activate a model explicitly, then warm it before the first heavy session or let Jarvis auto-warm on first send.")
            }
            
            Section {
                Button {
                    appModel.beginModelImport()
                } label: {
                    Label("Import GGUF Model", systemImage: "plus.circle.fill")
                        .font(.subheadline.weight(.semibold))
                }
                .tint(.indigo)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Model Library")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Done") {
                    dismiss()
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                EditButton()
            }
        }
        .overlay {
            if appModel.models.isEmpty {
                ContentUnavailableView {
                    Label("No Models", systemImage: "cpu")
                } description: {
                    Text("Import a GGUF model to get started. \(appModel.supportedModelDisplayName) is the recommended iPhone target.")
                } actions: {
                    Button("Import GGUF Model") {
                        appModel.beginModelImport()
                    }
                }
            }
        }
        .onAppear {
            if appModel.consumePendingModelLibraryImport() {
                appModel.beginModelImport()
            }
        }
        .fileImporter(
            isPresented: $appModel.isModelImporterPresented,
            allowedContentTypes: [UTType(filenameExtension: "gguf") ?? .data],
            allowsMultipleSelection: false,
            onCompletion: appModel.handleModelImportResult
        )
    }
}

struct ModelRow: View {
    @EnvironmentObject private var appModel: JarvisPhoneAppModel
    let model: JarvisImportedModel
    
    private var isActive: Bool {
        appModel.activeModelID == model.id
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // Status indicator
            Image(systemName: statusIcon)
                .font(.title3)
                .foregroundStyle(statusColor)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(model.displayName)
                    .font(.subheadline.weight(.semibold))
                
                HStack(spacing: 8) {
                    Text(model.format.displayName)
                    Text("•")
                    Text(ByteCountFormatter.string(fromByteCount: model.fileSizeBytes, countStyle: .file))
                    if let family = model.inferredFamily {
                        Text("•")
                        Text(family)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                if let profile = JarvisSupportedModelCatalog.profile(for: model.supportedProfileID) {
                    Text("Curated profile: \(profile.displayName)")
                        .font(.caption)
                        .foregroundStyle(.green)
                }

                Text("Access: \(model.primaryAsset.lastFileAccessStatus.displayName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if model.capabilities.supportsVisionInputs {
                    Text(model.visualReadinessDescription)
                        .font(.caption)
                        .foregroundStyle(model.hasProjectorAttached ? .teal : .orange)
                }
                
                if let message = model.statusMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            
            Spacer()
            
            // Active indicator
            if isActive {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
        }
        .padding(.vertical, 4)
        .swipeActions(edge: .trailing) {
            if model.status == .ready && !isActive {
                Button {
                    appModel.setActiveModel(id: model.id)
                } label: {
                    Label("Activate", systemImage: "checkmark")
                }
                .tint(.indigo)
            }
            
            Button(role: .destructive) {
                appModel.removeModel(id: model.id)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .swipeActions(edge: .leading) {
            Button {
                appModel.revalidateModel(id: model.id)
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .tint(.blue)

            if model.capabilities.supportsVisionInputs && !model.hasProjectorAttached {
                Button {
                    appModel.beginProjectorImport(for: model.id)
                } label: {
                    Label("Projector", systemImage: "paperclip")
                }
                .tint(.teal)
            }
        }
    }
    
    private var statusIcon: String {
        switch model.status {
        case .ready: return isActive ? "cpu.fill" : "cpu"
        case .invalid: return "exclamationmark.triangle"
        case .unsupported: return "xmark.octagon"
        case .missing: return "questionmark.folder"
        case .failed: return "xmark.circle"
        }
    }
    
    private var statusColor: Color {
        switch model.status {
        case .ready: return isActive ? .indigo : .green
        case .invalid, .unsupported: return .orange
        case .missing, .failed: return .red
        }
    }
}

// MARK: - Modern Setup View

struct JarvisModernSetupView: View {
    @EnvironmentObject private var appModel: JarvisPhoneAppModel
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 24) {
                        // Hero
                        VStack(spacing: 16) {
                            Image(systemName: "cpu.fill")
                                .font(.system(size: 64))
                                .foregroundStyle(.indigo)
                            
                            Text("Set Up Local AI")
                                .font(.largeTitle.weight(.bold))
                            
                            Text("Jarvis runs entirely on your device. The recommended foundation path is \(appModel.supportedModelDisplayName), but import, activation, and warmup are all explicit steps.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding(.top, 20)
                        
                        // Import status
                        if case .importing(let progress, let message) = appModel.modelImportState {
                            ImportProgressCard(progress: progress, message: message)
                        } else if case .success(let message) = appModel.modelImportState {
                            StatusCard(message: message, type: .success)
                        } else if case .failure(let message) = appModel.modelImportState {
                            StatusCard(message: message, type: .error)
                        }

                        SupportedProfileCard()
                        
                        // Steps
                        VStack(alignment: .leading, spacing: 16) {
                            Text("How it works")
                                .font(.headline)
                            
                            StepRow(number: 1, title: "Download a GGUF model", description: appModel.supportedModelImportGuidance)
                            StepRow(number: 2, title: "Import and bookmark it", description: "Select the GGUF from Files or iCloud Drive. Jarvis stores a persistent security-scoped bookmark for later access.")
                            StepRow(number: 3, title: "Activate, warm, and chat", description: "Activation is explicit. Warm the model now or let Jarvis auto-warm on the first send.")
                        }
                        .padding()
                        .background(Color(.secondarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        
                        // Simulator warning
                        #if targetEnvironment(simulator)
                        SimulatorWarningCard()
                        #endif
                        
                        // Current models
                        if !appModel.models.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Your Models")
                                    .font(.headline)
                                
                                ForEach(appModel.models) { model in
                                    HStack {
                                        Image(systemName: "cpu")
                                        Text(model.displayName)
                                        Spacer()
                                        VStack(alignment: .trailing, spacing: 2) {
                                            if appModel.activeModelID == model.id {
                                                Text("Active")
                                                    .font(.caption.weight(.semibold))
                                                    .foregroundStyle(.green)
                                            }
                                            Text(model.status.displayName)
                                                .font(.caption)
                                                .foregroundStyle(model.status == .ready ? .green : .orange)
                                        }
                                    }
                                    .padding(.vertical, 4)
                                }
                            }
                            .padding()
                            .background(Color(.secondarySystemGroupedBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                        }
                    }
                    .padding()
                }
                
                // Bottom actions
                VStack(spacing: 12) {
                    Button {
                        appModel.beginModelImport()
                    } label: {
                        Label("Import GGUF Model", systemImage: "square.and.arrow.down")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.indigo)

                    if !appModel.models.isEmpty {
                        Button {
                            appModel.presentModelLibrary()
                        } label: {
                            Label("Open Model Library", systemImage: "tray.full")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                    
                    if !appModel.needsModelSetup {
                        Button("Continue") {
                            dismiss()
                        }
                        .font(.subheadline.weight(.semibold))
                    }
                }
                .padding()
                .background(.ultraThinMaterial)
            }
            .navigationTitle("Setup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !appModel.needsModelSetup {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") {
                            dismiss()
                        }
                    }
                }
            }
        }
        .fileImporter(
            isPresented: $appModel.isModelImporterPresented,
            allowedContentTypes: [UTType(filenameExtension: "gguf") ?? .data],
            allowsMultipleSelection: false,
            onCompletion: appModel.handleModelImportResult
        )
    }
}

private struct SupportedProfileCard: View {
    @EnvironmentObject private var appModel: JarvisPhoneAppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Gold Path", systemImage: "checkmark.seal.fill")
                .font(.caption.weight(.bold))
                .foregroundStyle(.green)

            Text(appModel.supportedModelDisplayName)
                .font(.headline)

            Text(appModel.supportedModelShortDescription)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text(appModel.supportedModelImportGuidance)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("Gemma 3 4B remains text-ready first. Attach the projector GGUF later to preserve the multimodal path.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

struct StepRow: View {
    let number: Int
    let title: String
    let description: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(Circle().fill(.indigo))
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct ImportProgressCard: View {
    let progress: Double
    let message: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Importing...", systemImage: "arrow.down.circle")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(Int(progress * 100))%")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            
            ProgressView(value: progress)
                .tint(.indigo)
            
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(Color.indigo.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct StatusCard: View {
    let message: String
    let type: StatusType
    
    enum StatusType {
        case success, error
    }
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: type == .success ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.title3)
                .foregroundStyle(type == .success ? .green : .red)
            
            Text(message)
                .font(.subheadline)
            
            Spacer()
        }
        .padding()
        .background((type == .success ? Color.green : Color.red).opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct SimulatorWarningCard: View {
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title3)
                .foregroundStyle(.orange)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Simulator Detected")
                    .font(.subheadline.weight(.semibold))
                Text("GGUF models require Metal/ANE which is not available in the iOS Simulator. Test on a physical device for actual inference.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
        }
        .padding()
        .background(Color.orange.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
