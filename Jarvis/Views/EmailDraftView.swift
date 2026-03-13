import SwiftUI

struct EmailDraftView: View {
    @EnvironmentObject private var viewModel: EmailDraftViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                JarvisSectionHeader(title: "1. Source context", subtitle: "Captured thread or pasted context")
                Spacer()
                if viewModel.isCapturing {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            TextEditor(text: $viewModel.extractedText)
                .font(.body)
                .frame(height: 140)
                .padding(8)
                .jarvisCard(fill: JarvisPalette.panelMuted, border: JarvisPalette.border, shadowOpacity: 0.02)

            HStack(spacing: 8) {
                Button("Draft reply") { viewModel.draftReply() }
                    .disabled(viewModel.extractedText.isEmpty)
                    .buttonStyle(JarvisButtonStyle(tone: .primary))
                Button("Copy") { viewModel.copyDraft() }
                    .disabled(viewModel.draft.isEmpty)
                    .buttonStyle(JarvisButtonStyle(tone: .secondary))
                Button("Open Mail") { viewModel.openMail() }
                    .buttonStyle(JarvisButtonStyle(tone: .secondary))

                Spacer()

                Picker("Tone", selection: $viewModel.selectedTone) {
                    ForEach(ToneStyle.allCases, id: \.self) { tone in
                        Text(tone.rawValue.capitalized).tag(tone)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 150)

                Button("Improve tone") {
                    viewModel.improveTone(viewModel.selectedTone)
                }
                .disabled(viewModel.draft.isEmpty || viewModel.isGenerating)
                .buttonStyle(JarvisButtonStyle(tone: .secondary))
            }
            JarvisStatusRow(
                tone: .info,
                message: "If Mail insert is unavailable, use Copy and paste the draft manually."
            )

            JarvisSectionHeader(title: "2. Draft", subtitle: "Final text for copy/insert")
            TextEditor(text: $viewModel.draft)
                .font(.body)
                .frame(height: 200)
                .padding(8)
                .jarvisCard(fill: JarvisPalette.panel, border: JarvisPalette.border, shadowOpacity: 0.03)

            if !viewModel.citations.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Supporting lines")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ForEach(viewModel.citations, id: \.self) { citation in
                        Text("• \(citation)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(10)
                .jarvisCard(fill: JarvisPalette.panelMuted, border: JarvisPalette.border, shadowOpacity: 0.02)
            }

            if let status = viewModel.statusMessage {
                JarvisStatusRow(
                    tone: status.localizedCaseInsensitiveContains("failed") ? .error : .info,
                    message: status
                )
            }
        }
    }
}
