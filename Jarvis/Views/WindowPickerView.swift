import SwiftUI
import ScreenCaptureKit

struct WindowPickerView: View {
    @State private var windows: [SCWindow] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    let onSelect: (SCWindow) -> Void
    let onCancel: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Select Window")
                    .font(.headline)
                Spacer()
                Button("Cancel", action: onCancel)
                    .buttonStyle(.borderless)
            }
            .padding()
            
            if isLoading {
                ProgressView("Loading windows...")
                    .padding()
            } else if let error = errorMessage {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 32))
                        .foregroundStyle(.secondary)
                    Text(error)
                        .foregroundStyle(.secondary)
                }
                .padding()
            } else if windows.isEmpty {
                Text("No windows available")
                    .foregroundStyle(.secondary)
                    .padding()
            } else {
                List(windows) { window in
                    WindowRow(window: window)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            onSelect(window)
                        }
                }
                .listStyle(.plain)
            }
        }
        .frame(width: 400, height: 500)
        .task {
            await loadWindows()
        }
    }
    
    private func loadWindows() async {
        do {
            let content = try await SCShareableContent.current
            let currentPID = ProcessInfo.processInfo.processIdentifier
            windows = content.windows.filter { window in
                window.owningApplication?.processID != currentPID &&
                window.isOnScreen &&
                !(window.title?.isEmpty ?? true) &&
                window.frame.width > 100 &&
                window.frame.height > 50
            }
            isLoading = false
        } catch {
            errorMessage = "Failed to load windows: \(error.localizedDescription)"
            isLoading = false
        }
    }
}

struct WindowRow: View {
    let window: SCWindow
    
    var body: some View {
        HStack(spacing: 12) {
            // App icon placeholder
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.secondary.opacity(0.2))
                .frame(width: 48, height: 48)
                .overlay(
                    Image(systemName: "app.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(.secondary)
                )
            
            VStack(alignment: .leading, spacing: 2) {
                Text(window.title ?? "Untitled")
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                
                Text(window.owningApplication?.applicationName ?? "Unknown App")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
        }
        .padding(.vertical, 8)
    }
}

extension SCWindow: @retroactive Identifiable {
    public var id: CGWindowID {
        windowID
    }
}
