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
                    .disabled(viewModel.draft.isEmpty)
                Spacer()
                Menu("Improve tone") {
                    ForEach(ToneStyle.allCases, id: \.self) { tone in
                        Button(tone.rawValue.capitalized) { viewModel.improveTone(tone) }
                    }
                }
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
