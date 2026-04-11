import SwiftUI

struct JarvisModernModelLibraryView: View {
    @EnvironmentObject private var appModel: JarvisPhoneAppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: JarvisModernTheme.sectionSpacing) {
                JarvisModernSectionHeader(
                    "Model Library",
                    eyebrow: "Local Runtime",
                    subtitle: "Import, activate, and validate local GGUF models without leaving the iPhone shell.",
                    trailing: AnyView(
                        Button("Done") { dismiss() }
                            .buttonStyle(JarvisModernSecondaryButtonStyle())
                    )
                )

                SupportedProfileCard()
                activeModelCard
                importCard

                if appModel.models.isEmpty {
                    emptyLibraryCard
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Imported Models")
                            .font(.system(.headline, design: .rounded, weight: .semibold))
                            .foregroundStyle(JarvisModernTheme.textPrimary)

                        ForEach(appModel.models) { model in
                            ModelRow(model: model)
                        }
                    }
                }
            }
            .padding(.horizontal, JarvisModernTheme.screenPadding)
            .padding(.top, 18)
            .padding(.bottom, 32)
        }
        .background(JarvisModernBackground())
        .navigationTitle("Model Library")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .onAppear {
            if appModel.consumePendingModelLibraryImport() {
                appModel.beginModelImport()
            }
        }
        .sheet(isPresented: $appModel.isModelImporterPresented) {
            JarvisGGUFImportPicker(
                isPresented: $appModel.isModelImporterPresented,
                onCompletion: appModel.handleModelImportResult
            )
        }
    }

    private var activeModelCard: some View {
        JarvisModernCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Active Model")
                    .font(.system(.headline, design: .rounded, weight: .semibold))
                    .foregroundStyle(JarvisModernTheme.textPrimary)

                if let active = appModel.activeModel {
                    JarvisModernInlineStatusRow(
                        icon: "cpu.fill",
                        title: active.displayName,
                        detail: "\(active.format.displayName) • \(active.importState.displayName) • \(active.activationEligibility.displayName)",
                        tint: JarvisModernTheme.accentSoft
                    )
                } else {
                    JarvisModernInlineStatusRow(
                        icon: "tray",
                        title: "No active model",
                        detail: "Import a GGUF model and activate it before starting a heavy local session.",
                        tint: JarvisModernTheme.warning
                    )
                }
            }
        }
    }

    private var importCard: some View {
        JarvisModernCard(secondary: true) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Import and activation")
                    .font(.system(.headline, design: .rounded, weight: .semibold))
                    .foregroundStyle(JarvisModernTheme.textPrimary)
                Text("Import, activation, and warmup are separate. Jarvis copies the file locally, then you activate and warm it explicitly.")
                    .font(.system(.footnote, design: .rounded, weight: .medium))
                    .foregroundStyle(JarvisModernTheme.textSecondary)

                Button {
                    appModel.beginModelImport()
                } label: {
                    Label("Import GGUF Model", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(JarvisModernPrimaryButtonStyle())
            }
        }
    }

    private var emptyLibraryCard: some View {
        JarvisModernCard(secondary: true) {
            VStack(spacing: 14) {
                Image(systemName: "cpu")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(JarvisModernTheme.textPrimary)
                Text("No imported models")
                    .font(.system(.headline, design: .rounded, weight: .bold))
                    .foregroundStyle(JarvisModernTheme.textPrimary)
                Text("Import a GGUF model to get started. Recommended iPhone profiles will guide sizing and performance.")
                    .font(.system(.footnote, design: .rounded, weight: .medium))
                    .foregroundStyle(JarvisModernTheme.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
        }
    }
}

struct ModelRow: View {
    @EnvironmentObject private var appModel: JarvisPhoneAppModel
    let model: JarvisImportedModel

    private var isActive: Bool {
        appModel.activeModelID == model.id
    }

    var body: some View {
        JarvisModernCard(secondary: true, padding: 16) {
            HStack(alignment: .top, spacing: 12) {
                JarvisModernIconBadge(systemName: statusIcon, tint: statusColor)

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(model.displayName)
                            .font(.system(.subheadline, design: .rounded, weight: .semibold))
                            .foregroundStyle(JarvisModernTheme.textPrimary)
                        if isActive {
                            JarvisModernChip(title: "Active", icon: "checkmark", tint: JarvisModernTheme.success, active: true)
                        }
                    }

                    Text("\(model.format.displayName) • \(ByteCountFormatter.string(fromByteCount: model.fileSizeBytes, countStyle: .file))")
                        .font(.system(.caption, design: .rounded, weight: .medium))
                        .foregroundStyle(JarvisModernTheme.textSecondary)

                    Text("Import: \(model.importState.displayName) • Activation: \(model.activationEligibility.displayName)")
                        .font(.system(.caption, design: .rounded, weight: .medium))
                        .foregroundStyle(model.canActivate ? JarvisModernTheme.success : JarvisModernTheme.warning)

                    if let family = model.inferredFamily {
                        Text(family)
                            .font(.system(.caption2, design: .rounded, weight: .semibold))
                            .foregroundStyle(JarvisModernTheme.textTertiary)
                    }

                    if let message = model.statusMessage {
                        Text(message)
                            .font(.system(.caption2, design: .rounded, weight: .medium))
                            .foregroundStyle(JarvisModernTheme.warning)
                    }

                    HStack(spacing: 8) {
                        if model.canActivate && !isActive {
                            Button {
                                appModel.setActiveModel(id: model.id)
                            } label: {
                                Label("Activate", systemImage: "checkmark")
                            }
                            .buttonStyle(JarvisModernSecondaryButtonStyle())
                        }

                        Button {
                            appModel.revalidateModel(id: model.id)
                        } label: {
                            Label("Refresh", systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(JarvisModernSecondaryButtonStyle())

                        Button(role: .destructive) {
                            appModel.removeModel(id: model.id)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        .buttonStyle(JarvisModernSecondaryButtonStyle())
                    }
                }
            }
        }
    }

    private var statusIcon: String {
        switch (model.importState, model.activationEligibility) {
        case (.imported, .eligible):
            return isActive ? "cpu.fill" : "cpu"
        case (.imported, .unsupportedProfile):
            return "tray.full"
        case (.invalid, _):
            return "exclamationmark.triangle"
        case (.missing, _):
            return "questionmark.folder"
        case (.failed, _), (.imported, .accessLost), (.imported, .validationFailed):
            return "xmark.circle"
        }
    }

    private var statusColor: Color {
        switch (model.importState, model.activationEligibility) {
        case (.imported, .eligible):
            return isActive ? JarvisModernTheme.accent : JarvisModernTheme.success
        case (.imported, .unsupportedProfile), (.invalid, _):
            return JarvisModernTheme.warning
        case (.missing, _), (.failed, _), (.imported, .accessLost), (.imported, .validationFailed):
            return JarvisModernTheme.danger
        }
    }
}

struct JarvisModernSetupView: View {
    @EnvironmentObject private var appModel: JarvisPhoneAppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: JarvisModernTheme.sectionSpacing) {
                        hero
                        importStateSurface
                        SupportedProfileCard()
                        setupSteps
                        currentModels
                        #if targetEnvironment(simulator)
                        SimulatorWarningCard()
                        #endif
                    }
                    .padding(.horizontal, JarvisModernTheme.screenPadding)
                    .padding(.top, 18)
                    .padding(.bottom, 24)
                }

                VStack(spacing: 10) {
                    Button {
                        appModel.beginModelImport()
                    } label: {
                        Label("Import GGUF Model", systemImage: "square.and.arrow.down")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(JarvisModernPrimaryButtonStyle())

                    if !appModel.models.isEmpty {
                        Button {
                            appModel.presentModelLibrary()
                        } label: {
                            Label("Open Model Library", systemImage: "tray.full")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(JarvisModernSecondaryButtonStyle())
                    }

                    if !appModel.needsModelSetup {
                        Button("Continue") {
                            dismiss()
                        }
                        .buttonStyle(JarvisModernSecondaryButtonStyle())
                    }
                }
                .padding(.horizontal, JarvisModernTheme.screenPadding)
                .padding(.top, 10)
                .padding(.bottom, 18)
                .background(Color.black.opacity(0.14))
            }
            .background(JarvisModernBackground())
            .navigationTitle("Setup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                if !appModel.needsModelSetup {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { dismiss() }
                    }
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

    private var hero: some View {
        JarvisModernCard {
            HStack(spacing: 14) {
                JarvisModernIconBadge(systemName: "cpu.fill", tint: JarvisModernTheme.accent)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Set up local AI")
                        .font(.system(.title3, design: .rounded, weight: .bold))
                        .foregroundStyle(JarvisModernTheme.textPrimary)
                    Text("Jarvis runs fully on-device. Import one GGUF model from Files, then activate and warm it explicitly.")
                        .font(.system(.footnote, design: .rounded, weight: .medium))
                        .foregroundStyle(JarvisModernTheme.textSecondary)
                }
            }
        }
    }

    @ViewBuilder
    private var importStateSurface: some View {
        switch appModel.modelImportState {
        case .idle:
            EmptyView()
        case .importing(let progress, let message):
            ImportProgressCard(progress: progress, message: message)
        case .success(let message):
            StatusCard(message: message, type: .success)
        case .failure(let message):
            StatusCard(message: message, type: .error)
        }
    }

    private var setupSteps: some View {
        JarvisModernCard(secondary: true) {
            VStack(alignment: .leading, spacing: 14) {
                Text("How it works")
                    .font(.system(.headline, design: .rounded, weight: .semibold))
                    .foregroundStyle(JarvisModernTheme.textPrimary)
                StepRow(number: 1, title: "Choose a GGUF model", description: appModel.supportedModelImportGuidance)
                StepRow(number: 2, title: "Jarvis copies it locally", description: "The selected file is copied into local app storage before activation.")
                StepRow(number: 3, title: "Activate, warm, and chat", description: "Keep import, activation, and warmup explicit so the assistant state is always honest.")
            }
        }
    }

    private var currentModels: some View {
        JarvisModernCard(secondary: true) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Current readiness")
                    .font(.system(.headline, design: .rounded, weight: .semibold))
                    .foregroundStyle(JarvisModernTheme.textPrimary)

                if let active = appModel.activeModel {
                    Text("Active: \(active.displayName)")
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .foregroundStyle(JarvisModernTheme.textPrimary)
                    Text("Imported models: \(appModel.models.count)")
                        .font(.system(.footnote, design: .rounded, weight: .medium))
                        .foregroundStyle(JarvisModernTheme.textSecondary)
                } else {
                    Text("No active model selected")
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .foregroundStyle(JarvisModernTheme.warning)
                    Text("Imported models: \(appModel.models.count)")
                        .font(.system(.footnote, design: .rounded, weight: .medium))
                        .foregroundStyle(JarvisModernTheme.textSecondary)
                }
            }
        }
    }
}

