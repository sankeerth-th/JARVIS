import SwiftUI

struct EmailDraftView: View {
    @EnvironmentObject private var viewModel: EmailDraftViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Extracted thread")
                Spacer()
                if viewModel.isCapturing {
                    ProgressView()
                }
            }
            TextEditor(text: $viewModel.extractedText)
                .frame(height: 120)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.2)))
            HStack {
                Button("Draft reply") { viewModel.draftReply() }
                    .disabled(viewModel.extractedText.isEmpty)
                Button("Copy") { viewModel.copyDraft() }
                    .disabled(viewModel.draft.isEmpty)
                Button("Open Mail") { viewModel.openMail() }
                Spacer()
                Picker("Tone", selection: $viewModel.selectedTone) {
                    ForEach(ToneStyle.allCases, id: \.self) { tone in
                        Text(tone.rawValue.capitalized).tag(tone)
                    }
                }
                .frame(width: 170)
                Button("Improve tone") {
                    viewModel.improveTone(viewModel.selectedTone)
                }
                .disabled(viewModel.draft.isEmpty || viewModel.isGenerating)
            }
            Text("Draft")
            TextEditor(text: $viewModel.draft)
                .frame(height: 160)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.2)))
            if !viewModel.citations.isEmpty {
                Text("Citations").font(.caption)
                ForEach(viewModel.citations, id: \.self) { citation in
                    Text("• \(citation)").font(.caption2)
                }
            }
            if let status = viewModel.statusMessage {
                Text(status).font(.footnote).foregroundStyle(.secondary)
            }
        }
    }
}
