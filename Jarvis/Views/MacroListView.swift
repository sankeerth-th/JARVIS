import SwiftUI

struct MacroListView: View {
    @EnvironmentObject private var commandVM: CommandPaletteViewModel
    @EnvironmentObject private var settingsVM: SettingsViewModel
    @State private var macroName: String = ""
    @State private var macroPrompt: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            JarvisSectionHeader(
                title: "Workflow macros",
                subtitle: "Create and run reusable local automations"
            )

            HStack {
                TextField("Macro name", text: $macroName)
                    .textFieldStyle(.roundedBorder)
                TextField("Prompt", text: $macroPrompt)
                    .textFieldStyle(.roundedBorder)
                Button("Save") {
                    let step = MacroStep(kind: .runPrompt, payload: ["prompt": macroPrompt])
                    settingsVM.createMacro(name: macroName, steps: [step])
                    macroName = ""
                    macroPrompt = ""
                }
                .disabled(macroName.isEmpty || macroPrompt.isEmpty)
                .buttonStyle(JarvisButtonStyle(tone: .primary))
            }

            HStack {
                Button("Add OCR cleanup macro") {
                    let steps = [
                        MacroStep(kind: .runTool, payload: ["tool": "ocrCurrentWindow"]),
                        MacroStep(kind: .runPrompt, payload: ["prompt": "Rewrite the extracted OCR text cleanly and keep important details only:\n{{last_output}}"])
                    ]
                    settingsVM.createMacro(name: "Window OCR Cleanup", steps: steps)
                }
                .buttonStyle(JarvisButtonStyle(tone: .secondary))
                Text("Capture active window -> OCR -> clean rewrite")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            List(settingsVM.macros) { macro in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(macro.name)
                            .font(.body.weight(.semibold))
                        Text("Steps: \(macro.steps.map(\.kind.rawValue).joined(separator: " -> "))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Run") { commandVM.runMacro(macro) }
                        .buttonStyle(JarvisButtonStyle(tone: .primary))
                    Button(role: .destructive, action: { settingsVM.deleteMacro(macro) }) {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                }
                .listRowBackground(Color.clear)
            }
            .scrollContentBackground(.hidden)
            .background(Color.clear)

            if !commandVM.macroLogs.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Last run")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 6) {
                            ForEach(commandVM.macroLogs) { log in
                                Text("• \(log.message)")
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                    .frame(height: 120)
                }
                .padding(10)
                .jarvisCard(fill: JarvisPalette.panel, border: JarvisPalette.border, shadowOpacity: 0.02)
            }
        }
        .padding(10)
        .jarvisCard(fill: JarvisPalette.panelMuted, border: JarvisPalette.border, shadowOpacity: 0.02)
    }
}
