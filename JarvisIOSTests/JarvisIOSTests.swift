import XCTest
@testable import JarvisIOS

final class JarvisIOSTests: XCTestCase {
    @MainActor
    func testRuntimeTransitionsFromColdToReadyWithAccessGrant() async throws {
        let engine = TestGGUFEngine()
        let runtime = JarvisLocalModelRuntime(engine: engine)
        let modelURL = try temporaryGGUFURL(named: "runtime-ready")

        runtime.setSelectedModel(
            JarvisRuntimeModelSelection(
                id: UUID(),
                displayName: "Test Model",
                family: .gemma,
                modality: .textOnly,
                capabilities: JarvisModelCapabilities(supportsTextGeneration: true),
                projectorAttached: false,
                inactiveAccessDetail: "Bookmark stored. Warm when needed.",
                acquireResources: {
                    JarvisRuntimeResolvedModelResources(modelURL: modelURL, projectorURL: nil) {}
                }
            )
        )

        XCTAssertEqual(runtime.state, .cold(modelName: "Test Model"))
        if case .accessPending(let modelName, _) = runtime.fileAccessState {
            XCTAssertEqual(modelName, "Test Model")
        } else {
            XCTFail("Expected pending access state before warmup")
        }

        try await runtime.prepareIfNeeded()
        XCTAssertEqual(runtime.state, .ready(modelName: "Test Model"))
        XCTAssertEqual(engine.loadCount, 1)
        XCTAssertEqual(engine.loadedPath, modelURL.path)
        if case .accessGranted(let modelName, _) = runtime.fileAccessState {
            XCTAssertEqual(modelName, "Test Model")
        } else {
            XCTFail("Expected granted file access after warmup")
        }
    }

    func testSettingsStoreRoundTripsMeaningfulPreferences() throws {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let store = JarvisAssistantSettingsStore(defaults: defaults)
        let settings = JarvisAssistantSettings(
            startupRoute: .assistant,
            preferredModelProfile: .gemma3_4b_it_q4_0,
            autoWarmOnLaunch: true,
            autoWarmOnFirstSend: false,
            performanceProfile: .quality,
            contextWindow: .extended,
            responseStyle: .detailed,
            creativity: 0.9,
            unloadModelOnBackground: true,
            batterySaverMode: false,
            autoScrollConversation: false,
            showRuntimeDiagnostics: true,
            hapticsEnabled: false,
            autoStartListeningForVoiceEntry: false,
            autoSendVoiceAfterPause: false,
            speechLocaleIdentifier: "en-US"
        )

        store.save(settings)
        XCTAssertEqual(store.load(), settings)
    }

    func testLaunchRouteParsesModelLibraryRoute() throws {
        let route = try XCTUnwrap(JarvisLaunchRoute.parse(url: XCTUnwrap(URL(string: "jarvis://models?source=test"))))
        XCTAssertEqual(route.action, .modelLibrary)
        XCTAssertEqual(route.source, "test")
    }

    func testLaunchRouteParsesAssistantVoiceOptions() throws {
        let route = try XCTUnwrap(
            JarvisLaunchRoute.parse(
                url: XCTUnwrap(URL(string: "jarvis://voice?source=shortcut&task=chat&listen=1&focus=0"))
            )
        )

        XCTAssertEqual(route.action, .voice)
        XCTAssertEqual(route.entryRoute, .voice)
        XCTAssertEqual(route.assistantTask, .chat)
        XCTAssertEqual(route.shouldStartListening, true)
        XCTAssertEqual(route.shouldFocusComposer, false)
        XCTAssertEqual(route.sourceKind, .shortcut)
    }

    @MainActor
    func testAskRouteWithoutModelShowsAssistantUnavailableState() {
        let appModel = makeAppModel()

        appModel.apply(route: JarvisLaunchRoute(action: .ask, source: "test"))

        XCTAssertEqual(appModel.selectedTab, .assistant)
        XCTAssertFalse(appModel.showSetupFlow)
        XCTAssertEqual(appModel.assistantEntryStyle, .quickAsk)
        if case .unavailable(let reason) = appModel.assistantExperienceState {
            XCTAssertTrue(reason.contains("Import and activate"))
        } else {
            XCTFail("Expected assistant unavailable state")
        }
    }

