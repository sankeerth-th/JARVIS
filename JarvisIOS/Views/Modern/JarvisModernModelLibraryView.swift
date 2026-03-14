import SwiftUI
import UniformTypeIdentifiers

/// Modern model library view with improved UX
struct JarvisModernModelLibraryView: View {
    @EnvironmentObject private var appModel: JarvisPhoneAppModel
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        List {
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
                Text("GGUF models run locally on your device. Larger models provide better quality but require more memory.")
            }
            
            Section {
                Button {
                    appModel.beginModelImport()
                } label: {
                    Label("Import Model", systemImage: "plus.circle.fill")
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
                    Text("Import a GGUF model file to get started with local AI.")
                } actions: {
                    Button("Import Model") {
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
                            
                            Text("Jarvis runs entirely on your device. Import a GGUF model file to get started.")
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
                        
                        // Steps
                        VStack(alignment: .leading, spacing: 16) {
                            Text("How it works")
                                .font(.headline)
                            
                            StepRow(number: 1, title: "Download a GGUF model", description: "Find small language models in GGUF format (1-4GB).")
                            StepRow(number: 2, title: "Import to Jarvis", description: "Select the file from Files or iCloud Drive.")
                            StepRow(number: 3, title: "Start chatting", description: "Your model runs locally—no internet required.")
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
                                        Text(model.status.displayName)
                                            .font(.caption)
                                            .foregroundStyle(model.status == .ready ? .green : .orange)
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
                        Label("Import Model", systemImage: "square.and.arrow.down")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.indigo)
                    
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
