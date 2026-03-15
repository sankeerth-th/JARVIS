import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct JarvisPhoneModelLibraryView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appModel: JarvisPhoneAppModel

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [Color.black.opacity(0.96), Color.black.opacity(0.84)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                if appModel.models.isEmpty {
                    emptyState
                } else {
                    ScrollView(showsIndicators: false) {
                        LazyVStack(spacing: 10) {
                            ForEach(appModel.models) { model in
                                modelRow(model)
                            }
                        }
                        .padding(16)
                        .padding(.bottom, 18)
                    }
                }
            }
            .navigationTitle("Model Library")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        appModel.beginModelImport()
                    } label: {
                        Label("Import", systemImage: "plus")
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

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "tray")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(.white.opacity(0.8))
            Text("No imported models")
                .font(.system(.headline, design: .rounded, weight: .semibold))
                .foregroundStyle(.white)
            Text("Import a GGUF model from Files to start using Jarvis.")
                .font(.system(.footnote, design: .rounded, weight: .medium))
                .foregroundStyle(.white.opacity(0.74))
                .multilineTextAlignment(.center)
            Button {
                appModel.beginModelImport()
            } label: {
                Label("Import Model", systemImage: "square.and.arrow.down")
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color(red: 0.14, green: 0.74, blue: 0.88))
            .padding(.top, 6)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func modelRow(_ model: JarvisImportedModel) -> some View {
        let isActive = appModel.activeModelID == model.id

        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.displayName)
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    Text("\(model.format.displayName) • \(ByteCountFormatter.string(fromByteCount: model.fileSizeBytes, countStyle: .file))")
                        .font(.system(.caption, design: .rounded, weight: .medium))
                        .foregroundStyle(.white.opacity(0.72))

                    if let family = model.inferredFamily {
                        Text("Family: \(family)")
                            .font(.system(.caption2, design: .rounded, weight: .medium))
                            .foregroundStyle(.white.opacity(0.62))
                    }
                }

                Spacer(minLength: 10)

                VStack(alignment: .trailing, spacing: 6) {
                    statusPill(
                        title: model.importState.displayName,
                        color: model.canActivate ? .green : statusColor(for: model.status)
                    )
                    if isActive {
                        Text("Active")
                            .font(.system(.caption2, design: .rounded, weight: .bold))
                            .foregroundStyle(.green)
                    }
                }
            }

            if let message = model.statusMessage, !message.isEmpty {
                Text(message)
                    .font(.system(.caption, design: .rounded, weight: .medium))
                    .foregroundStyle(.orange)
            }

            HStack(spacing: 8) {
                Button {
                    appModel.setActiveModel(id: model.id)
                } label: {
                    Text(isActive ? "Selected" : "Set Active")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(isActive ? .green.opacity(0.8) : Color(red: 0.14, green: 0.74, blue: 0.88))
                .disabled(!model.canActivate || isActive)

                Button("Revalidate") {
                    appModel.revalidateModel(id: model.id)
                }
                .buttonStyle(.bordered)
                .tint(.white.opacity(0.85))

                Button(role: .destructive) {
                    appModel.removeModel(id: model.id)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.bordered)
                .tint(.red.opacity(0.9))
            }
            .font(.system(.caption, design: .rounded, weight: .semibold))
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(isActive ? Color.green.opacity(0.5) : Color.white.opacity(0.14), lineWidth: 1)
                )
        )
    }

    private func statusPill(title: String, color: Color) -> some View {
        Text(title)
            .font(.system(.caption2, design: .rounded, weight: .bold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .foregroundStyle(color)
            .background(
                Capsule(style: .continuous)
                    .fill(color.opacity(0.15))
            )
    }

    private func statusColor(for status: JarvisModelRecordStatus) -> Color {
        switch status {
        case .ready: return .green
        case .invalid: return .orange
        case .unsupported: return .yellow
        case .missing: return .red
        case .failed: return .red
        }
    }
}

struct JarvisGGUFImportPicker: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    let onCompletion: (Result<[URL], Error>) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(
            forOpeningContentTypes: [UTType(filenameExtension: "gguf") ?? .data],
            asCopy: true
        )
        picker.allowsMultipleSelection = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        private let parent: JarvisGGUFImportPicker

        init(parent: JarvisGGUFImportPicker) {
            self.parent = parent
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            parent.isPresented = false
            parent.onCompletion(.success(urls))
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            parent.isPresented = false
        }
    }
}
