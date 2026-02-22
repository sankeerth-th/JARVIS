import SwiftUI

struct EmailDraftView: View {
    @EnvironmentObject private var viewModel: EmailDraftViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Extracted thread", systemImage: "text.quote")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if viewModel.isCapturing {
                    ProgressView()
                }
            }

            TextEditor(text: $viewModel.extractedText)
                .font(.body)
                .frame(height: 150)
                .padding(8)
                .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )

            HStack(spacing: 8) {
                Button("Draft reply") { viewModel.draftReply() }
                    .disabled(viewModel.extractedText.isEmpty)
                    .buttonStyle(.borderedProminent)
                Button("Copy") { viewModel.copyDraft() }
                    .disabled(viewModel.draft.isEmpty)
                    .buttonStyle(.bordered)
                Button("Open Mail") { viewModel.openMail() }
                    .buttonStyle(.bordered)
                Spacer()
                Picker("Tone", selection: $viewModel.selectedTone) {
                    ForEach(ToneStyle.allCases, id: \.self) { tone in
                        Text(tone.rawValue.capitalized).tag(tone)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 140)
                Button("Improve tone") {
                    viewModel.improveTone(viewModel.selectedTone)
                }
                .disabled(viewModel.draft.isEmpty || viewModel.isGenerating)
                .buttonStyle(.bordered)
            }

            Text("Draft")
                .font(.subheadline.weight(.semibold))
            TextEditor(text: $viewModel.draft)
                .font(.body)
                .frame(height: 190)
                .padding(8)
                .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )

            if !viewModel.citations.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Citations")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ForEach(viewModel.citations, id: \.self) { citation in
                        Text("- \(citation)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(10)
                .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            if let status = viewModel.statusMessage {
                Text(status)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
