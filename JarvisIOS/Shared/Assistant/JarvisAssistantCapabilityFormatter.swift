import Foundation

enum JarvisAssistantCapabilityFormatter {
    static func format(
        capabilityID: CapabilityID,
        input: CapabilityInputPayload,
        result: CapabilityResult,
        platformAvailability: CapabilityPlatformAvailability? = nil
    ) -> [JarvisAssistantCapabilitySurface] {
        switch result.output {
        case .fileSearch(let output):
            return [makeFileSearchSurface(output: output, result: result)]
        case .filePreview(let output):
            return [makeFilePreviewSurface(output: output, result: result)]
        case .filePatch(let output):
            return [makeFilePatchSurface(output: output, result: result)]
        case .fileCreate(let output):
            return [makeFileCreateSurface(output: output, result: result)]
        case .projectScaffold(let output):
            return [makeProjectScaffoldSurface(output: output, result: result)]
        case .projectOpen(let output):
            return [makeProjectOpenSurface(output: output, result: result)]
        case .projectAnalyze(let output):
            return [makeProjectAnalyzeSurface(output: output, result: result)]
        case .appOpen(let output):
            return [makeAppOpenSurface(capabilityID: capabilityID, input: input, output: output, result: result)]
        case .appFocus(let output):
            return [makeAppFocusSurface(capabilityID: capabilityID, input: input, output: output, result: result)]
        case .finderReveal(let output):
            return [makeFinderRevealSurface(input: input, output: output, result: result)]
        case .systemOpenURL(let output):
            return [makeOpenURLSurface(input: input, output: output, result: result)]
        case .shellRunSafe(let output):
            return [makeShellSurface(input: input, output: output, result: result)]
        case .fileRead:
            return []
        case .memorySearch, .memoryStore, .none:
            return fallbackSurfaces(
                capabilityID: capabilityID,
                input: input,
                result: result,
                platformAvailability: platformAvailability
            )
        }
    }

    static func allowedRootsSurface(
        roots: [JarvisAllowedDirectoryRecord],
        validationState: String? = nil,
        title: String = "Allowed Roots",
        summary: String = "Approved file system roots available to JARVIS."
    ) -> JarvisAssistantCapabilitySurface {
        let entries = roots.map { root in
            JarvisAssistantCapabilityEntry(
                title: root.name,
                subtitle: root.path,
                facts: [
                    JarvisAssistantCapabilityFact(
                        label: "Validation",
                        value: validationState ?? "allowed"
                    )
                ]
            )
        }

        return JarvisAssistantCapabilitySurface(
            kind: .allowedRoots,
            title: title,
            status: .success,
            summary: summary,
            entries: entries,
            footnote: roots.isEmpty ? "No approved roots are currently available." : nil
        )
    }

    private static func fallbackSurfaces(
        capabilityID: CapabilityID,
        input: CapabilityInputPayload,
        result: CapabilityResult,
        platformAvailability: CapabilityPlatformAvailability?
    ) -> [JarvisAssistantCapabilitySurface] {
        switch capabilityID.rawValue {
        case "file.patch":
            return [pendingActionSurface(
                kind: .patchApproval,
                title: "Patch Approval",
                scenarioID: capabilityID.rawValue,
                summary: result.userMessage,
                entries: [
                    makePathEntry(from: input, fallbackTitle: "Target File")
                ].compactMap { $0 }
            )]
        case "file.create":
            return [pendingActionSurface(
                kind: .patchApproval,
                title: "Create File",
                scenarioID: capabilityID.rawValue,
                summary: result.userMessage,
                entries: [
                    makePathEntry(from: input, fallbackTitle: "Destination")
                ].compactMap { $0 }
            )]
        case "project.scaffold":
            return [pendingActionSurface(
                kind: .projectAction,
                title: "Project Scaffold",
                scenarioID: capabilityID.rawValue,
                summary: result.userMessage,
                entries: [
                    makeProjectScaffoldInputEntry(from: input)
                ].compactMap { $0 }
            )]
        case "shell.run.safe":
            return [pendingActionSurface(
                kind: .shellResult,
                title: "Safe Shell Command",
                scenarioID: capabilityID.rawValue,
                summary: result.userMessage,
                entries: [
                    makeShellInputEntry(from: input)
                ].compactMap { $0 }
            )]
        case "system.open_url":
            return [pendingActionSurface(
                kind: .macAction,
                title: "Open URL",
                scenarioID: capabilityID.rawValue,
                summary: result.userMessage,
                entries: [
                    makeOpenURLEntry(from: input)
                ].compactMap { $0 }
            )]
        default:
            let platformText = platformAvailability.map(platformLabel(for:))
            return [JarvisAssistantCapabilitySurface(
                kind: .projectAction,
                title: prettyCapabilityTitle(for: capabilityID.rawValue),
                status: mapStatus(result.status, approvalState: result.approvalState),
                summary: result.userMessage,
                entries: [],
                footnote: platformText
            )]
        }
    }