    @MainActor
    func testModelLibraryRoutePresentsLibraryFromSettings() {
        let appModel = makeAppModel()

        appModel.apply(route: JarvisLaunchRoute(action: .modelLibrary, source: "test"))

        XCTAssertEqual(appModel.selectedTab, .settings)
        XCTAssertTrue(appModel.isModelLibraryPresented)
    }

    @MainActor
    func testKnowledgeRouteAppliesIncomingQuery() {
        let appModel = makeAppModel()

        appModel.apply(route: JarvisLaunchRoute(action: .knowledge, query: "flight receipt", source: "test"))

        XCTAssertEqual(appModel.selectedTab, .knowledge)
        XCTAssertEqual(appModel.knowledgeQuery, "flight receipt")
        XCTAssertEqual(appModel.activeAssistantRoute, .knowledge)
    }

    func testSupportedModelCatalogMatchesGemmaGoldPathFilename() {
        let assessment = JarvisSupportedModelCatalog.assess(
            filename: "gemma-3-4b-it-q4_0.gguf",
            fileSizeBytes: 3_400_000_000,
            format: .gguf
        )

        XCTAssertEqual(assessment.status, .ready)
        XCTAssertEqual(assessment.supportedProfileID, .gemma3_4b_it_q4_0)
        XCTAssertEqual(assessment.compatibilityClass, .primaryRecommended)
    }

    func testSupportedModelCatalogMatchesGemmaQATGoldPathFilename() {
        let assessment = JarvisSupportedModelCatalog.assess(
            filename: "gemma-3-4b-it-qat-q4_0.gguf",
            fileSizeBytes: 2_530_000_000,
            format: .gguf
        )

        XCTAssertEqual(assessment.status, .ready)
        XCTAssertEqual(assessment.supportedProfileID, .gemma3_4b_it_q4_0)
        XCTAssertEqual(assessment.compatibilityClass, .primaryRecommended)
    }

    func testSupportedModelCatalogMarksGenericImportAsImportOnly() {
        let assessment = JarvisSupportedModelCatalog.assess(
            filename: "Qwen2.5-3B-Instruct-Q4_K_M.gguf",
            fileSizeBytes: 1_900_000_000,
            format: .gguf
        )

        XCTAssertEqual(assessment.status, .ready)
        XCTAssertEqual(assessment.compatibilityClass, .importOnly)
        XCTAssertNil(assessment.supportedProfileID)
    }

    func testModelLibraryImportCopiesIntoSandboxAndDoesNotAutoActivate() throws {
        let suffix = UUID().uuidString
        let library = JarvisModelLibrary(payloadFilename: "JarvisModelLibrary-\(suffix).json")
        let supportedURL = try temporarySparseGGUFURL(
            named: "gemma-3-4b-it-q4_0",
            size: 3_400_000_000
        )

        let imported = try library.importModel(from: supportedURL)

        XCTAssertEqual(imported.importState, .imported)
        XCTAssertEqual(imported.activationEligibility, .eligible)
        XCTAssertEqual(imported.supportedProfileID, .gemma3_4b_it_q4_0)
        XCTAssertEqual(imported.primaryAsset.storageKind, .sandboxCopy)
        XCTAssertNotNil(imported.primaryAsset.sandboxStoredFilename)
        XCTAssertNil(library.activeModelID())
    }

    func testModelLibraryImportAllowsGenericGGUFWhileLeavingProfileUnset() throws {
        let suffix = UUID().uuidString
        let library = JarvisModelLibrary(payloadFilename: "JarvisModelLibrary-\(suffix).json")
        let genericURL = try temporarySparseGGUFURL(
            named: "Qwen2.5-3B-Instruct-Q4_K_M",
            size: 1_900_000_000
        )

        let imported = try library.importModel(from: genericURL)

        XCTAssertEqual(imported.importState, .imported)
        XCTAssertEqual(imported.activationEligibility, .eligible)
        XCTAssertNil(imported.supportedProfileID)
        XCTAssertEqual(imported.family, .qwen)
    }

    func testModelLibraryActivationSucceedsForGenericGGUF() throws {
        let suffix = UUID().uuidString
        let library = JarvisModelLibrary(payloadFilename: "JarvisModelLibrary-\(suffix).json")
        let genericURL = try temporarySparseGGUFURL(
            named: "Qwen2.5-3B-Instruct-Q4_K_M",
            size: 1_900_000_000
        )

        let imported = try library.importModel(from: genericURL)
        let activated = try library.activateModel(id: imported.id)

        XCTAssertEqual(activated.activationEligibility, .eligible)
        XCTAssertEqual(library.activeModelID(), imported.id)
    }

