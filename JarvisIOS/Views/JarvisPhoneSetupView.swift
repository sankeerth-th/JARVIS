import SwiftUI
import UniformTypeIdentifiers

struct JarvisPhoneSetupView: View {
    @EnvironmentObject private var appModel: JarvisPhoneAppModel

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.03, green: 0.06, blue: 0.12),
                        Color(red: 0.05, green: 0.12, blue: 0.2),
                        Color(red: 0.01, green: 0.03, blue: 0.08)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 16) {
                        hero
                        importStateCard
                        setupSteps
                        librarySummary
                        actions
                    }
                    .padding(16)
                    .padding(.bottom, 20)
                }
            }
            .navigationTitle("Set Up Jarvis")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if !appModel.needsModelSetup {
                        Button("Done") {
                            appModel.dismissSetupFlowIfReady()
                            appModel.showSetupFlow = false
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

    private var hero: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Import a local model")
                .font(.system(.title2, design: .rounded, weight: .bold))
                .foregroundStyle(.white)
            Text("Jarvis runs fully on-device. To start chatting, import one model file from Files.")
                .font(.system(.subheadline, design: .rounded, weight: .medium))
                .foregroundStyle(.white.opacity(0.82))
            HStack(spacing: 8) {
                Image(systemName: "checkmark.shield")
                Text("Supported now: \(appModel.supportedModelFormatText)")
            }
            .font(.system(.footnote, design: .rounded, weight: .semibold))
            .foregroundStyle(.white.opacity(0.9))
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(Color.white.opacity(0.18), lineWidth: 1)
                )
        )
    }

    private var setupSteps: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quick Setup")
                .font(.system(.headline, design: .rounded, weight: .semibold))
                .foregroundStyle(.white)

            setupStep(index: 1, title: "Choose a GGUF model", detail: "Select a .gguf file from iCloud Drive or On My iPhone.")
            setupStep(index: 2, title: "Jarvis validates import", detail: "You’ll see import and validation state before activation.")
            setupStep(index: 3, title: "Start asking immediately", detail: "Jarvis opens into Ask flow once a Ready model is active.")
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color.white.opacity(0.10)))
    }

    @ViewBuilder
    private var importStateCard: some View {
        switch appModel.modelImportState {
        case .idle:
            EmptyView()
        case .importing(let progress, let message):
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("Importing", systemImage: "square.and.arrow.down")
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .foregroundStyle(.white)
                    Spacer()
                    Text("\(Int(progress * 100))%")
                        .font(.system(.caption, design: .rounded, weight: .bold))
                        .foregroundStyle(.white.opacity(0.8))
                }
                ProgressView(value: progress)
                    .tint(Color(red: 0.14, green: 0.74, blue: 0.88))
                Text(message)
                    .font(.system(.footnote, design: .rounded, weight: .medium))
                    .foregroundStyle(.white.opacity(0.8))
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.white.opacity(0.10)))
        case .success(let message):
            stateMessageCard(message: message, tint: .green, icon: "checkmark.seal.fill")
        case .failure(let message):
            stateMessageCard(message: message, tint: .red, icon: "xmark.octagon.fill")
        }
    }

    private func stateMessageCard(message: String, tint: Color, icon: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(tint)
            Text(message)
                .font(.system(.footnote, design: .rounded, weight: .medium))
                .foregroundStyle(.white.opacity(0.9))
            Spacer()
            Button {
                appModel.clearModelImportFeedback()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white.opacity(0.74))
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.white.opacity(0.10)))
    }

    private func setupStep(index: Int, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(index)")
                .font(.system(.caption, design: .rounded, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(Circle().fill(Color.white.opacity(0.18)))

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(.white)
                Text(detail)
                    .font(.system(.footnote, design: .rounded, weight: .medium))
                    .foregroundStyle(.white.opacity(0.75))
            }
        }
    }

    private var librarySummary: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Model Library")
                .font(.system(.headline, design: .rounded, weight: .semibold))
                .foregroundStyle(.white)

            if let active = appModel.activeModel {
                Text("Active: \(active.displayName) • \(active.status.displayName)")
                    .font(.system(.footnote, design: .rounded, weight: .semibold))
                    .foregroundStyle(active.status == .ready ? .green.opacity(0.95) : .orange)
            } else {
                Text("No active model selected")
                    .font(.system(.footnote, design: .rounded, weight: .semibold))
                    .foregroundStyle(.orange)
            }

            Text("Imported models: \(appModel.models.count)")
                .font(.system(.footnote, design: .rounded, weight: .medium))
                .foregroundStyle(.white.opacity(0.78))
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color.white.opacity(0.10)))
    }

    private var actions: some View {
        VStack(spacing: 10) {
            Button {
                appModel.beginModelImport()
            } label: {
                Label("Import Model from Files", systemImage: "square.and.arrow.down")
                    .font(.system(.headline, design: .rounded, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color(red: 0.14, green: 0.74, blue: 0.88))

            NavigationLink {
                JarvisPhoneModelLibraryView()
            } label: {
                Label("Open Model Library", systemImage: "tray.full")
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.white.opacity(0.18))

            if !appModel.needsModelSetup {
                Button("Continue to Jarvis") {
                    appModel.dismissSetupFlowIfReady()
                    appModel.showSetupFlow = false
                }
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .foregroundStyle(.white.opacity(0.86))
            }
        }
    }
}