    private static func makeFileSearchSurface(
        output: FileSearchCapabilityOutput,
        result: CapabilityResult
    ) -> JarvisAssistantCapabilitySurface {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        let dateFormatter = RelativeDateTimeFormatter()
        dateFormatter.unitsStyle = .short

        let entries = output.matches.map { match in
            JarvisAssistantCapabilityEntry(
                title: match.name,
                subtitle: match.path,
                facts: [
                    JarvisAssistantCapabilityFact(label: "Extension", value: match.fileExtension.isEmpty ? "none" : match.fileExtension.uppercased()),
                    JarvisAssistantCapabilityFact(label: "Size", value: formatter.string(fromByteCount: match.size)),
                    JarvisAssistantCapabilityFact(label: "Modified", value: dateFormatter.localizedString(for: match.lastModified, relativeTo: Date()))
                ]
            )
        }

        return JarvisAssistantCapabilitySurface(
            kind: .fileSearchResults,
            title: output.matches.isEmpty ? "No Files Matched" : "File Search Results",
            status: mapStatus(result.status, approvalState: result.approvalState),
            summary: result.userMessage,
            entries: entries,
            footnote: output.truncated ? "Search results were truncated." : nil
        )
    }

    private static func makeFilePreviewSurface(
        output: FilePreviewCapabilityOutput,
        result: CapabilityResult
    ) -> JarvisAssistantCapabilitySurface {
        let truncated = output.metadata["truncated"] == "true"
        return JarvisAssistantCapabilitySurface(
            kind: .filePreview,
            title: "File Preview",
            status: mapStatus(result.status, approvalState: result.approvalState),
            summary: result.userMessage,
            entries: [
                JarvisAssistantCapabilityEntry(
                    title: output.metadata["name"] ?? URL(fileURLWithPath: output.resolvedPath).lastPathComponent,
                    subtitle: output.resolvedPath,
                    facts: [
                        JarvisAssistantCapabilityFact(label: "Extension", value: (output.metadata["extension"] ?? "").isEmpty ? "none" : (output.metadata["extension"] ?? "").uppercased()),
                        JarvisAssistantCapabilityFact(label: "Truncated", value: truncated ? "Yes" : "No")
                    ]
                )
            ],
            previewText: output.previewText,
            footnote: truncated ? "Preview is truncated to keep the conversation lightweight." : nil
        )
    }

    private static func makeFilePatchSurface(
        output: FilePatchCapabilityOutput,
        result: CapabilityResult
    ) -> JarvisAssistantCapabilitySurface {
        let approval = output.requiresApproval
            ? approvalSurface(
                scenarioID: "file.patch",
                message: output.applied ? "Patch applied." : "Approval is required before this patch can run.",
                approvalState: result.approvalState
            )
            : nil

        return JarvisAssistantCapabilitySurface(
            kind: .patchApproval,
            title: output.applied ? "Patch Applied" : "Patch Approval",
            status: mapStatus(result.status, approvalState: result.approvalState),
            summary: result.userMessage,
            entries: [
                JarvisAssistantCapabilityEntry(
                    title: output.fileName,
                    subtitle: output.resolvedPath,
                    facts: [
                        JarvisAssistantCapabilityFact(label: "Line Changes", value: "\(output.lineChangeCount)"),
                        JarvisAssistantCapabilityFact(label: "Ready", value: output.canApply ? "Yes" : "No")
                    ]
                )
            ],
            previewText: output.diffSummary,
            footnote: output.rejectionReason,
            approval: approval
        )
    }