private struct SupportedProfileCard: View {
    @EnvironmentObject private var appModel: JarvisPhoneAppModel

    var body: some View {
        JarvisModernCard(secondary: true) {
            VStack(alignment: .leading, spacing: 10) {
                JarvisModernChip(title: "Recommended on iPhone", icon: "checkmark.seal.fill", tint: JarvisModernTheme.success, active: true)
                Text(appModel.supportedModelDisplayName)
                    .font(.system(.headline, design: .rounded, weight: .semibold))
                    .foregroundStyle(JarvisModernTheme.textPrimary)
                Text(appModel.supportedModelShortDescription)
                    .font(.system(.footnote, design: .rounded, weight: .medium))
                    .foregroundStyle(JarvisModernTheme.textSecondary)
                Text(appModel.supportedModelImportGuidance)
                    .font(.system(.caption, design: .rounded, weight: .medium))
                    .foregroundStyle(JarvisModernTheme.textSecondary)
            }
        }
    }
}

struct StepRow: View {
    let number: Int
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.system(.caption, design: .rounded, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(Circle().fill(JarvisModernTheme.accent))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(JarvisModernTheme.textPrimary)
                Text(description)
                    .font(.system(.caption, design: .rounded, weight: .medium))
                    .foregroundStyle(JarvisModernTheme.textSecondary)
            }
        }
    }
}