    func testModelLibraryActivationSucceedsForCuratedGemma() throws {
        let suffix = UUID().uuidString
        let library = JarvisModelLibrary(payloadFilename: "JarvisModelLibrary-\(suffix).json")
        let supportedURL = try temporarySparseGGUFURL(
            named: "gemma-3-4b-it-q4_0",
            size: 3_400_000_000
        )

        let imported = try library.importModel(from: supportedURL)
        let activated = try library.activateModel(id: imported.id)

        XCTAssertEqual(activated.activationEligibility, .eligible)
        XCTAssertEqual(library.activeModelID(), imported.id)
    }

    func testMemoryStoreRanksPreferencesAheadOfGenericContext() {
        let store = JarvisMemoryStore(filename: "JarvisMemoryStore-\(UUID().uuidString).json")
        store.clearAll()

        store.upsertMemory(
            JarvisMemoryRecord(
                kind: .preference,
                title: "User preference",
                content: "I prefer concise bullet summaries for project updates.",
                confidence: 0.9,
                importance: 0.9,
                isPinned: true,
                tags: ["summary", "project"]
            ),
            maxCount: 20
        )

        store.upsertMemory(
            JarvisMemoryRecord(
                kind: .recentContext,
                title: "Recent note",
                content: "We discussed a project update last week.",
                confidence: 0.4,
                importance: 0.3,
                tags: ["project"]
            ),
            maxCount: 20
        )

        let matches = store.searchMemories(query: "project summary preference", conversationID: nil, limit: 5)

        XCTAssertEqual(matches.first?.record.kind, .preference)
        XCTAssertTrue(matches.first?.score ?? 0 > matches.dropFirst().first?.score ?? 0)
    }

    @MainActor
    func testConversationMemoryManagerCreatesSummaryAndRecall() {
        let store = JarvisMemoryStore(filename: "JarvisMemorySummary-\(UUID().uuidString).json")
        store.clearAll()

        let manager = ConversationMemoryManager(
            store: store,
            policy: MemoryRetentionPolicy(
                maxRecentMessages: 2,
                maxSummaryMessages: 4,
                maxCharactersPerMessage: 400,
                minMessageAgeForCompression: 0,
                enableSemanticCompression: true,
                maxRetrievedMemories: 3,
                maxStoredMemories: 20
            )
        )

        let conversationID = UUID()
        manager.recordInteraction(
            conversationID: conversationID,
            userMessage: JarvisChatMessage(role: .user, text: "I prefer concise plans for the release project."),
            assistantMessage: JarvisChatMessage(role: .assistant, text: "I will keep plans short and action-oriented."),
            task: .chat,
            classification: .default
        )
        manager.recordInteraction(
            conversationID: conversationID,
            userMessage: JarvisChatMessage(role: .user, text: "We are working on the TestFlight launch this week."),
            assistantMessage: JarvisChatMessage(role: .assistant, text: "I can help with the TestFlight launch checklist."),
            task: .analyzeText,
            classification: JarvisTaskClassification(
                category: .planning,
                task: .analyzeText,
                preset: .balanced,
                confidence: 0.8,
                reasoningHint: "Organize the work into concrete actions.",
                responseHint: "Use a checklist.",
                shouldInjectKnowledge: false,
                shouldPreferStructuredOutput: true
            )
        )

        let conversation = JarvisConversationRecord(
            id: conversationID,
            title: "Launch",
            messages: [
                JarvisChatMessage(role: .user, text: "I prefer concise plans for the release project."),
                JarvisChatMessage(role: .assistant, text: "I will keep plans short and action-oriented."),
                JarvisChatMessage(role: .user, text: "We are working on the TestFlight launch this week."),
                JarvisChatMessage(role: .assistant, text: "I can help with the TestFlight launch checklist.")
            ]
        )

        let context = manager.prepareContext(
            conversation: conversation,
            prompt: "Create the project launch checklist",
            task: .analyzeText,
            taskBudget: 4
        )

        XCTAssertNotNil(context.summary)
        XCTAssertFalse(context.retrievedMemories.isEmpty)
        XCTAssertTrue(context.memoryLabels.contains("User Preference") || context.memoryLabels.contains("Project Context"))
    }