    private static func makeFileCreateSurface(
        output: FileCreateCapabilityOutput,
        result: CapabilityResult
    ) -> JarvisAssistantCapabilitySurface {
        let approval = output.requiresApproval
            ? approvalSurface(
                scenarioID: "file.create",
                message: output.created ? "File write completed." : "Approval is required before this file is created.",
                approvalState: result.approvalState
            )
            : nil

        return JarvisAssistantCapabilitySurface(
            kind: .patchApproval,
            title: output.created ? "File Created" : "Create File",
            status: mapStatus(result.status, approvalState: result.approvalState),
            summary: result.userMessage,
            entries: [
                JarvisAssistantCapabilityEntry(
                    title: output.fileName,
                    subtitle: output.resolvedPath,
                    facts: [
                        JarvisAssistantCapabilityFact(label: "Overwrite", value: output.overwritten ? "Yes" : "No"),
                        JarvisAssistantCapabilityFact(label: "Ready", value: output.canCreate ? "Yes" : "No")
                    ]
                )
            ],
            approval: approval
        )
    }

    private static func makeProjectScaffoldSurface(
        output: ProjectScaffoldCapabilityOutput,
        result: CapabilityResult
    ) -> JarvisAssistantCapabilitySurface {
        JarvisAssistantCapabilitySurface(
            kind: .projectAction,
            title: "Project Scaffold",
            status: mapStatus(result.status, approvalState: result.approvalState),
            summary: result.userMessage,
            entries: [
                JarvisAssistantCapabilityEntry(
                    title: "Destination",
                    subtitle: output.rootPath,
                    facts: [
                        JarvisAssistantCapabilityFact(label: "Files", value: "\(output.createdFilesCount)")
                    ]
                )
            ],
            footnote: output.summary
        )
    }

    private static func makeProjectOpenSurface(
        output: ProjectOpenCapabilityOutput,
        result: CapabilityResult
    ) -> JarvisAssistantCapabilitySurface {
        JarvisAssistantCapabilitySurface(
            kind: .projectAction,
            title: "Project Action",
            status: mapStatus(result.status, approvalState: result.approvalState),
            summary: result.userMessage,
            entries: [
                JarvisAssistantCapabilityEntry(title: output.target)
            ]
        )
    }

    private static func makeProjectAnalyzeSurface(
        output: ProjectAnalyzeCapabilityOutput,
        result: CapabilityResult
    ) -> JarvisAssistantCapabilitySurface {
        JarvisAssistantCapabilitySurface(
            kind: .projectAction,
            title: "Project Analysis",
            status: mapStatus(result.status, approvalState: result.approvalState),
            summary: output.summary,
            entries: output.interestingPaths.prefix(4).map {
                JarvisAssistantCapabilityEntry(title: $0)
            },
            footnote: output.detectedStack.isEmpty ? nil : "Detected stack: \(output.detectedStack.joined(separator: ", "))"
        )
    }

    private static func makeAppOpenSurface(
        capabilityID: CapabilityID,
        input: CapabilityInputPayload,
        output: AppOpenCapabilityOutput,
        result: CapabilityResult
    ) -> JarvisAssistantCapabilitySurface {
        let target = output.resolvedAppName ?? appTarget(from: input) ?? prettyCapabilityTitle(for: capabilityID.rawValue)
        return JarvisAssistantCapabilitySurface(
            kind: .macAction,
            title: "macOS Action",
            status: mapStatus(result.status, approvalState: result.approvalState),
            summary: result.userMessage,
            entries: [
                JarvisAssistantCapabilityEntry(
                    title: target,
                    facts: [
                        JarvisAssistantCapabilityFact(label: "Action", value: "Open App"),
                        JarvisAssistantCapabilityFact(label: "Status", value: output.launched ? "Success" : "Failed")
                    ]
                )
            ]
        )
    }

