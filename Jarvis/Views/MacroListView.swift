import SwiftUI

struct MacroListView: View {
    @EnvironmentObject private var commandVM: CommandPaletteViewModel
    @EnvironmentObject private var settingsVM: SettingsViewModel
    @State private var macroName: String = ""
    @State private var macroPrompt: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Workflow macros allow chaining Jarvis skills offline.")
                .font(.body)
            HStack {
                TextField("Macro name", text: $macroName)
                TextField("Prompt", text: $macroPrompt)
                Button("Save") {
                    let step = MacroStep(kind: .runPrompt, payload: ["prompt": macroPrompt])
                    settingsVM.createMacro(name: macroName, steps: [step])
                    macroName = ""
                    macroPrompt = ""
                }
                .disabled(macroName.isEmpty || macroPrompt.isEmpty)
            }
            HStack {
                Button("Add OCR cleanup macro") {
                    let steps = [
                        MacroStep(kind: .runTool, payload: ["tool": "ocrCurrentWindow"]),
                        MacroStep(kind: .runPrompt, payload: ["prompt": "Rewrite the extracted OCR text cleanly and keep important details only:\n{{last_output}}"])
                    ]
                    settingsVM.createMacro(name: "Window OCR Cleanup", steps: steps)
                }
                .buttonStyle(.borderedProminent)
                Text("Captures active window -> OCR -> clean rewrite.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            List(settingsVM.macros) { macro in
                HStack {
                    VStack(alignment: .leading) {
                        Text(macro.name).bold()
                        Text("Steps: \(macro.steps.map(\.kind.rawValue).joined(separator: " -> "))")
                            .font(.caption)
                    }
                    Spacer()
                    Button("Run") { commandVM.runMacro(macro) }
                    Button(role: .destructive, action: { settingsVM.deleteMacro(macro) }) {
                        Image(systemName: "trash")
                    }
                }
            }
            if !commandVM.macroLogs.isEmpty {
                Text("Last run")
                ScrollView {
                    ForEach(commandVM.macroLogs) { log in
                        Text("• \(log.message)").frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .frame(height: 120)
            }
        }
        .padding(8)
    }
}