    func testAssistantOutputFormatterCreatesChecklistCard() {
        let output = JarvisAssistantOutputFormatter.format(
            text: """
            Here is the rollout plan.

            1. Confirm the build number.
            2. Upload release notes.
            3. Validate TestFlight testers.
            """,
            classification: JarvisTaskClassification(
                category: .planning,
                task: .analyzeText,
                preset: .balanced,
                confidence: 0.9,
                reasoningHint: "Organize the work.",
                responseHint: "Use steps.",
                shouldInjectKnowledge: false,
                shouldPreferStructuredOutput: true
            ),
            memoryContext: MemoryContext()
        )

        XCTAssertEqual(output?.cards.first?.kind, .checklist)
        XCTAssertEqual(output?.cards.first?.items.count, 3)
    }

    func testGemmaProjectorAttachmentPersistsCompanionMetadata() throws {
        let suffix = UUID().uuidString
        let library = JarvisModelLibrary(payloadFilename: "JarvisModelLibrary-\(suffix).json")
        let modelURL = try temporarySparseGGUFURL(
            named: "gemma-3-4b-it-q4_0",
            size: 3_400_000_000
        )
        let projectorURL = try temporarySparseGGUFURL(
            named: "mmproj-model-f16-4B",
            size: 200_000_000
        )

        let imported = try library.importModel(from: modelURL)
        let updated = try library.attachProjector(from: projectorURL, to: imported.id)

        XCTAssertTrue(updated.hasProjectorAttached)
        XCTAssertEqual(updated.projectorAsset?.storageKind, .sandboxCopy)
    }

    func testAssistantIntelligenceClassifiesSummarization() {
        let classification = JarvisAssistantIntelligence.classify(
            prompt: "Summarize this meeting transcript into key decisions.",
            requestedTask: .chat,
            context: JarvisAssistantTaskContext(task: .chat, source: "test"),
            conversation: JarvisConversationRecord()
        )

        XCTAssertEqual(classification.category, .summarization)
        XCTAssertEqual(classification.task, .summarize)
        XCTAssertEqual(classification.preset, .precise)
    }

    func testAssistantIntelligenceClassifiesCoding() {
        let classification = JarvisAssistantIntelligence.classify(
            prompt: "Debug this Swift compile error and suggest the smallest fix.",
            requestedTask: .chat,
            context: JarvisAssistantTaskContext(task: .chat, source: "test"),
            conversation: JarvisConversationRecord()
        )

        XCTAssertEqual(classification.category, .coding)
        XCTAssertEqual(classification.preset, .coding)
        XCTAssertTrue(classification.shouldPreferStructuredOutput)
    }

    func testPreciseTuningEnablesGroundedReasoningGuards() {
        let classification = JarvisTaskClassification(
            category: .questionAnswering,
            task: .knowledgeAnswer,
            preset: .precise,
            confidence: 0.9,
            reasoningHint: "Ground the answer.",
            responseHint: "Answer directly.",
            shouldInjectKnowledge: true,
            shouldPreferStructuredOutput: false
        )

        let tuning = JarvisAssistantIntelligence.tuning(
            for: classification,
            settings: .default
        )

        XCTAssertEqual(tuning.preset, .precise)
        XCTAssertTrue(tuning.requiresGroundedAnswers)
        XCTAssertTrue(tuning.usesReasoningPlan)
        XCTAssertLessThanOrEqual(tuning.temperature, 0.36)
    }

    func testRecentHistoryPreservesLatestInstructionLikeMessage() {
        let history = [
            JarvisChatMessage(role: .user, text: "Use bullet points and keep it short."),
            JarvisChatMessage(role: .assistant, text: "Understood."),
            JarvisChatMessage(role: .user, text: String(repeating: "Long context ", count: 80)),
            JarvisChatMessage(role: .assistant, text: "Working on it."),
            JarvisChatMessage(role: .user, text: "What's the shortest plan?")
        ]

        let trimmed = JarvisAssistantIntelligence.recentHistory(from: history, budget: 280)

        XCTAssertTrue(trimmed.contains(where: { $0.text.contains("Use bullet points") }))
        XCTAssertTrue(trimmed.contains(where: { $0.text.contains("What's the shortest plan?") }))
        XCTAssertTrue(trimmed.allSatisfy { $0.text.count <= 420 })
    }