    private static func makeAppFocusSurface(
        capabilityID: CapabilityID,
        input: CapabilityInputPayload,
        output: AppFocusCapabilityOutput,
        result: CapabilityResult
    ) -> JarvisAssistantCapabilitySurface {
        JarvisAssistantCapabilitySurface(
            kind: .macAction,
            title: "macOS Action",
            status: mapStatus(result.status, approvalState: result.approvalState),
            summary: result.userMessage,
            entries: [
                JarvisAssistantCapabilityEntry(
                    title: appTarget(from: input) ?? prettyCapabilityTitle(for: capabilityID.rawValue),
                    facts: [
                        JarvisAssistantCapabilityFact(label: "Action", value: "Focus App"),
                        JarvisAssistantCapabilityFact(label: "Status", value: output.focused ? "Success" : "Failed")
                    ]
                )
            ]
        )
    }

    private static func makeFinderRevealSurface(
        input: CapabilityInputPayload,
        output: FinderRevealCapabilityOutput,
        result: CapabilityResult
    ) -> JarvisAssistantCapabilitySurface {
        JarvisAssistantCapabilitySurface(
            kind: .macAction,
            title: "macOS Action",
            status: mapStatus(result.status, approvalState: result.approvalState),
            summary: result.userMessage,
            entries: [
                JarvisAssistantCapabilityEntry(
                    title: "Reveal in Finder",
                    subtitle: path(from: input),
                    facts: [
                        JarvisAssistantCapabilityFact(label: "Status", value: output.revealed ? "Success" : "Failed")
                    ]
                )
            ]
        )
    }

    private static func makeOpenURLSurface(
        input: CapabilityInputPayload,
        output: SystemOpenURLCapabilityOutput,
        result: CapabilityResult
    ) -> JarvisAssistantCapabilitySurface {
        JarvisAssistantCapabilitySurface(
            kind: .macAction,
            title: "macOS Action",
            status: mapStatus(result.status, approvalState: result.approvalState),
            summary: result.userMessage,
            entries: [
                JarvisAssistantCapabilityEntry(
                    title: "Open URL",
                    subtitle: openURL(from: input),
                    facts: [
                        JarvisAssistantCapabilityFact(label: "Status", value: output.opened ? "Success" : "Failed")
                    ]
                )
            ]
        )
    }

    private static func makeShellSurface(
        input: CapabilityInputPayload,
        output: ShellRunSafeCapabilityOutput,
        result: CapabilityResult
    ) -> JarvisAssistantCapabilitySurface {
        let summary = output.stderr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? output.stdout
            : output.stderr

        return JarvisAssistantCapabilitySurface(
            kind: .shellResult,
            title: "Shell Result",
            status: mapStatus(result.status, approvalState: result.approvalState),
            summary: result.userMessage,
            entries: [
                JarvisAssistantCapabilityEntry(
                    title: shellCommand(from: input) ?? "shell.run.safe",
                    subtitle: shellPath(from: input),
                    facts: [
                        JarvisAssistantCapabilityFact(label: "Exit Code", value: "\(output.exitCode)")
                    ]
                )
            ],
            previewText: summary.trimmingCharacters(in: .whitespacesAndNewlines),
            footnote: output.truncated ? "Output was truncated." : nil
        )
    }

    private static func pendingActionSurface(
        kind: JarvisAssistantCapabilitySurfaceKind,
        title: String,
        scenarioID: String,
        summary: String,
        entries: [JarvisAssistantCapabilityEntry]
    ) -> JarvisAssistantCapabilitySurface {
        JarvisAssistantCapabilitySurface(
            kind: kind,
            title: title,
            status: .pending,
            summary: summary,
            entries: entries,
            approval: JarvisAssistantApprovalSurface(
                scenarioID: scenarioID,
                title: title,
                message: "Approval routing is not connected to the runtime in this build yet.",
                decision: .pending,
                runtimeHookAvailable: false
            )
        )
    }

    private static func approvalSurface(
        scenarioID: String,
        message: String,
        approvalState: ApprovalState
    ) -> JarvisAssistantApprovalSurface {
        JarvisAssistantApprovalSurface(
            scenarioID: scenarioID,
            title: "Pending Approval",
            message: message,
            decision: mapApprovalDecision(approvalState),
            runtimeHookAvailable: false
        )
    }