struct ImportProgressCard: View {
    let progress: Double
    let message: String

    var body: some View {
        JarvisModernCard(secondary: true) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Importing")
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .foregroundStyle(JarvisModernTheme.textPrimary)
                    Spacer()
                    Text("\(Int(progress * 100))%")
                        .font(.system(.caption, design: .rounded, weight: .bold))
                        .foregroundStyle(JarvisModernTheme.textSecondary)
                }
                ProgressView(value: progress)
                    .tint(JarvisModernTheme.accent)
                Text(message)
                    .font(.system(.caption, design: .rounded, weight: .medium))
                    .foregroundStyle(JarvisModernTheme.textSecondary)
            }
        }
    }
}

struct StatusCard: View {
    let message: String
    let type: StatusType

    enum StatusType {
        case success, error
    }

    var body: some View {
        JarvisModernCard(secondary: true) {
            JarvisModernInlineStatusRow(
                icon: type == .success ? "checkmark.circle.fill" : "xmark.circle.fill",
                title: type == .success ? "Import complete" : "Import failed",
                detail: message,
                tint: type == .success ? JarvisModernTheme.success : JarvisModernTheme.danger
            )
        }
    }
}

struct SimulatorWarningCard: View {
    var body: some View {
        JarvisModernCard(secondary: true) {
            JarvisModernInlineStatusRow(
                icon: "exclamationmark.triangle.fill",
                title: "Simulator detected",
                detail: "GGUF inference needs a physical iPhone for actual Metal and ANE-backed execution.",
                tint: JarvisModernTheme.warning
            )
        }
    }
}