    func testLimitedKnowledgePrioritizesHigherScoringResults() {
        let lowScore = JarvisKnowledgeResult(
            item: JarvisKnowledgeItem(title: "Low", text: "A", source: "test"),
            score: 0.41,
            snippet: String(repeating: "low ", count: 80)
        )
        let highScore = JarvisKnowledgeResult(
            item: JarvisKnowledgeItem(title: "High", text: "B", source: "test"),
            score: 0.93,
            snippet: "high signal snippet"
        )

        let results = JarvisAssistantIntelligence.limitedKnowledge(
            from: [lowScore, highScore],
            maxCharacters: 80
        )

        XCTAssertEqual(results.first?.item.title, "High")
    }

    func testDeviceTierSelectionFavorsHighMemoryPhones() {
        XCTAssertEqual(JarvisRuntimeDeviceTier.current(physicalMemoryBytes: 6_500_000_000), .constrained)
        XCTAssertEqual(JarvisRuntimeDeviceTier.current(physicalMemoryBytes: 8_000_000_000), .baseline)
        XCTAssertEqual(JarvisRuntimeDeviceTier.current(physicalMemoryBytes: 12_000_000_000), .high)
    }

    func testStreamingTextProcessorFlushesSentenceBoundaries() {
        var processor = JarvisStreamingTextProcessor()

        XCTAssertNil(processor.ingest("Hello"))
        let flushed = processor.ingest(", world.")

        XCTAssertEqual(flushed, "Hello, world.")
        XCTAssertNil(processor.finish())
    }

    func testAssistantSuggestionsReflectTaskCategory() {
        let suggestions = JarvisAssistantIntelligence.suggestions(
            for: JarvisTaskClassification(
                category: .coding,
                task: .analyzeText,
                preset: .coding,
                confidence: 0.9,
                reasoningHint: "reason",
                responseHint: "respond",
                shouldInjectKnowledge: false,
                shouldPreferStructuredOutput: true
            ),
            latestAssistantText: "Try moving the state update onto the main actor."
        )

        XCTAssertTrue(suggestions.contains(where: { $0.title == "Add Tests" }))
        XCTAssertTrue(suggestions.contains(where: { $0.title == "Summarize" }))
    }

    func testOrchestrationRequestNormalizesInvocationMetadata() {
        let conversation = JarvisConversationRecord()
        let request = JarvisOrchestrationRequest(
            prompt: "Plan my week",
            task: .chat,
            source: JarvisAssistantEntrySource.shortcut.rawValue,
            sourceKind: .shortcut,
            mode: .plan,
            conversation: conversation,
            routeContext: JarvisAssistantRouteContext(
                tabIdentifier: "assistant",
                entryRouteIdentifier: JarvisAssistantEntryRoute.chat.rawValue,
                entryStyleIdentifier: "quickAsk",
                isFocusedExperience: true,
                shouldFocusComposer: false
            ),
            executionPreferences: JarvisAssistantExecutionPreferences(
                preferredDeliveryMode: .streamingText,
                prefersStructuredOutput: true,
                allowCapabilityExecution: true,
                allowMemoryAugmentation: true
            )
        )

        let normalized = request.normalizedRequest
        XCTAssertEqual(normalized.invocationSource, JarvisAssistantEntrySource.shortcut.rawValue)
        XCTAssertEqual(normalized.sourceKind, .shortcut)
        XCTAssertEqual(normalized.assistantMode, .plan)
        XCTAssertEqual(normalized.conversationID, conversation.id)
        XCTAssertEqual(normalized.routeContext.entryStyleIdentifier, "quickAsk")
        XCTAssertTrue(normalized.routeContext.isFocusedExperience)
        XCTAssertEqual(normalized.executionPreferences.prefersStructuredOutput, true)
    }

