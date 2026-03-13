import SwiftUI
import UniformTypeIdentifiers

struct JarvisPhoneHomeView: View {
    @EnvironmentObject private var appModel: JarvisPhoneAppModel

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 16) {
                heroCard
                importFeedbackCard
                runtimeCard
                modelCard
                quickLaunchGrid
                resumeCard
            }
            .padding(.top, 12)
            .padding(.bottom, 28)
        }
        .safeAreaInset(edge: .bottom) {
            askNowBar
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
        }
        .fileImporter(
            isPresented: $appModel.isModelImporterPresented,
            allowedContentTypes: [UTType(filenameExtension: "gguf") ?? .data],
            allowsMultipleSelection: false,
            onCompletion: appModel.handleModelImportResult
        )
    }

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(appModel.needsModelSetup ? "Set up local model" : "Instant local assistant")
                .font(.system(.title2, design: .rounded, weight: .bold))
                .foregroundStyle(.white)

            Text(heroSubtitle)
                .font(.system(.subheadline, design: .rounded, weight: .medium))
                .foregroundStyle(.white.opacity(0.82))

            Button {
                if appModel.needsModelSetup {
                    appModel.showSetupFlow = true
                } else {
                    appModel.apply(route: JarvisLaunchRoute(action: .ask, source: "home.hero"))
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: appModel.needsModelSetup ? "square.and.arrow.down" : "sparkle")
                    Text(appModel.needsModelSetup ? "Import Model" : "Start Asking")
                }
                .font(.system(.headline, design: .rounded, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color(red: 0.14, green: 0.74, blue: 0.88))
            .accessibilityHint(appModel.needsModelSetup ? "Opens setup and model import" : "Opens assistant ready for immediate input")
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .stroke(Color.white.opacity(0.16), lineWidth: 1)
                )
        )
    }

    @ViewBuilder
    private var importFeedbackCard: some View {
        switch appModel.modelImportState {
        case .idle:
            EmptyView()
        case .importing(let progress, let message):
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("Importing model", systemImage: "square.and.arrow.down")
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
                    .foregroundStyle(.white.opacity(0.82))
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.white.opacity(0.10)))
        case .success(let message):
            feedbackCard(message: message, tint: .green)
        case .failure(let message):
            feedbackCard(message: message, tint: .red)
        }
    }

    private func feedbackCard(message: String, tint: Color) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: tint == .green ? "checkmark.seal.fill" : "xmark.octagon.fill")
                .foregroundStyle(tint)
            Text(message)
                .font(.system(.footnote, design: .rounded, weight: .medium))
                .foregroundStyle(.white.opacity(0.9))
                .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                appModel.clearModelImportFeedback()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white.opacity(0.7))
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.white.opacity(0.10)))
    }

    private var runtimeCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(appModel.runtimeState.title, systemImage: runtimeIcon)
                    .font(.system(.headline, design: .rounded, weight: .semibold))
                    .foregroundStyle(.white)

                Spacer()

                if appModel.hasReadyModel {
                    Button("Warm") {
                        appModel.warmModel()
                    }
                    .buttonStyle(.bordered)
                    .tint(.white.opacity(0.8))
                }
            }

            runtimeDetail
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.white.opacity(0.10))
        )
    }

    @ViewBuilder
    private var runtimeDetail: some View {
        switch appModel.runtimeState {
        case .unavailable(let reason):
            Text(reason)
                .font(.system(.footnote, design: .rounded, weight: .medium))
                .foregroundStyle(.orange)
                .transition(.opacity)
        case .cold(let modelName):
            Text("\(modelName) is cold. First request will warm it.")
                .font(.system(.footnote, design: .rounded, weight: .medium))
                .foregroundStyle(.white.opacity(0.85))
        case .loading(let progress, let detail):
            VStack(alignment: .leading, spacing: 8) {
                ProgressView(value: progress)
                    .tint(Color(red: 0.14, green: 0.74, blue: 0.88))
                Text(detail)
                    .font(.system(.footnote, design: .rounded, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
            }
            .transition(.opacity)
        case .ready(let modelName):
            Text("Using local model: \(modelName)")
                .font(.system(.footnote, design: .rounded, weight: .medium))
                .foregroundStyle(.green.opacity(0.95))
        case .generating(let modelName):
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                    .tint(.white)
                Text("Generating with \(modelName)")
                    .font(.system(.footnote, design: .rounded, weight: .medium))
                    .foregroundStyle(.white.opacity(0.9))
            }
        case .paused(let modelName):
            Text("\(modelName ?? "Runtime") paused in background or due to thermal pressure.")
                .font(.system(.footnote, design: .rounded, weight: .medium))
                .foregroundStyle(.yellow)
        case .failed(let message):
            Text(message)
                .font(.system(.footnote, design: .rounded, weight: .medium))
                .foregroundStyle(.red.opacity(0.9))
        }
    }

    private var modelCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Model Library")
                    .font(.system(.headline, design: .rounded, weight: .semibold))
                    .foregroundStyle(.white)
                Spacer()
                Button("Manage") {
                    appModel.isModelLibraryPresented = true
                }
                .buttonStyle(.bordered)
                .tint(.white.opacity(0.85))
            }

            if let active = appModel.activeModel {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "cpu")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.top, 2)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(active.displayName)
                            .font(.system(.subheadline, design: .rounded, weight: .semibold))
                            .foregroundStyle(.white)
                        Text("\(active.format.displayName) • \(active.status.displayName)")
                            .font(.system(.caption, design: .rounded, weight: .medium))
                            .foregroundStyle(.white.opacity(0.74))
                        Text("Imported \(active.importedAt.formatted(date: .abbreviated, time: .omitted))")
                            .font(.system(.caption2, design: .rounded, weight: .medium))
                            .foregroundStyle(.white.opacity(0.66))
                    }
                    Spacer(minLength: 12)
                }
            } else {
                Text("No active model. Import a GGUF file from Files to begin.")
                    .font(.system(.footnote, design: .rounded, weight: .medium))
                    .foregroundStyle(.white.opacity(0.84))
            }

            Button {
                appModel.beginModelImport()
            } label: {
                Label("Import GGUF Model", systemImage: "square.and.arrow.down")
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.white.opacity(0.22))
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.white.opacity(0.10))
        )
    }

    private var quickLaunchGrid: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Quick Start")
                .font(.system(.headline, design: .rounded, weight: .semibold))
                .foregroundStyle(.white)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(appModel.quickLaunchItems) { item in
                    Button {
                        appModel.triggerQuickLaunch(item)
                    } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            Image(systemName: item.icon)
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(.white)
                            Text(item.title)
                                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                                .foregroundStyle(.white)
                            Text(item.subtitle)
                                .font(.system(.caption, design: .rounded, weight: .medium))
                                .foregroundStyle(.white.opacity(0.76))
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                        }
                        .frame(maxWidth: .infinity, minHeight: 118, alignment: .topLeading)
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(.ultraThinMaterial)
                        )
                    }
                    .buttonStyle(.plain)
                    .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
            }
        }
    }

    private var resumeCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recent")
                .font(.system(.headline, design: .rounded, weight: .semibold))
                .foregroundStyle(.white)

            if let last = appModel.conversations.first {
                Button {
                    appModel.apply(route: JarvisLaunchRoute(action: .continueConversation, source: "home.recent"))
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(last.title)
                            .font(.system(.subheadline, design: .rounded, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Text(last.updatedAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.system(.caption, design: .rounded, weight: .medium))
                            .foregroundStyle(.white.opacity(0.72))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 16).fill(Color.white.opacity(0.10)))
                }
                .buttonStyle(.plain)
            } else {
                Text("No conversation history yet")
                    .font(.system(.footnote, design: .rounded, weight: .medium))
                    .foregroundStyle(.white.opacity(0.75))
            }
        }
    }

    private var askNowBar: some View {
        Button {
            appModel.apply(route: JarvisLaunchRoute(action: .ask, source: "home.bottom"))
        } label: {
            HStack(spacing: 8) {
                Image(systemName: appModel.needsModelSetup ? "square.and.arrow.down" : "bolt.fill")
                Text(appModel.needsModelSetup ? "Import Model to Ask" : "Ask Jarvis Now")
                Spacer()
                Text(appModel.statusText)
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.75))
                    .lineLimit(1)
            }
            .font(.system(.headline, design: .rounded, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                Capsule(style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(Color.white.opacity(0.18), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private var runtimeIcon: String {
        switch appModel.runtimeState {
        case .unavailable: return "exclamationmark.triangle"
        case .cold: return "snowflake"
        case .loading: return "hourglass"
        case .ready: return "checkmark.seal"
        case .generating: return "waveform.path.ecg"
        case .paused: return "pause.circle"
        case .failed: return "xmark.octagon"
        }
    }

    private var heroSubtitle: String {
        if appModel.needsModelSetup {
            return "Jarvis runs fully local on iPhone. Import a GGUF model from Files to begin in seconds."
        }
        return "Launch in one tap, keep context, and get immediate feedback while your on-device model warms up."
    }
}