    private static func mapStatus(
        _ status: CapabilityExecutionStatus,
        approvalState: ApprovalState
    ) -> JarvisAssistantCapabilityStatus {
        if approvalState == .denied {
            return .denied
        }

        switch status {
        case .pending, .executing:
            return .executing
        case .requiresApproval:
            return .pending
        case .success:
            return .success
        case .failed:
            return .failed
        case .denied:
            return .denied
        case .unsupported:
            return .unsupported
        case .cancelled:
            return .cancelled
        }
    }

    private static func mapApprovalDecision(_ approvalState: ApprovalState) -> JarvisAssistantApprovalDecision {
        switch approvalState {
        case .approved:
            return .approved
        case .denied:
            return .denied
        case .notRequired, .required:
            return .pending
        }
    }

    private static func makePathEntry(
        from input: CapabilityInputPayload,
        fallbackTitle: String
    ) -> JarvisAssistantCapabilityEntry? {
        let path: String? = {
            switch input {
            case .filePatch(let input):
                return input.path.displayPath
            case .fileCreate(let input):
                return (input.parent.displayPath as NSString).appendingPathComponent(input.name)
            default:
                return nil
            }
        }()

        guard let path else { return nil }
        let title = URL(fileURLWithPath: path).lastPathComponent.isEmpty ? fallbackTitle : URL(fileURLWithPath: path).lastPathComponent
        return JarvisAssistantCapabilityEntry(title: title, subtitle: path)
    }

    private static func makeProjectScaffoldInputEntry(from input: CapabilityInputPayload) -> JarvisAssistantCapabilityEntry? {
        guard case .projectScaffold(let scaffold) = input else { return nil }
        return JarvisAssistantCapabilityEntry(
            title: scaffold.name,
            subtitle: scaffold.destination.displayPath,
            facts: [
                JarvisAssistantCapabilityFact(label: "Template", value: scaffold.template.rawValue)
            ]
        )
    }

    private static func makeShellInputEntry(from input: CapabilityInputPayload) -> JarvisAssistantCapabilityEntry? {
        guard case .shellRunSafe(let shell) = input else { return nil }
        return JarvisAssistantCapabilityEntry(
            title: shell.command.rawValue,
            subtitle: shell.cwd?.displayPath,
            facts: []
        )
    }

    private static func makeOpenURLEntry(from input: CapabilityInputPayload) -> JarvisAssistantCapabilityEntry? {
        guard case .systemOpenURL(let openURL) = input else { return nil }
        return JarvisAssistantCapabilityEntry(title: "Open URL", subtitle: openURL.url.absoluteString)
    }

    private static func appTarget(from input: CapabilityInputPayload) -> String? {
        switch input {
        case .appOpen(let app):
            return app.bundleID ?? app.appURL?.lastPathComponent
        case .appFocus(let focus):
            return focus.bundleID
        default:
            return nil
        }
    }

    private static func openURL(from input: CapabilityInputPayload) -> String? {
        guard case .systemOpenURL(let openURL) = input else { return nil }
        return openURL.url.absoluteString
    }

    private static func shellCommand(from input: CapabilityInputPayload) -> String? {
        guard case .shellRunSafe(let shell) = input else { return nil }
        return shell.command.rawValue
    }

    private static func shellPath(from input: CapabilityInputPayload) -> String? {
        guard case .shellRunSafe(let shell) = input else { return nil }
        return shell.cwd?.displayPath
    }

    private static func path(from input: CapabilityInputPayload) -> String? {
        guard case .finderReveal(let reveal) = input else { return nil }
        return reveal.path.displayPath
    }

    private static func prettyCapabilityTitle(for rawValue: String) -> String {
        rawValue
            .split(separator: ".")
            .map { $0.capitalized }
            .joined(separator: " ")
    }

    private static func platformLabel(for availability: CapabilityPlatformAvailability) -> String {
        switch availability {
        case .shared:
            return "Available on all supported builds."
        case .macOSOnly:
            return "Available on macOS only."
        case .iOSOnly:
            return "Available on iOS only."
        case .unsupported:
            return "Not available in this build."
        }
    }
}