    @MainActor
    func testExecutionPlannerChoosesClarifyForShortAmbiguousPrompt() async {
        let planner = JarvisExecutionPlanner()
        let request = JarvisNormalizedAssistantRequest(
            prompt: "Help?",
            requestedTask: .chat,
            invocationSource: JarvisAssistantEntrySource.inApp.rawValue,
            sourceKind: .chat,
            assistantMode: .general,
            conversationID: UUID(),
            conversation: JarvisConversationRecord(),
            routeContext: JarvisAssistantRouteContext()
        )
        let classification = JarvisTaskClassification(
            category: .generalChat,
            task: .chat,
            preset: .balanced,
            confidence: 0.4,
            reasoningHint: "General request",
            responseHint: "Respond directly",
            shouldInjectKnowledge: false,
            shouldPreferStructuredOutput: false
        )

        let plan = await planner.makePlan(
            for: request,
            classification: classification,
            memoryContextAvailable: false
        )

        XCTAssertEqual(plan.mode, .clarify)
        XCTAssertEqual(plan.steps.first?.kind, .normalizeRequest)
        XCTAssertTrue(plan.diagnostics.reasoning.joined(separator: " ").contains("clarify"))
    }

    @MainActor
    func testExecutionPlannerChoosesMemoryAugmentedResponseWhenHistoryExists() async {
        let planner = JarvisExecutionPlanner()
        let conversation = JarvisConversationRecord(
            messages: [
                JarvisChatMessage(role: .user, text: "Here is some background."),
                JarvisChatMessage(role: .assistant, text: "Understood.")
            ]
        )
        let request = JarvisNormalizedAssistantRequest(
            prompt: "Continue",
            requestedTask: .chat,
            invocationSource: JarvisAssistantEntrySource.inApp.rawValue,
            sourceKind: .chat,
            assistantMode: .general,
            conversationID: conversation.id,
            conversation: conversation,
            routeContext: JarvisAssistantRouteContext()
        )
        let classification = JarvisTaskClassification.default

        let plan = await planner.makePlan(
            for: request,
            classification: classification,
            memoryContextAvailable: true
        )

        XCTAssertEqual(plan.mode, .memoryAugmentedResponse)
        XCTAssertTrue(plan.steps.contains(where: { $0.kind == .consultMemory }))
        XCTAssertTrue(plan.diagnostics.memoryAugmentationAvailable)
    }

    @MainActor
    private func makeAppModel() -> JarvisPhoneAppModel {
        let suffix = UUID().uuidString
        let defaults = UserDefaults(suiteName: "JarvisIOSTests.\(suffix)")!
        defaults.removePersistentDomain(forName: "JarvisIOSTests.\(suffix)")

        return JarvisPhoneAppModel(
            store: JarvisConversationStore(filename: "JarvisPhoneStore-\(suffix).json"),
            modelLibrary: JarvisModelLibrary(payloadFilename: "JarvisModelLibrary-\(suffix).json"),
            launchStore: JarvisLaunchRouteStore(defaults: defaults),
            settingsStore: JarvisAssistantSettingsStore(defaults: defaults)
        )
    }

    private func temporaryGGUFURL(named name: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(name).gguf")
        try Data("GGUF".utf8).write(to: url, options: [.atomic])
        return url
    }

    private func temporarySparseGGUFURL(named name: String, size: Int64) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString)-\(name).gguf")
        FileManager.default.createFile(atPath: url.path, contents: nil)
        let handle = try FileHandle(forWritingTo: url)
        try handle.write(contentsOf: Data("GGUF".utf8))
        try handle.truncate(atOffset: UInt64(max(size, 4)))
        try handle.close()
        return url
    }
}

private final class TestGGUFEngine: JarvisGGUFEngine {
    var name: String { "test-engine" }
    var isInstalled: Bool { true }
    var capability: JarvisGGUFEngineCapability { .fullInference }
    var supportsVisualInputs: Bool { false }

    private(set) var loadCount = 0
    private(set) var loadedPath: String?
    private(set) var loadedProjectorPath: String?
    private var configuration = JarvisRuntimeConfiguration()

    func updateConfiguration(_ configuration: JarvisRuntimeConfiguration) {
        self.configuration = configuration
    }

    func updateGenerationTuning(_ tuning: JarvisGenerationTuning?) {
        _ = tuning
    }

    func loadModel(at path: String, projectorPath: String?) async throws {
        loadCount += 1
        loadedPath = path
        loadedProjectorPath = projectorPath
    }

    func unloadModel() async {
        loadedPath = nil
        loadedProjectorPath = nil
    }

    func generate(request: JarvisAssistantRequest, onToken: @escaping @Sendable (String) -> Void) async throws {
        _ = request
        _ = configuration
        onToken("ok")
    }

    func cancelGeneration() {}
}
