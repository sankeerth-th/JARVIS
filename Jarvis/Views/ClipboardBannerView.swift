import SwiftUI

struct ClipboardBannerView: View {
    let text: String
    let clearAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Clipboard preview")
                Spacer()
                Button("Clear", action: clearAction)
                    .buttonStyle(.borderless)
            }
            Text(text)
                .font(.caption)
                .lineLimit(4)
        }
        .padding(8)
        .background(Color.orange.opacity(0.1))
        .cornerRadius(8)
    }
}
