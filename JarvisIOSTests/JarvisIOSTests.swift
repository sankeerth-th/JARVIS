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
            assistantQualityMode: .highQuality,
            promptMode: .advanced,
            memoryEnabled: false,
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
        let raw = try XCTUnwrap(defaults.data(forKey: "jarvis.ios.assistant.settings"))
        XCTAssertNil(try? JSONDecoder().decode(JarvisAssistantSettings.self, from: raw))
    }

    func testConversationStorePersistsEncryptedPayload() throws {
        let filename = "JarvisPhoneStore-\(UUID().uuidString).json"
        let store = JarvisConversationStore(filename: filename)
        let record = JarvisConversationRecord(
            id: UUID(),
            title: "Sensitive",
            messages: [
                JarvisConversationMessageRecord(role: .user, text: "my email is jarvis@example.com and token=abcd1234")
            ],
            createdAt: Date(),
            updatedAt: Date()
        )

        store.saveConversation(record)

        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let fileURL = appSupport
            .appendingPathComponent("JarvisPhone", isDirectory: true)
            .appendingPathComponent(filename)
        let data = try Data(contentsOf: fileURL)

        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("jarvis@example.com"))
        XCTAssertEqual(store.loadConversations().first?.messages.first?.text, "my email is jarvis@example.com and token=abcd1234")
    }

    func testConversationStoreDropsBlankStreamingAssistantPlaceholder() {
        let filename = "JarvisPhoneStore-\(UUID().uuidString).json"
        let store = JarvisConversationStore(filename: filename)
        let conversation = JarvisConversationRecord(
            title: "Transient",
            messages: [
                JarvisConversationMessageRecord(role: .user, text: "Hello"),
                JarvisConversationMessageRecord(role: .assistant, text: "", isStreaming: true)
            ]
        )

        store.saveConversation(conversation)

        let loaded = store.loadConversations().first
        XCTAssertEqual(loaded?.messages.count, 1)
        XCTAssertEqual(loaded?.messages.first?.role, .user)
    }

    func testIOSSecurityRedactorRemovesSensitivePatterns() {
        let output = JarvisIOSSecurityRedactor.redact("contact me at jarvis@example.com or +1 312-555-1212")
        XCTAssertFalse(output.contains("jarvis@example.com"))
        XCTAssertFalse(output.contains("312-555-1212"))
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
        XCTAssertEqual(appModel.assistantEntryStyle, .quickAsk)
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
            classification: JarvisTaskClassification(
                category: .planning,
                task: .analyzeText,
                preset: .balanced,
                confidence: 0.8,
                reasoningHint: "Organize the work into concrete actions.",
                responseHint: "Use a checklist.",
                shouldInjectKnowledge: false,
                shouldPreferStructuredOutput: true
            ),
            skill: JarvisResolvedSkill(
                skill: JarvisSkillCatalog.resolve(
                    for: JarvisNormalizedAssistantRequest(
                        prompt: "Create the project launch checklist",
                        requestedTask: .analyzeText,
                        invocationSource: "test",
                        sourceKind: .chat,
                        assistantMode: .plan,
                        conversationID: conversationID,
                        conversation: conversation,
                        routeContext: JarvisAssistantRouteContext()
                    ),
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
                ),
                policy: JarvisSkillContextPolicy(
                    recentMessageLimit: 4,
                    includeSummary: true,
                    knowledgeLimit: 1,
                    maxMemoryItems: 3,
                    maxMemoryCharacters: 360,
                    includeReplyTarget: false
                )
            ),
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

    @MainActor
    func testMemoryWriteFilteringIgnoresTrivialConversation() {
        let store = JarvisMemoryStore(filename: "JarvisMemoryFilter-\(UUID().uuidString).json")
        store.clearAll()
        let manager = ConversationMemoryManager(store: store)

        let conversationID = UUID()
        manager.recordInteraction(
            conversationID: conversationID,
            userMessage: JarvisChatMessage(role: .user, text: "Thanks"),
            assistantMessage: JarvisChatMessage(role: .assistant, text: "You're welcome."),
            task: .chat,
            classification: .default
        )

        let matches = store.searchMemories(query: "thanks", conversationID: conversationID, limit: 5)
        XCTAssertTrue(matches.isEmpty)
    }

    @MainActor
    func testEntityExtractionImprovesRetrieval() {
        let store = JarvisMemoryStore(filename: "JarvisMemoryEntity-\(UUID().uuidString).json")
        store.clearAll()
        let manager = ConversationMemoryManager(store: store)

        let conversationID = UUID()
        manager.recordInteraction(
            conversationID: conversationID,
            userMessage: JarvisChatMessage(role: .user, text: "I am building Jarvis in SwiftUI for iOS."),
            assistantMessage: JarvisChatMessage(role: .assistant, text: "I can help with the Jarvis SwiftUI iOS work."),
            task: .chat,
            classification: .default
        )

        let matches = store.searchMemories(query: "swiftui ios jarvis", conversationID: nil, limit: 5)
        XCTAssertFalse(matches.isEmpty)
        XCTAssertTrue(matches.first?.record.entityHints.contains("swiftui") == true)
    }

    func testSkillCapabilityProviderMatchesDraftEmailIntent() async {
        let provider = JarvisSkillCapabilityProvider()
        let request = JarvisNormalizedAssistantRequest(
            prompt: "Draft an email to the team about the release delay.",
            requestedTask: .draftEmail,
            invocationSource: "test",
            sourceKind: .chat,
            assistantMode: .write,
            conversationID: UUID(),
            conversation: JarvisConversationRecord(),
            routeContext: JarvisAssistantRouteContext()
        )

        let candidates = await provider.candidates(
            for: request,
            classification: JarvisTaskClassification(
                category: .draftingEmail,
                task: .draftEmail,
                preset: .drafting,
                confidence: 0.9,
                reasoningHint: "Draft the email.",
                responseHint: "Make it send-ready.",
                shouldInjectKnowledge: false,
                shouldPreferStructuredOutput: true
            )
        )

        XCTAssertTrue(candidates.contains { $0.name == "draft_email" })
    }

    func testSkillResolverPrefersPlanningSkillForPlanningClassification() {
        let request = JarvisNormalizedAssistantRequest(
            prompt: "Create a launch checklist for the Jarvis release.",
            requestedTask: .analyzeText,
            invocationSource: "test",
            sourceKind: .chat,
            assistantMode: .plan,
            conversationID: UUID(),
            conversation: JarvisConversationRecord(),
            routeContext: JarvisAssistantRouteContext()
        )

        let classification = JarvisTaskClassification(
            category: .planning,
            task: .analyzeText,
            preset: .balanced,
            confidence: 0.9,
            reasoningHint: "Organize the work.",
            responseHint: "Use steps.",
            shouldInjectKnowledge: false,
            shouldPreferStructuredOutput: true
        )

        let resolved = JarvisSkillPolicyResolver.resolve(for: request, classification: classification)
        XCTAssertEqual(resolved.skill.id, "planning")
        XCTAssertEqual(resolved.policy.maxMemoryItems, 4)
    }

    func testTaskAwareMemoryRankingPrefersProjectForCoding() {
        let store = JarvisMemoryStore(filename: "JarvisTaskAwareMemory-\(UUID().uuidString).json")
        store.clearAll()

        store.upsertMemory(
            JarvisMemoryRecord(
                kind: .project,
                title: "Jarvis project",
                content: "Jarvis uses SwiftUI and local GGUF models for iOS assistant work.",
                importance: 0.9,
                confidence: 0.9,
                tags: ["jarvis", "swiftui", "ios"],
                entityHints: ["jarvis", "swiftui", "ios"]
            ),
            maxCount: 20
        )
        store.upsertMemory(
            JarvisMemoryRecord(
                kind: .personalFact,
                title: "Personal fact",
                content: "I work from home on weekdays.",
                importance: 0.7,
                confidence: 0.8,
                tags: ["home"]
            ),
            maxCount: 20
        )

        let classification = JarvisTaskClassification(
            category: .coding,
            task: .analyzeText,
            preset: .coding,
            confidence: 0.9,
            reasoningHint: "Fix the code issue.",
            responseHint: "Lead with the fix.",
            shouldInjectKnowledge: false,
            shouldPreferStructuredOutput: true
        )
        let request = JarvisNormalizedAssistantRequest(
            prompt: "Fix the SwiftUI assistant view in Jarvis.",
            requestedTask: .analyzeText,
            invocationSource: "test",
            sourceKind: .chat,
            assistantMode: .code,
            conversationID: UUID(),
            conversation: JarvisConversationRecord(),
            routeContext: JarvisAssistantRouteContext()
        )
        let skill = JarvisSkillCatalog.resolve(for: request, classification: classification)

        let matches = store.searchMemories(
            query: request.prompt,
            conversationID: request.conversationID,
            limit: 3,
            classification: classification,
            skill: skill
        )

        XCTAssertEqual(matches.first?.record.kind, .project)
    }

    func testContextBuilderPacksDraftContextSelectively() {
        let builder = ContextBuilder()
        let request = JarvisOrchestrationRequest(
            prompt: "Draft a short email to the team about the delay.",
            task: .draftEmail,
            source: "test",
            mode: .write,
            conversation: JarvisConversationRecord(
                messages: [
                    JarvisChatMessage(role: .user, text: "Keep my emails direct."),
                    JarvisChatMessage(role: .assistant, text: "Understood."),
                    JarvisChatMessage(role: .user, text: "Draft a short email to the team about the delay.")
                ]
            ),
            replyTargetText: "Team update thread"
        )
        let classification = JarvisTaskClassification(
            category: .draftingEmail,
            task: .draftEmail,
            preset: .drafting,
            confidence: 0.9,
            reasoningHint: "Draft the email.",
            responseHint: "Make it send-ready.",
            shouldInjectKnowledge: false,
            shouldPreferStructuredOutput: true
        )
        let resolved = JarvisSkillPolicyResolver.resolve(for: request.normalizedRequest, classification: classification)
        let summary = ConversationSummary(
            conversationID: request.conversation.id,
            messageCount: 4,
            summaryText: "User prefers direct updates.",
            keyTopics: ["email"],
            userIntent: "drafting",
            assistantActions: ["drafted content"]
        )
        let context = builder.build(
            request: request,
            classification: classification,
            memoryContext: MemoryContext(
                recentMessages: request.conversation.messages,
                summary: summary
            ),
            resolvedSkill: resolved
        )

        XCTAssertTrue(context.taskInstruction.contains("Skill: Draft Email"))
        XCTAssertTrue(context.contextBlocks.contains { $0.title == "Reply Target" })
        XCTAssertTrue(context.contextBlocks.contains { $0.title == "Conversation Context" })
    }

    func testSummaryIncludesGoalsTasksAndActions() {
        let store = JarvisMemoryStore(filename: "JarvisSummaryGoals-\(UUID().uuidString).json")
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
            userMessage: JarvisChatMessage(role: .user, text: "Our goal is to ship Jarvis this month."),
            assistantMessage: JarvisChatMessage(role: .assistant, text: "I can turn that into launch steps."),
            task: .analyzeText,
            classification: JarvisTaskClassification(
                category: .planning,
                task: .analyzeText,
                preset: .balanced,
                confidence: 0.9,
                reasoningHint: "Plan the launch.",
                responseHint: "Use steps.",
                shouldInjectKnowledge: false,
                shouldPreferStructuredOutput: true
            )
        )
        manager.recordInteraction(
            conversationID: conversationID,
            userMessage: JarvisChatMessage(role: .user, text: "We need to finalize TestFlight and follow up with QA."),
            assistantMessage: JarvisChatMessage(role: .assistant, text: "Next I will outline the QA checklist and ask which release date to target."),
            task: .analyzeText,
            classification: JarvisTaskClassification(
                category: .planning,
                task: .analyzeText,
                preset: .balanced,
                confidence: 0.9,
                reasoningHint: "Plan the launch.",
                responseHint: "Use steps.",
                shouldInjectKnowledge: false,
                shouldPreferStructuredOutput: true
            )
        )

        let summary = store.latestSummary(for: conversationID)
        XCTAssertTrue(summary?.summaryText.contains("Open tasks:") == true)
        XCTAssertTrue(summary?.summaryText.contains("Jarvis actions:") == true)
    }

    func testKnowledgeFormatterCreatesKnowledgeAnswerCard() {
        let output = JarvisAssistantOutputFormatter.format(
            text: "Jarvis stores notes locally and retrieves the most relevant ones for grounded answers.",
            classification: JarvisTaskClassification(
                category: .questionAnswering,
                task: .knowledgeAnswer,
                preset: .precise,
                confidence: 0.9,
                reasoningHint: "Ground the answer.",
                responseHint: "Answer directly.",
                shouldInjectKnowledge: true,
                shouldPreferStructuredOutput: true
            ),
            memoryContext: MemoryContext()
        )

        XCTAssertEqual(output?.cards.first?.kind, .knowledgeAnswer)
    }

    func testGreetingDoesNotCreateDraftCard() {
        let output = JarvisAssistantOutputFormatter.format(
            text: "Hello",
            classification: JarvisTaskClassification(
                category: .draftingEmail,
                task: .draftEmail,
                preset: .drafting,
                confidence: 0.9,
                reasoningHint: "Draft the email.",
                responseHint: "Make it send-ready.",
                shouldInjectKnowledge: false,
                shouldPreferStructuredOutput: true
            ),
            memoryContext: MemoryContext(),
            skill: JarvisSkillCatalog.all.first { $0.id == "draft_email" }
        )

        XCTAssertNil(output)
    }

    func testSinglePeriodDoesNotCreateCodeCard() {
        let output = JarvisAssistantOutputFormatter.format(
            text: ".",
            classification: JarvisTaskClassification(
                category: .coding,
                task: .analyzeText,
                preset: .coding,
                confidence: 0.9,
                reasoningHint: "Fix the code issue.",
                responseHint: "Lead with the fix.",
                shouldInjectKnowledge: false,
                shouldPreferStructuredOutput: true
            ),
            memoryContext: MemoryContext(),
            skill: JarvisSkillCatalog.all.first { $0.id == "code_generation" }
        )

        XCTAssertNil(output)
    }

    func testEmptyTextCreatesNoStructuredOutput() {
        let output = JarvisAssistantOutputFormatter.format(
            text: "   ",
            classification: .default,
            memoryContext: MemoryContext()
        )

        XCTAssertNil(output)
    }

    func testWeakDraftLikeTextFallsBackToPlainText() {
        let output = JarvisAssistantOutputFormatter.format(
            text: "Thanks.",
            classification: JarvisTaskClassification(
                category: .draftingMessage,
                task: .reply,
                preset: .drafting,
                confidence: 0.9,
                reasoningHint: "Draft the reply.",
                responseHint: "Make it send-ready.",
                shouldInjectKnowledge: false,
                shouldPreferStructuredOutput: true
            ),
            memoryContext: MemoryContext(),
            skill: JarvisSkillCatalog.all.first { $0.id == "draft_message" }
        )

        XCTAssertNil(output)
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
        XCTAssertEqual(tuning.temperature, 0.45, accuracy: 0.001)
        XCTAssertEqual(tuning.topP, 0.88, accuracy: 0.001)
        XCTAssertEqual(tuning.maxOutputTokens, 200)
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
        XCTAssertEqual(JarvisRuntimeDeviceTier.current(physicalMemoryBytes: 12_000_000_000), .highMemory)
    }

    func testMemoryPressureLevelThresholds() {
        XCTAssertEqual(JarvisRuntimeMemoryPressureLevel.current(availableMemoryBytes: 1_500_000_000), .normal)
        XCTAssertEqual(JarvisRuntimeMemoryPressureLevel.current(availableMemoryBytes: 1_000_000_000), .reduced)
        XCTAssertEqual(JarvisRuntimeMemoryPressureLevel.current(availableMemoryBytes: 800_000_000), .critical)
    }

    func testKVContextBudgetHeuristicMatchesTierBudgetAssumptions() {
        XCTAssertEqual(
            JarvisRuntimeHeuristics.maxContextTokens(fileSizeBytes: 3_400_000_000, kvBudgetMB: 1_200),
            1_200
        )
        XCTAssertEqual(
            JarvisRuntimeHeuristics.maxContextTokens(fileSizeBytes: 2_500_000_000, kvBudgetMB: 1_200),
            1_600
        )
        XCTAssertEqual(
            JarvisRuntimeHeuristics.maxContextTokens(fileSizeBytes: 1_900_000_000, kvBudgetMB: 768),
            1_536
        )
    }

    func testEstimatedKVCacheBytesScalesWithContext() {
        let small = JarvisRuntimeHeuristics.estimatedKVCacheBytes(
            contextTokens: 512,
            fileSizeBytes: 3_400_000_000
        )
        let large = JarvisRuntimeHeuristics.estimatedKVCacheBytes(
            contextTokens: 1_024,
            fileSizeBytes: 3_400_000_000
        )

        XCTAssertEqual(small, 512_000_000)
        XCTAssertEqual(large, 1_024_000_000)
        XCTAssertGreaterThan(large, small)
    }

    func testGPULayerTargetsRespectTierAndPressure() {
        XCTAssertEqual(
            JarvisRuntimeHeuristics.gpuLayerTarget(
                for: .constrained,
                performanceProfile: .balanced,
                memoryPressure: .normal,
                batterySaverMode: false,
                thermalState: .nominal
            ),
            12
        )
        XCTAssertEqual(
            JarvisRuntimeHeuristics.gpuLayerTarget(
                for: .baseline,
                performanceProfile: .quality,
                memoryPressure: .normal,
                batterySaverMode: false,
                thermalState: .nominal
            ),
            48
        )
        XCTAssertEqual(
            JarvisRuntimeHeuristics.gpuLayerTarget(
                for: .highMemory,
                performanceProfile: .balanced,
                memoryPressure: .reduced,
                batterySaverMode: false,
                thermalState: .nominal
            ),
            48
        )
    }

    func testFlashAttentionOnlyEnablesOnStableHighMemoryTier() {
        XCTAssertTrue(
            JarvisRuntimeHeuristics.shouldEnableFlashAttention(
                for: .highMemory,
                performanceProfile: .balanced,
                memoryPressure: .normal,
                batterySaverMode: false,
                thermalState: .nominal
            )
        )
        XCTAssertFalse(
            JarvisRuntimeHeuristics.shouldEnableFlashAttention(
                for: .baseline,
                performanceProfile: .quality,
                memoryPressure: .normal,
                batterySaverMode: false,
                thermalState: .nominal
            )
        )
        XCTAssertFalse(
            JarvisRuntimeHeuristics.shouldEnableFlashAttention(
                for: .highMemory,
                performanceProfile: .balanced,
                memoryPressure: .reduced,
                batterySaverMode: false,
                thermalState: .nominal
            )
        )
    }

    func testMicroBatchSizingStaysSmallerThanLogicalBatch() {
        XCTAssertEqual(
            JarvisRuntimeHeuristics.microBatchSize(
                for: 20,
                deviceTier: .highMemory,
                memoryPressure: .normal,
                thermalState: .nominal
            ),
            12
        )
        XCTAssertEqual(
            JarvisRuntimeHeuristics.microBatchSize(
                for: 12,
                deviceTier: .baseline,
                memoryPressure: .reduced,
                thermalState: .nominal
            ),
            8
        )
    }

    func testRuntimeRepetitionGuardDetectsRepeatedSuffixPatterns() {
        let repeated = "final answer " + String(repeating: "repeat this phrase ", count: 3)
        XCTAssertTrue(
            JarvisRuntimeHeuristics.repeatedSuffixDetected(
                in: repeated,
                windowCharacters: 64,
                threshold: 3
            )
        )

        XCTAssertFalse(
            JarvisRuntimeHeuristics.repeatedSuffixDetected(
                in: "Here is one concise explanation with no looping pattern at the end.",
                windowCharacters: 64,
                threshold: 3
            )
        )
    }

    func testRuntimeRepetitionGuardDetectsRepeatedPhraseWindows() {
        XCTAssertTrue(
            JarvisRuntimeHeuristics.repeatedPhraseDetected(
                in: "alpha beta gamma alpha beta gamma alpha beta gamma",
                threshold: 3
            )
        )
        XCTAssertFalse(
            JarvisRuntimeHeuristics.repeatedPhraseDetected(
                in: "alpha beta gamma delta epsilon zeta",
                threshold: 3
            )
        )
    }

    func testRuntimeStopReasonRawValuesRemainStable() {
        XCTAssertEqual(JarvisRuntimeGenerationStopReason.eos.rawValue, "eos")
        XCTAssertEqual(JarvisRuntimeGenerationStopReason.stopSequence.rawValue, "stop_sequence")
        XCTAssertEqual(JarvisRuntimeGenerationStopReason.maxTokens.rawValue, "max_tokens")
        XCTAssertEqual(JarvisRuntimeGenerationStopReason.repetitionAbort.rawValue, "repetition_abort")
        XCTAssertEqual(JarvisRuntimeGenerationStopReason.thermalAbort.rawValue, "thermal_abort")
        XCTAssertEqual(JarvisRuntimeGenerationStopReason.memoryAbort.rawValue, "memory_abort")
        XCTAssertEqual(JarvisRuntimeGenerationStopReason.externalCancel.rawValue, "external_cancel")
        XCTAssertEqual(JarvisRuntimeGenerationStopReason.validationFailure.rawValue, "validation_failure")
    }

    func testOutputValidatorRejectsPunctuationOnlyCodingOutput() {
        let classification = JarvisTaskClassification(
            category: .coding,
            task: .analyzeText,
            preset: .coding,
            confidence: 0.9,
            reasoningHint: "reason",
            responseHint: "respond",
            shouldInjectKnowledge: false,
            shouldPreferStructuredOutput: true
        )

        let result = JarvisAssistantOutputValidator.validate(
            text: ".",
            classification: classification
        )

        XCTAssertEqual(result.status, .punctuationOnly)
        XCTAssertFalse(result.isValid)
    }

    func testOutputValidatorRejectsCodingAnswerWithoutCodeStructure() {
        let classification = JarvisTaskClassification(
            category: .coding,
            task: .analyzeText,
            preset: .coding,
            confidence: 0.9,
            reasoningHint: "reason",
            responseHint: "respond",
            shouldInjectKnowledge: false,
            shouldPreferStructuredOutput: true
        )

        let result = JarvisAssistantOutputValidator.validate(
            text: "Use a better approach soon",
            classification: classification
        )

        XCTAssertEqual(result.status, .missingCodeStructure)
        XCTAssertFalse(result.isValid)
    }

    func testOutputValidatorAcceptsCodeLikeCodingAnswer() {
        let classification = JarvisTaskClassification(
            category: .coding,
            task: .analyzeText,
            preset: .coding,
            confidence: 0.9,
            reasoningHint: "reason",
            responseHint: "respond",
            shouldInjectKnowledge: false,
            shouldPreferStructuredOutput: true
        )

        let result = JarvisAssistantOutputValidator.validate(
            text: "```swift\nlet value = 1\n```",
            classification: classification
        )

        XCTAssertEqual(result.status, .passed)
        XCTAssertTrue(result.isValid)
    }

    func testHighValueRetryTaskSelectionMatchesPolicies() {
        XCTAssertTrue(
            JarvisAssistantOutputValidator.isHighValueRetryTask(
                JarvisTaskClassification(
                    category: .coding,
                    task: .analyzeText,
                    preset: .coding,
                    confidence: 0.9,
                    reasoningHint: "reason",
                    responseHint: "respond",
                    shouldInjectKnowledge: false,
                    shouldPreferStructuredOutput: true
                )
            )
        )
        XCTAssertTrue(
            JarvisAssistantOutputValidator.isHighValueRetryTask(
                JarvisTaskClassification(
                    category: .planning,
                    task: .chat,
                    preset: .balanced,
                    confidence: 0.9,
                    reasoningHint: "reason",
                    responseHint: "respond",
                    shouldInjectKnowledge: false,
                    shouldPreferStructuredOutput: true
                )
            )
        )
        XCTAssertFalse(
            JarvisAssistantOutputValidator.isHighValueRetryTask(
                JarvisTaskClassification(
                    category: .questionAnswering,
                    task: .knowledgeAnswer,
                    preset: .precise,
                    confidence: 0.9,
                    reasoningHint: "reason",
                    responseHint: "respond",
                    shouldInjectKnowledge: true,
                    shouldPreferStructuredOutput: false
                )
            )
        )
    }

    func testTaskPresetCapsMatchAssistantPolicies() {
        let coding = JarvisAssistantIntelligence.tuning(
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
            settings: .default
        )
        XCTAssertEqual(coding.temperature, 0.20, accuracy: 0.001)
        XCTAssertEqual(coding.topP, 0.85, accuracy: 0.001)
        XCTAssertEqual(coding.penaltyLastN, 128)
        XCTAssertEqual(coding.maxOutputTokens, 400)

        let summarization = JarvisAssistantIntelligence.tuning(
            for: JarvisTaskClassification(
                category: .summarization,
                task: .summarize,
                preset: .precise,
                confidence: 0.9,
                reasoningHint: "summarize",
                responseHint: "faithful",
                shouldInjectKnowledge: false,
                shouldPreferStructuredOutput: true
            ),
            settings: .default
        )
        XCTAssertEqual(summarization.maxOutputTokens, 300)
        XCTAssertEqual(summarization.repeatPenalty, 1.16, accuracy: 0.001)

        let questionAnswering = JarvisAssistantIntelligence.tuning(
            for: JarvisTaskClassification(
                category: .questionAnswering,
                task: .knowledgeAnswer,
                preset: .precise,
                confidence: 0.9,
                reasoningHint: "answer",
                responseHint: "direct",
                shouldInjectKnowledge: true,
                shouldPreferStructuredOutput: false
            ),
            settings: .default
        )
        XCTAssertEqual(questionAnswering.maxOutputTokens, 200)
        XCTAssertEqual(questionAnswering.topP, 0.88, accuracy: 0.001)

        let planning = JarvisAssistantIntelligence.tuning(
            for: JarvisTaskClassification(
                category: .planning,
                task: .analyzeText,
                preset: .balanced,
                confidence: 0.9,
                reasoningHint: "plan",
                responseHint: "steps",
                shouldInjectKnowledge: false,
                shouldPreferStructuredOutput: true
            ),
            settings: .default
        )
        XCTAssertEqual(planning.maxOutputTokens, 250)
        XCTAssertEqual(planning.penaltyLastN, 96)
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
            memoryContextAvailable: false,
            elevatedRequest: JarvisRequestElevator().elevate(
                prompt: "Help?",
                requestedTask: .chat,
                classification: classification
            )
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
            memoryContextAvailable: true,
            elevatedRequest: JarvisRequestElevator().elevate(
                prompt: "Continue",
                requestedTask: .chat,
                classification: classification
            )
        )

        XCTAssertEqual(plan.mode, .memoryAugmentedResponse)
        XCTAssertTrue(plan.steps.contains(where: { $0.kind == .consultMemory }))
        XCTAssertTrue(plan.diagnostics.memoryAugmentationAvailable)
    }

    @MainActor
    func testMemoryBoundaryPrepareDelegatesToCurrentContextAndAugmentation() async {
        let store = JarvisMemoryStore(filename: "JarvisMemoryBoundaryPrepare-\(UUID().uuidString).json")
        store.clearAll()
        let manager = ConversationMemoryManager(
            store: store,
            policy: MemoryRetentionPolicy(
                maxRecentMessages: 3,
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
            userMessage: JarvisChatMessage(role: .user, text: "I prefer concise launch plans for Jarvis."),
            assistantMessage: JarvisChatMessage(role: .assistant, text: "I will keep the launch plan brief."),
            task: .chat,
            classification: .default
        )
        manager.recordInteraction(
            conversationID: conversationID,
            userMessage: JarvisChatMessage(role: .user, text: "We are shipping TestFlight this week."),
            assistantMessage: JarvisChatMessage(role: .assistant, text: "I can help with the TestFlight checklist."),
            task: .analyzeText,
            classification: JarvisTaskClassification(
                category: .planning,
                task: .analyzeText,
                preset: .balanced,
                confidence: 0.8,
                reasoningHint: "Organize the launch.",
                responseHint: "Use a checklist.",
                shouldInjectKnowledge: false,
                shouldPreferStructuredOutput: true
            )
        )

        let boundary = JarvisExecutionMemoryBoundaryAdapter(
            memoryManager: manager,
            memoryProvider: JarvisSemanticMemoryProvider(store: store, isLongTermMemoryEnabled: { true })
        )
        let conversation = JarvisConversationRecord(
            id: conversationID,
            title: "Launch",
            messages: [
                JarvisChatMessage(role: .user, text: "I prefer concise launch plans for Jarvis."),
                JarvisChatMessage(role: .assistant, text: "I will keep the launch plan brief."),
                JarvisChatMessage(role: .user, text: "We are shipping TestFlight this week."),
                JarvisChatMessage(role: .assistant, text: "I can help with the TestFlight checklist.")
            ]
        )
        let request = JarvisOrchestrationRequest(
            prompt: "Continue the TestFlight launch checklist",
            task: .chat,
            source: "test",
            mode: .plan,
            conversation: conversation
        )
        let classification = JarvisTaskClassification(
            category: .planning,
            task: .chat,
            preset: .balanced,
            confidence: 0.9,
            reasoningHint: "Organize the launch.",
            responseHint: "Use a checklist.",
            shouldInjectKnowledge: false,
            shouldPreferStructuredOutput: true
        )
        let resolvedSkill = JarvisSkillPolicyResolver.resolve(for: request.normalizedRequest, classification: classification)

        let snapshot = await boundary.prepare(
            request: MemoryBoundaryRequest(
                request: request,
                normalizedRequest: request.normalizedRequest,
                classification: classification,
                resolvedSkill: resolvedSkill
            )
        )

        XCTAssertNotNil(snapshot.context.summary)
        XCTAssertFalse(snapshot.context.retrievedMemories.isEmpty)
        XCTAssertNotNil(snapshot.augmentation.summary)
        XCTAssertFalse(snapshot.contextLines.isEmpty)
    }

    @MainActor
    func testMemoryBoundaryRecordDelegatesToConversationMemoryManager() async {
        let store = JarvisMemoryStore(filename: "JarvisMemoryBoundaryRecord-\(UUID().uuidString).json")
        store.clearAll()
        let boundary = JarvisExecutionMemoryBoundaryAdapter(
            memoryManager: ConversationMemoryManager(store: store),
            memoryProvider: JarvisNullMemoryProvider()
        )
        let conversation = JarvisConversationRecord(id: UUID(), title: "Planning")
        let request = JarvisOrchestrationRequest(
            prompt: "Remember that the release needs QA approval.",
            task: .chat,
            source: "test",
            mode: .plan,
            conversation: conversation
        )
        let classification = JarvisTaskClassification(
            category: .planning,
            task: .chat,
            preset: .balanced,
            confidence: 0.9,
            reasoningHint: "Plan the release.",
            responseHint: "Use steps.",
            shouldInjectKnowledge: false,
            shouldPreferStructuredOutput: true
        )

        await boundary.record(
            request: MemoryBoundaryRequest(
                request: request,
                normalizedRequest: request.normalizedRequest,
                classification: classification,
                resolvedSkill: JarvisSkillPolicyResolver.resolve(
                    for: request.normalizedRequest,
                    classification: classification
                )
            ),
            result: AssistantTurnResult(
                requestID: request.id,
                plan: ExecutionPlan(
                    id: UUID(),
                    requestID: request.id,
                    intent: JarvisTypedIntent(mode: .respond, intent: "plan_release", confidence: 0.9),
                    lane: .localFast,
                    steps: []
                ),
                trace: ExecutionTrace(
                    requestID: request.id,
                    planID: UUID(),
                    lane: .localFast,
                    steps: [],
                    status: .success
                ),
                responseText: "I will include QA approval in the release checklist."
            )
        )

        let matches = store.searchMemories(
            query: "QA approval release checklist",
            conversationID: conversation.id,
            limit: 5,
            classification: classification,
            skill: JarvisSkillPolicyResolver.resolve(for: request.normalizedRequest, classification: classification).skill
        )

        XCTAssertFalse(matches.isEmpty)
    }

    @MainActor
    func testRequestElevatorHandlesGreetingWithoutModelCall() {
        let elevator = JarvisRequestElevator()
        let elevated = elevator.elevate(
            prompt: "hi",
            requestedTask: .chat,
            classification: .default
        )

        XCTAssertEqual(elevated.kind, .greeting)
        XCTAssertEqual(elevated.platformResponse, "Hey. Send me what you need.")
        XCTAssertTrue(elevated.prefersSafePrompt)
    }

    @MainActor
    func testRequestElevatorExpandsWeakEmailPrompt() {
        let elevator = JarvisRequestElevator()
        let elevated = elevator.elevate(
            prompt: "mail",
            requestedTask: .chat,
            classification: .default
        )

        XCTAssertEqual(elevated.kind, .clarificationNeeded)
        XCTAssertTrue(elevated.platformResponse?.contains("drafting a new email") == true)
    }

    @MainActor
    func testRequestElevatorClassifiesCodingPrompt() {
        let elevator = JarvisRequestElevator()
        let classification = JarvisAssistantIntelligence.classify(
            prompt: "write a python script for adding numbers",
            requestedTask: .chat,
            context: JarvisAssistantTaskContext(task: .chat, source: "test"),
            conversation: JarvisConversationRecord()
        )

        let elevated = elevator.elevate(
            prompt: "write a python script for adding numbers",
            requestedTask: .chat,
            classification: classification
        )

        XCTAssertEqual(classification.category, .coding)
        XCTAssertEqual(elevated.kind, .codingRequest)
        XCTAssertTrue(elevated.responseContract.prefersCodeFirst)
        XCTAssertTrue(elevated.responseContract.prefersRunnableOutput)
        XCTAssertTrue(elevated.elevatedPrompt.contains("Return runnable code first"))
    }

    @MainActor
    func testRequestElevatorClassifiesScreenshotAsDeviceAction() {
        let elevator = JarvisRequestElevator()
        let elevated = elevator.elevate(
            prompt: "take a screenshot of the screen",
            requestedTask: .chat,
            classification: .default
        )

        XCTAssertEqual(elevated.kind, .deviceActionRequest)
        XCTAssertEqual(elevated.capabilityHint, .screenshot)
        XCTAssertTrue(elevated.responseContract.forbidsHallucinatedCompletion)
    }

    @MainActor
    func testExecutionPlannerRoutesScreenshotToCapabilityAction() async {
        let planner = JarvisExecutionPlanner(capabilityProvider: JarvisSkillCapabilityProvider())
        let request = JarvisNormalizedAssistantRequest(
            prompt: "take a screenshot of the screen",
            requestedTask: .chat,
            invocationSource: JarvisAssistantEntrySource.inApp.rawValue,
            sourceKind: .chat,
            assistantMode: .general,
            conversationID: UUID(),
            conversation: JarvisConversationRecord(),
            routeContext: JarvisAssistantRouteContext()
        )
        let elevated = JarvisRequestElevator().elevate(
            prompt: request.prompt,
            requestedTask: .chat,
            classification: .default
        )

        let plan = await planner.makePlan(
            for: request,
            classification: .default,
            memoryContextAvailable: false,
            elevatedRequest: elevated
        )

        XCTAssertEqual(plan.mode, .capabilityAction)
        XCTAssertTrue(plan.diagnostics.reasoning.joined(separator: " ").contains("capability"))
        XCTAssertFalse(plan.steps.contains(where: { $0.kind == .infer }))
    }

    @MainActor
    func testExecutionPlannerSelectsFileSearchCapability() async {
        let planner = JarvisExecutionPlanner(capabilityProvider: JarvisSkillCapabilityProvider())
        let request = JarvisNormalizedAssistantRequest(
            prompt: "search files for swift",
            requestedTask: .chat,
            invocationSource: JarvisAssistantEntrySource.inApp.rawValue,
            sourceKind: .chat,
            assistantMode: .general,
            conversationID: UUID(),
            conversation: JarvisConversationRecord(),
            routeContext: JarvisAssistantRouteContext()
        )
        let elevated = JarvisRequestElevator().elevate(
            prompt: request.prompt,
            requestedTask: .chat,
            classification: .default
        )

        let plan = await planner.makePlan(
            for: request,
            classification: .default,
            memoryContextAvailable: false,
            elevatedRequest: elevated
        )

        XCTAssertEqual(plan.mode, .capabilityAction)
        XCTAssertEqual(plan.selectedCapabilityID, CapabilityID(rawValue: "file.search"))
        XCTAssertEqual(plan.capabilityApprovalRequired, false)
        XCTAssertEqual(plan.capabilityPlatformAvailability, .shared)
    }

    @MainActor
    func testExecutionPlannerMarksFilePatchAsApprovalRequired() async {
        let planner = JarvisExecutionPlanner(capabilityProvider: JarvisSkillCapabilityProvider())
        let request = JarvisNormalizedAssistantRequest(
            prompt: "patch file `/tmp/demo.swift`",
            requestedTask: .chat,
            invocationSource: JarvisAssistantEntrySource.inApp.rawValue,
            sourceKind: .chat,
            assistantMode: .general,
            conversationID: UUID(),
            conversation: JarvisConversationRecord(),
            routeContext: JarvisAssistantRouteContext()
        )
        let elevated = JarvisRequestElevator().elevate(
            prompt: request.prompt,
            requestedTask: .chat,
            classification: .default
        )

        let plan = await planner.makePlan(
            for: request,
            classification: .default,
            memoryContextAvailable: false,
            elevatedRequest: elevated
        )

        XCTAssertEqual(plan.mode, .capabilityAction)
        XCTAssertEqual(plan.selectedCapabilityID, CapabilityID(rawValue: "file.patch"))
        XCTAssertTrue(plan.capabilityApprovalRequired)
        XCTAssertEqual(plan.capabilityPlatformAvailability, .shared)
    }

    @MainActor
    func testExecutionPlannerSelectsMacOSAppOpenCapability() async {
        let planner = JarvisExecutionPlanner(capabilityProvider: JarvisSkillCapabilityProvider())
        let request = JarvisNormalizedAssistantRequest(
            prompt: "open Safari",
            requestedTask: .chat,
            invocationSource: JarvisAssistantEntrySource.inApp.rawValue,
            sourceKind: .chat,
            assistantMode: .general,
            conversationID: UUID(),
            conversation: JarvisConversationRecord(),
            routeContext: JarvisAssistantRouteContext()
        )
        let elevated = JarvisRequestElevator().elevate(
            prompt: request.prompt,
            requestedTask: .chat,
            classification: .default
        )

        let plan = await planner.makePlan(
            for: request,
            classification: .default,
            memoryContextAvailable: false,
            elevatedRequest: elevated
        )

        XCTAssertEqual(plan.mode, .capabilityAction)
        XCTAssertEqual(plan.selectedCapabilityID, CapabilityID(rawValue: "app.open"))
        XCTAssertEqual(plan.capabilityPlatformAvailability, .macOSOnly)
    }

    func testCapabilityResolverMapsKnowledgeSearchCandidateToResolvedCapability() {
        let candidate = JarvisAssistantCapabilityCandidate(
            name: "knowledge.search",
            summary: "Search the local knowledge surface directly.",
            kind: .searchKnowledge,
            availability: .placeholder
        )

        let resolved = JarvisCapabilityResolver(registry: JarvisToolRegistry()).resolve(candidate: candidate)

        XCTAssertEqual(resolved?.id, "knowledge.lookup")
        XCTAssertEqual(resolved?.kind, .knowledgeLookup)
        XCTAssertEqual(resolved?.risk, .low)
        XCTAssertEqual(resolved?.requiresConfirmation, false)
    }

    func testToolRegistryContainsKnowledgeLookupTool() async throws {
        let registry = JarvisToolRegistry()
        let tool = try XCTUnwrap(registry.tool(for: "knowledge.lookup"))

        XCTAssertEqual(tool.capability.id, "knowledge.lookup")
        XCTAssertEqual(tool.capability.capability, "knowledge.lookup")

        let result = try await tool.execute(
            JarvisToolInvocation(
                toolID: "knowledge.lookup",
                sourceIntent: JarvisTypedIntent(
                    mode: .action,
                    intent: "search_notes",
                    confidence: 0.9
                )
            )
        )

        XCTAssertEqual(result.status, .success)
        XCTAssertEqual(result.userMessage, "Knowledge lookup queued for local search.")
    }

    func testFileAccessManagerRestrictsPathsToApprovedDirectories() throws {
        let defaults = makeFileAccessDefaults()
        let accessManager = JarvisFileAccessManager(defaults: defaults, storageKey: "allowed")
        let allowedDirectory = try makeTemporaryDirectory(named: "allowed-root")
        let allowedFile = allowedDirectory.appendingPathComponent("Notes/example.txt")
        let disallowedFile = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("outside.txt")

        _ = accessManager.addAllowedDirectory(allowedDirectory)

        XCTAssertEqual(accessManager.getAllowedDirectories(), [allowedDirectory])
        XCTAssertTrue(accessManager.isPathAllowed(allowedFile.path))
        XCTAssertFalse(accessManager.isPathAllowed(disallowedFile.path))
    }

    func testFileSearchServiceReturnsMatchesInsideAllowedDirectory() throws {
        let defaults = makeFileAccessDefaults()
        let accessManager = JarvisFileAccessManager(defaults: defaults, storageKey: "allowed")
        let root = try makeTemporaryDirectory(named: "search-root")
        let swiftFile = root.appendingPathComponent("Sources/JarvisFileTool.swift")
        let ignoredFile = root.appendingPathComponent("Docs/readme.md")

        try FileManager.default.createDirectory(at: swiftFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: ignoredFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "struct Demo {}".write(to: swiftFile, atomically: true, encoding: .utf8)
        try "# Readme".write(to: ignoredFile, atomically: true, encoding: .utf8)
        _ = accessManager.addAllowedDirectory(root)

        let service = JarvisFileSearchService(accessManager: accessManager)
        let results = service.searchFiles(query: "swift", limit: 10)

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.path, swiftFile.path)
        XCTAssertEqual(results.first?.name, "JarvisFileTool.swift")
        XCTAssertEqual(results.first?.fileExtension, "swift")
    }

    func testFileReadServiceReadsAllowedFile() throws {
        let defaults = makeFileAccessDefaults()
        let accessManager = JarvisFileAccessManager(defaults: defaults, storageKey: "allowed")
        let root = try makeTemporaryDirectory(named: "read-root")
        let fileURL = root.appendingPathComponent("script.swift")
        try "print(\"hello\")".write(to: fileURL, atomically: true, encoding: .utf8)
        _ = accessManager.addAllowedDirectory(root)

        let service = JarvisFileReadService(accessManager: accessManager)
        let response = try service.readFile(path: fileURL.path)

        XCTAssertEqual(response.path, fileURL.path)
        XCTAssertEqual(response.name, "script.swift")
        XCTAssertEqual(response.fileExtension, "swift")
        XCTAssertEqual(response.content, "print(\"hello\")")
        XCTAssertFalse(response.truncated)
    }

    func testFilePatchServiceAppliesPatchWhenOriginalMatches() throws {
        let defaults = makeFileAccessDefaults()
        let accessManager = JarvisFileAccessManager(defaults: defaults, storageKey: "allowed")
        let root = try makeTemporaryDirectory(named: "patch-root")
        let fileURL = root.appendingPathComponent("notes.txt")
        try "alpha\nbeta".write(to: fileURL, atomically: true, encoding: .utf8)
        _ = accessManager.addAllowedDirectory(root)

        let service = JarvisFilePatchService(accessManager: accessManager)
        let patch = service.generatePatch(original: "alpha\nbeta", updated: "alpha\ngamma")
        let response = try service.applyPatch(path: fileURL.path, patch: patch)

        XCTAssertTrue(response.applied)
        XCTAssertTrue(response.canApply)
        XCTAssertTrue(response.requiresApproval)
        XCTAssertEqual(response.fileName, "notes.txt")
        XCTAssertEqual(response.lineChangeCount, 2)
        XCTAssertTrue(response.diffPreview.contains("- beta"))
        XCTAssertTrue(response.diffPreview.contains("+ gamma"))
        XCTAssertEqual(try String(contentsOf: fileURL, encoding: .utf8), "alpha\ngamma")
    }

    func testFilePatchServicePreviewIsApprovalReadyAndDoesNotWrite() throws {
        let defaults = makeFileAccessDefaults()
        let accessManager = JarvisFileAccessManager(defaults: defaults, storageKey: "allowed")
        let root = try makeTemporaryDirectory(named: "patch-preview-root")
        let fileURL = root.appendingPathComponent("draft.txt")
        try "before".write(to: fileURL, atomically: true, encoding: .utf8)
        _ = accessManager.addAllowedDirectory(root)

        let service = JarvisFilePatchService(accessManager: accessManager)
        let patch = service.generatePatch(original: "before", updated: "after")
        let response = try service.previewPatch(path: fileURL.path, patch: patch)

        XCTAssertFalse(response.applied)
        XCTAssertTrue(response.canApply)
        XCTAssertTrue(response.requiresApproval)
        XCTAssertEqual(try String(contentsOf: fileURL, encoding: .utf8), "before")
    }

    func testFileAccessManagerProvidesValidationStatusForRequestedPath() throws {
        let defaults = makeFileAccessDefaults()
        let accessManager = JarvisFileAccessManager(defaults: defaults, storageKey: "allowed")
        let root = try makeTemporaryDirectory(named: "validate-root")
        let child = root.appendingPathComponent("Folder/file.md")
        _ = accessManager.addAllowedDirectory(root)

        let response = accessManager.validatePath(child.path)

        XCTAssertTrue(response.allowed)
        XCTAssertEqual(response.validationState, "allowed")
        XCTAssertEqual(response.matchedRoot?.path, root.path)
        XCTAssertEqual(response.normalizedPath, child.path)
    }

    func testAllowedRootsListAndAddToolsReturnStructuredResponses() async throws {
        let defaults = UserDefaults.standard
        let storageKey = "jarvis.allowedDirectories"
        defaults.removeObject(forKey: storageKey)
        let root = try makeTemporaryDirectory(named: "allowed-root-tool")
        defer { defaults.removeObject(forKey: storageKey) }

        let registry = JarvisToolRegistry()
        let addTool = try XCTUnwrap(registry.tool(for: "file.allowed_roots.add"))
        let addResult = try await addTool.execute(
            JarvisToolInvocation(
                toolID: "file.allowed_roots.add",
                arguments: ["path": .string(root.path)],
                sourceIntent: JarvisTypedIntent(mode: .action, intent: "file.allowed_roots.add", confidence: 0.9)
            )
        )

        XCTAssertEqual(addResult.status, .success)
        let addPayload = try XCTUnwrap(addResult.rawResult)
        let addResponse = try JSONDecoder().decode(JarvisAllowedRootAddResponse.self, from: addPayload)
        XCTAssertEqual(addResponse.root.path, root.path)
        XCTAssertTrue(addResponse.added)
        XCTAssertEqual(addResponse.validationState, "allowed")

        let listTool = try XCTUnwrap(registry.tool(for: "file.allowed_roots.list"))
        let listResult = try await listTool.execute(
            JarvisToolInvocation(
                toolID: "file.allowed_roots.list",
                sourceIntent: JarvisTypedIntent(mode: .action, intent: "file.allowed_roots.list", confidence: 0.9)
            )
        )

        XCTAssertEqual(listResult.status, .success)
        let listPayload = try XCTUnwrap(listResult.rawResult)
        let listResponse = try JSONDecoder().decode(JarvisAllowedRootsListResponse.self, from: listPayload)
        XCTAssertTrue(listResponse.roots.contains(where: { $0.path == root.path }))
    }

    func testFilePathValidateToolReturnsMatchedRootStatus() async throws {
        let defaults = UserDefaults.standard
        let storageKey = "jarvis.allowedDirectories"
        let root = try makeTemporaryDirectory(named: "validate-tool-root")
        let nestedPath = root.appendingPathComponent("Nested/file.swift").path
        defaults.set([root.path], forKey: storageKey)
        defer { defaults.removeObject(forKey: storageKey) }

        let registry = JarvisToolRegistry()
        let tool = try XCTUnwrap(registry.tool(for: "file.path.validate"))
        let result = try await tool.execute(
            JarvisToolInvocation(
                toolID: "file.path.validate",
                arguments: ["path": .string(nestedPath)],
                sourceIntent: JarvisTypedIntent(mode: .action, intent: "file.path.validate", confidence: 0.9)
            )
        )

        XCTAssertEqual(result.status, .success)
        let payload = try XCTUnwrap(result.rawResult)
        let response = try JSONDecoder().decode(JarvisFilePathValidationResponse.self, from: payload)
        XCTAssertTrue(response.allowed)
        XCTAssertEqual(response.validationState, "allowed")
        XCTAssertEqual(response.matchedRoot?.path, root.path)
    }

    func testFilePreviewToolReturnsMetadataForCardRendering() async throws {
        let defaults = UserDefaults.standard
        let storageKey = "jarvis.allowedDirectories"
        let root = try makeTemporaryDirectory(named: "preview-tool-root")
        let fileURL = root.appendingPathComponent("notes.md")
        try "# Title\nBody".write(to: fileURL, atomically: true, encoding: .utf8)
        defaults.set([root.path], forKey: storageKey)
        defer { defaults.removeObject(forKey: storageKey) }

        let registry = JarvisToolRegistry()
        let tool = try XCTUnwrap(registry.tool(for: "file.preview"))
        let result = try await tool.execute(
            JarvisToolInvocation(
                toolID: "file.preview",
                arguments: ["path": .string(fileURL.path), "max_length": .number(10)],
                sourceIntent: JarvisTypedIntent(mode: .action, intent: "file.preview", confidence: 0.9)
            )
        )

        let payload = try XCTUnwrap(result.rawResult)
        let response = try JSONDecoder().decode(JarvisFilePreviewResponse.self, from: payload)
        XCTAssertEqual(response.name, "notes.md")
        XCTAssertEqual(response.fileExtension, "md")
        XCTAssertTrue(response.truncated)
        XCTAssertGreaterThan(response.byteCount, 0)
    }

    func testFilePatchToolReturnsApprovalReadyPreviewWithoutWriting() async throws {
        let defaults = UserDefaults.standard
        let storageKey = "jarvis.allowedDirectories"
        let root = try makeTemporaryDirectory(named: "patch-tool-root")
        let fileURL = root.appendingPathComponent("notes.txt")
        try "line one\nline two".write(to: fileURL, atomically: true, encoding: .utf8)
        defaults.set([root.path], forKey: storageKey)
        defer { defaults.removeObject(forKey: storageKey) }

        let registry = JarvisToolRegistry()
        let tool = try XCTUnwrap(registry.tool(for: "file.patch"))
        let result = try await tool.execute(
            JarvisToolInvocation(
                toolID: "file.patch",
                arguments: [
                    "path": .string(fileURL.path),
                    "updated_content": .string("line one\nline three")
                ],
                sourceIntent: JarvisTypedIntent(mode: .action, intent: "file.patch", confidence: 0.9)
            )
        )

        XCTAssertEqual(result.status, .success)
        XCTAssertEqual(result.verificationState, .unverified)
        let payload = try XCTUnwrap(result.rawResult)
        let response = try JSONDecoder().decode(JarvisFilePatchResponse.self, from: payload)
        XCTAssertFalse(response.applied)
        XCTAssertTrue(response.canApply)
        XCTAssertTrue(response.requiresApproval)
        XCTAssertEqual(try String(contentsOf: fileURL, encoding: .utf8), "line one\nline two")
    }

    func testFileCreateToolReturnsApprovalReadyPreviewBeforeWriting() async throws {
        let defaults = UserDefaults.standard
        let storageKey = "jarvis.allowedDirectories"
        let root = try makeTemporaryDirectory(named: "create-tool-root")
        let fileURL = root.appendingPathComponent("Sources/NewFile.swift")
        defaults.set([root.path], forKey: storageKey)
        defer { defaults.removeObject(forKey: storageKey) }

        let registry = JarvisToolRegistry()
        let tool = try XCTUnwrap(registry.tool(for: "file.create"))
        let result = try await tool.execute(
            JarvisToolInvocation(
                toolID: "file.create",
                arguments: [
                    "path": .string(fileURL.path),
                    "content": .string("struct NewFile {}")
                ],
                sourceIntent: JarvisTypedIntent(mode: .action, intent: "file.create", confidence: 0.9)
            )
        )

        XCTAssertEqual(result.status, .success)
        XCTAssertEqual(result.verificationState, .unverified)
        let payload = try XCTUnwrap(result.rawResult)
        let response = try JSONDecoder().decode(JarvisFileCreateResponse.self, from: payload)
        XCTAssertFalse(response.created)
        XCTAssertTrue(response.canCreate)
        XCTAssertTrue(response.requiresApproval)
        XCTAssertEqual(response.fileName, "NewFile.swift")
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
    }

    func testToolRegistryExposesAndExecutesFileSearchTool() async throws {
        let defaults = UserDefaults.standard
        let storageKey = "jarvis.allowedDirectories"
        let root = try makeTemporaryDirectory(named: "registry-search-root")
        let fileURL = root.appendingPathComponent("feature.swift")
        try "func feature() {}".write(to: fileURL, atomically: true, encoding: .utf8)
        defaults.set([root.path], forKey: storageKey)
        defer { defaults.removeObject(forKey: storageKey) }

        let registry = JarvisToolRegistry()
        let tool = try XCTUnwrap(registry.tool(for: "file.search"))

        let result = try await tool.execute(
            JarvisToolInvocation(
                toolID: "file.search",
                arguments: [
                    "query": .string("swift"),
                    "limit": .number(10)
                ],
                sourceIntent: JarvisTypedIntent(
                    mode: .action,
                    intent: "file.search",
                    confidence: 0.9
                )
            )
        )

        XCTAssertEqual(result.status, .success)
        let payload = try XCTUnwrap(result.rawResult)
        let response = try JSONDecoder().decode(JarvisFileSearchResponse.self, from: payload)
        XCTAssertEqual(response.results.count, 1)
        XCTAssertEqual(response.results.first?.path, fileURL.path)
        XCTAssertTrue(registry.capabilities().contains(where: { $0.id == "file.search" }))
    }

    @MainActor
    func testExecutionPlannerKeepsCodingOnDirectResponse() async {
        let planner = JarvisExecutionPlanner(capabilityProvider: JarvisSkillCapabilityProvider())
        let classification = JarvisAssistantIntelligence.classify(
            prompt: "write a python script for adding numbers",
            requestedTask: .chat,
            context: JarvisAssistantTaskContext(task: .chat, source: "test"),
            conversation: JarvisConversationRecord()
        )
        let request = JarvisNormalizedAssistantRequest(
            prompt: "write a python script for adding numbers",
            requestedTask: .chat,
            invocationSource: JarvisAssistantEntrySource.inApp.rawValue,
            sourceKind: .chat,
            assistantMode: .general,
            conversationID: UUID(),
            conversation: JarvisConversationRecord(),
            routeContext: JarvisAssistantRouteContext()
        )

        let plan = await planner.makePlan(
            for: request,
            classification: classification,
            memoryContextAvailable: false,
            elevatedRequest: JarvisRequestElevator().elevate(
                prompt: request.prompt,
                requestedTask: .chat,
                classification: classification
            )
        )

        XCTAssertEqual(plan.mode, .directResponse)
        XCTAssertTrue(plan.diagnostics.reasoning.joined(separator: " ").contains("direct response") || plan.diagnostics.reasoning.joined(separator: " ").contains("direct answer"))
    }

    @MainActor
    func testExecutionPlannerAdapterOwnsRoutePolicyAndLaneForPlanningRequest() async {
        let adapter = JarvisExecutionPlannerAdapter(
            planner: JarvisExecutionPlanner(capabilityProvider: JarvisSkillCapabilityProvider())
        )
        let request = JarvisNormalizedAssistantRequest(
            prompt: "Plan my launch checklist",
            requestedTask: .chat,
            invocationSource: JarvisAssistantEntrySource.inApp.rawValue,
            sourceKind: .chat,
            assistantMode: .plan,
            conversationID: UUID(),
            conversation: JarvisConversationRecord(),
            routeContext: JarvisAssistantRouteContext()
        )
        let classification = JarvisTaskClassification(
            category: .planning,
            task: .chat,
            preset: .balanced,
            confidence: 0.8,
            reasoningHint: "Planning request",
            responseHint: "Produce steps",
            shouldInjectKnowledge: false,
            shouldPreferStructuredOutput: true
        )
        let resolvedSkill = JarvisSkillPolicyResolver.resolve(for: request, classification: classification)
        let elevatedRequest = JarvisRequestElevator().elevate(
            prompt: request.prompt,
            requestedTask: request.requestedTask,
            classification: classification
        )

        let plan = await adapter.makePlan(
            for: request,
            classification: classification,
            memoryContextAvailable: false,
            elevatedRequest: elevatedRequest,
            resolvedSkill: resolvedSkill
        )

        XCTAssertEqual(plan.routeDecision?.typedIntent.intent, elevatedRequest.elevatedIntent)
        XCTAssertEqual(plan.routeDecision?.typedIntent.mode, .workflow)
        XCTAssertEqual(plan.policyDecision?.isAllowed, true)
        XCTAssertEqual(plan.selectedModelLane, .remoteReasoning)
        XCTAssertEqual(plan.routeDecision?.selectedSkillID, resolvedSkill.skill.id)
    }

    @MainActor
    func testExecutionPlannerAdapterComputesRoutePolicyAndLaneBeforePlanBuild() async {
        let spyBuilder = SpyExecutionPlanBuilder()
        let adapter = JarvisExecutionPlannerAdapter(planner: spyBuilder)
        let request = JarvisNormalizedAssistantRequest(
            prompt: "Take a screenshot of the screen",
            requestedTask: .chat,
            invocationSource: JarvisAssistantEntrySource.inApp.rawValue,
            sourceKind: .chat,
            assistantMode: .general,
            conversationID: UUID(),
            conversation: JarvisConversationRecord(),
            routeContext: JarvisAssistantRouteContext()
        )
        let classification = JarvisTaskClassification.default
        let resolvedSkill = JarvisSkillPolicyResolver.resolve(for: request, classification: classification)
        let elevatedRequest = JarvisRequestElevator().elevate(
            prompt: request.prompt,
            requestedTask: request.requestedTask,
            classification: classification
        )

        _ = await adapter.makePlan(
            for: request,
            classification: classification,
            memoryContextAvailable: false,
            elevatedRequest: elevatedRequest,
            resolvedSkill: resolvedSkill
        )

        XCTAssertEqual(spyBuilder.recordedRequestID, request.id)
        XCTAssertEqual(spyBuilder.recordedRouteDecision?.typedIntent.intent, elevatedRequest.elevatedIntent)
        XCTAssertEqual(spyBuilder.recordedPolicyDecision?.riskLevel, .medium)
        XCTAssertEqual(spyBuilder.recordedSelectedModelLane, .localFast)
        XCTAssertEqual(spyBuilder.recordedSelectedSkillID, resolvedSkill.skill.id)
    }

    @MainActor
    func testCapabilityFallbackReturnsStructuredNonModelResponseWhenUnavailable() async {
        let engine = TestGGUFEngine()
        let runtime = JarvisLocalModelRuntime(engine: engine)
        let orchestrator = JarvisTaskOrchestrator(
            runtime: runtime,
            executionPlanner: JarvisExecutionPlannerAdapter(
                planner: JarvisExecutionPlanner(capabilityProvider: JarvisSkillCapabilityProvider())
            )
        )

        let request = JarvisOrchestrationRequest(
            prompt: "take a screenshot of the screen",
            task: .chat,
            source: "test",
            sourceKind: .chat,
            mode: .general,
            conversation: JarvisConversationRecord(),
            settingsSnapshot: .default
        )

        let expectation = expectation(description: "capability fallback")
        var result: JarvisOrchestrationResult?

        orchestrator.orchestrate(request: request, onComplete: { completed in
            result = completed
            expectation.fulfill()
        })

        await fulfillment(of: [expectation], timeout: 2.0)

        XCTAssertEqual(result?.executionPlan.mode, .capabilityAction)
        XCTAssertEqual(result?.turnResult.deliveryMode, .statusOnly)
        XCTAssertTrue(result?.streamingText.contains("screenshot action") == true)
        XCTAssertEqual(engine.loadCount, 0)
        XCTAssertNotNil(result?.turnResult.executionTrace)
        XCTAssertFalse(result?.turnResult.coreExecutionTrace.steps.isEmpty ?? true)
        XCTAssertEqual(result?.turnResult.diagnostics, result?.executionPlan.diagnostics)
    }

    @MainActor
    func testMemoryAugmentedLaneUsesMemoryBoundaryPrepareAndRecord() async throws {
        let engine = TestGGUFEngine()
        let runtime = JarvisLocalModelRuntime(engine: engine)
        let modelURL = try temporaryGGUFURL(named: "memory-boundary-lane")
        runtime.setSelectedModel(
            JarvisRuntimeModelSelection(
                id: UUID(),
                displayName: "Memory Boundary Model",
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

        let snapshot = MemorySnapshot(
            context: MemoryContext(
                recentMessages: [
                    JarvisChatMessage(role: .user, text: "Here is some background."),
                    JarvisChatMessage(role: .assistant, text: "Understood.")
                ],
                summary: ConversationSummary(
                    conversationID: UUID(),
                    messageCount: 2,
                    summaryText: "The user already provided launch background."
                )
            ),
            augmentation: JarvisAssistantMemoryAugmentation(
                supplementalContext: [
                    JarvisPromptContextBlock(
                        title: "Relevant Context",
                        content: "- Project Context: Launch is this week."
                    )
                ],
                summary: "Relevant Context:\n- Project Context: Launch is this week."
            )
        )
        let memoryBoundary = SpyMemoryBoundary(snapshot: snapshot)
        let conversation = JarvisConversationRecord(
            messages: [
                JarvisChatMessage(role: .user, text: "Here is some background."),
                JarvisChatMessage(role: .assistant, text: "Understood.")
            ]
        )
        let orchestrator = JarvisTaskOrchestrator(
            runtime: runtime,
            memoryBoundary: memoryBoundary
        )
        let request = JarvisOrchestrationRequest(
            prompt: "Continue",
            task: .chat,
            source: "test",
            sourceKind: .chat,
            mode: .general,
            conversation: conversation,
            settingsSnapshot: .default
        )

        let expectation = expectation(description: "memory boundary lane")
        var result: JarvisOrchestrationResult?

        orchestrator.orchestrate(request: request, onComplete: { completed in
            result = completed
            expectation.fulfill()
        })

        await fulfillment(of: [expectation], timeout: 2.0)

        let completed = try XCTUnwrap(result)
        XCTAssertEqual(completed.executionPlan.mode, .memoryAugmentedResponse)
        XCTAssertEqual(memoryBoundary.prepareCallCount, 1)
        XCTAssertEqual(memoryBoundary.recordCallCount, 1)
        XCTAssertEqual(memoryBoundary.recordedRequestID, request.id)
        XCTAssertEqual(memoryBoundary.recordedResponseText, completed.streamingText)
        XCTAssertEqual(completed.memoryContext, snapshot.context)
        XCTAssertTrue(
            completed.assistantRequest?.promptBlueprint.contextBlocks.contains {
                $0.title == "Relevant Context" && $0.content.contains("Launch is this week.")
            } == true
        )
    }

    @MainActor
    func testNonMigratedCapabilityLaneDoesNotUseMemoryBoundary() async {
        let engine = TestGGUFEngine()
        let runtime = JarvisLocalModelRuntime(engine: engine)
        let memoryBoundary = SpyMemoryBoundary(snapshot: MemorySnapshot())
        let orchestrator = JarvisTaskOrchestrator(
            runtime: runtime,
            memoryBoundary: memoryBoundary,
            executionPlanner: JarvisExecutionPlannerAdapter(
                planner: JarvisExecutionPlanner(capabilityProvider: JarvisSkillCapabilityProvider())
            )
        )
        let request = JarvisOrchestrationRequest(
            prompt: "take a screenshot of the screen",
            task: .chat,
            source: "test",
            sourceKind: .chat,
            mode: .general,
            conversation: JarvisConversationRecord(),
            settingsSnapshot: .default
        )

        let expectation = expectation(description: "capability unchanged")
        orchestrator.orchestrate(request: request, onComplete: { _ in
            expectation.fulfill()
        })

        await fulfillment(of: [expectation], timeout: 2.0)

        XCTAssertEqual(memoryBoundary.prepareCallCount, 0)
        XCTAssertEqual(memoryBoundary.recordCallCount, 0)
        XCTAssertEqual(engine.loadCount, 0)
    }

    @MainActor
    func testDirectResponseLaneUsesExecutionRuntimeSeam() async {
        let engine = TestGGUFEngine()
        let runtime = JarvisLocalModelRuntime(engine: engine)
        let executionRuntime = TestExecutionRuntime(tokens: ["print(", "\"sum\"", ")"], stopReason: .eos)
        let orchestrator = JarvisTaskOrchestrator(
            runtime: runtime,
            executionRuntime: executionRuntime
        )

        let request = JarvisOrchestrationRequest(
            prompt: "write a python script for adding two numbers",
            task: .chat,
            source: "test",
            sourceKind: .chat,
            mode: .code,
            conversation: JarvisConversationRecord(),
            settingsSnapshot: .default
        )

        let expectation = expectation(description: "direct response through execution runtime seam")
        var result: JarvisOrchestrationResult?

        orchestrator.orchestrate(request: request, onComplete: { completed in
            result = completed
            expectation.fulfill()
        })

        await fulfillment(of: [expectation], timeout: 2.0)

        XCTAssertEqual(result?.executionPlan.mode, .directResponse)
        XCTAssertEqual(executionRuntime.prepareCount, 1)
        XCTAssertEqual(executionRuntime.streamCount, 1)
        XCTAssertEqual(engine.loadCount, 0)
        XCTAssertEqual(result?.turnResult.responseText, "print(\"sum\")")
    }

    @MainActor
    func testNonMigratedPlanOnlyLaneStillUsesLegacyRuntime() async throws {
        let engine = TestGGUFEngine()
        let runtime = JarvisLocalModelRuntime(engine: engine)
        let modelURL = try temporaryGGUFURL(named: "legacy-plan-only")

        runtime.setSelectedModel(
            JarvisRuntimeModelSelection(
                id: UUID(),
                displayName: "Legacy Plan Model",
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

        let executionRuntime = TestExecutionRuntime(tokens: ["adapter"], stopReason: .eos)
        let orchestrator = JarvisTaskOrchestrator(
            runtime: runtime,
            executionRuntime: executionRuntime
        )

        let request = JarvisOrchestrationRequest(
            prompt: "plan the release checklist for tomorrow",
            task: .analyzeText,
            source: "test",
            sourceKind: .chat,
            mode: .plan,
            conversation: JarvisConversationRecord(),
            settingsSnapshot: .default
        )

        let expectation = expectation(description: "plan only uses legacy runtime")
        var result: JarvisOrchestrationResult?

        orchestrator.orchestrate(request: request, onComplete: { completed in
            result = completed
            expectation.fulfill()
        })

        await fulfillment(of: [expectation], timeout: 2.0)

        XCTAssertEqual(result?.executionPlan.mode, .planOnly)
        XCTAssertEqual(executionRuntime.prepareCount, 0)
        XCTAssertEqual(executionRuntime.streamCount, 0)
        XCTAssertEqual(engine.loadCount, 1)
        XCTAssertEqual(result?.turnResult.responseText, "ok")
    }

    @MainActor
    func testSelectedModelLaneControlsRuntimeChoiceForDirectResponse() async throws {
        let engine = TestGGUFEngine()
        let runtime = JarvisLocalModelRuntime(engine: engine)
        let modelURL = try temporaryGGUFURL(named: "lane-authoritative")

        runtime.setSelectedModel(
            JarvisRuntimeModelSelection(
                id: UUID(),
                displayName: "Lane Model",
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

        let executionRuntime = TestExecutionRuntime(tokens: ["local"], stopReason: .eos)
        let orchestrator = JarvisTaskOrchestrator(
            runtime: runtime,
            executionRuntime: executionRuntime,
            executionPlanner: FixedExecutionPlanner(
                mode: .directResponse,
                selectedModelLane: .remoteReasoning
            )
        )

        let request = JarvisOrchestrationRequest(
            prompt: "Answer this with remote lane selection",
            task: .chat,
            source: "test",
            sourceKind: .chat,
            mode: .general,
            conversation: JarvisConversationRecord(),
            settingsSnapshot: .default
        )

        let expectation = expectation(description: "lane drives runtime selection")
        var result: JarvisOrchestrationResult?

        orchestrator.orchestrate(request: request, onComplete: { completed in
            result = completed
            expectation.fulfill()
        })

        await fulfillment(of: [expectation], timeout: 2.0)

        XCTAssertEqual(result?.executionPlan.mode, .directResponse)
        XCTAssertEqual(result?.executionPlan.selectedModelLane, .remoteReasoning)
        XCTAssertEqual(executionRuntime.prepareCount, 0)
        XCTAssertEqual(executionRuntime.streamCount, 0)
        XCTAssertEqual(engine.loadCount, 1)
        XCTAssertEqual(result?.turnResult.responseText, "ok")
    }

    @MainActor
    func testKnowledgeCapabilityRouteExecutesThroughResolvedTool() async {
        let engine = TestGGUFEngine()
        let runtime = JarvisLocalModelRuntime(engine: engine)
        let orchestrator = JarvisTaskOrchestrator(
            runtime: runtime,
            executionPlanner: JarvisExecutionPlannerAdapter(
                planner: JarvisExecutionPlanner(capabilityProvider: JarvisSkillCapabilityProvider())
            ),
            toolRegistry: JarvisToolRegistry()
        )

        let request = JarvisOrchestrationRequest(
            prompt: "search my notes for release checklist",
            task: .chat,
            source: "test",
            sourceKind: .chat,
            mode: .general,
            conversation: JarvisConversationRecord(),
            settingsSnapshot: .default
        )

        let expectation = expectation(description: "knowledge capability")
        var result: JarvisOrchestrationResult?

        orchestrator.orchestrate(request: request, onComplete: { completed in
            result = completed
            expectation.fulfill()
        })

        await fulfillment(of: [expectation], timeout: 2.0)

        XCTAssertEqual(result?.executionPlan.mode, .capabilityAction)
        XCTAssertEqual(result?.turnResult.deliveryMode, .statusOnly)
        XCTAssertEqual(result?.streamingText, "Knowledge lookup queued for local search.")
        XCTAssertEqual(engine.loadCount, 0)

        let capabilityStep = result?.executionPlan.coreExecutionPlan.steps.first(where: { $0.kind == .capability })
        XCTAssertEqual(capabilityStep?.capability?.id, "knowledge.lookup")
    }

    @MainActor
    func testDirectResponseOrchestrationEmitsRealExecutionTraceWithoutChangingResponse() async throws {
        let engine = TestGGUFEngine()
        let runtime = JarvisLocalModelRuntime(engine: engine)
        let modelURL = try temporaryGGUFURL(named: "direct-response-trace")
        runtime.setSelectedModel(
            JarvisRuntimeModelSelection(
                id: UUID(),
                displayName: "Trace Test Model",
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

        let orchestrator = JarvisTaskOrchestrator(runtime: runtime)
        let request = JarvisOrchestrationRequest(
            prompt: "Explain tuples in Swift",
            task: .chat,
            source: "test",
            sourceKind: .chat,
            mode: .general,
            conversation: JarvisConversationRecord(),
            settingsSnapshot: .default
        )

        let expectation = expectation(description: "direct response trace")
        var result: JarvisOrchestrationResult?

        orchestrator.orchestrate(request: request, onComplete: { completed in
            result = completed
            expectation.fulfill()
        })

        await fulfillment(of: [expectation], timeout: 2.0)

        let completed = try XCTUnwrap(result)
        let trace = try XCTUnwrap(completed.turnResult.executionTrace)

        XCTAssertNil(completed.error)
        XCTAssertEqual(completed.executionPlan.mode, .directResponse)
        XCTAssertEqual(completed.turnResult.responseText, "ok")
        XCTAssertEqual(completed.streamingText, "ok")
        XCTAssertEqual(trace.requestID, completed.request.id)
        XCTAssertEqual(trace.planID, completed.executionPlan.id)
        XCTAssertEqual(trace.lane, completed.executionPlan.selectedModelLane)
        XCTAssertEqual(trace.status, .success)
        XCTAssertEqual(trace.steps.count, completed.executionPlan.steps.count)
        XCTAssertEqual(trace.steps.map(\.stepID), completed.executionPlan.steps.map(\.id))
        XCTAssertTrue(trace.steps.allSatisfy { $0.capabilityID == nil && $0.status == .success })
        XCTAssertEqual(completed.turnResult.coreExecutionTrace, trace)
    }

    func testCoreAssistantRequestMapsOrchestrationAndNormalizedRequests() {
        let conversation = JarvisConversationRecord(title: "Orchestrated", updatedAt: Date(), messages: [])
        let orchestrationRequest = JarvisOrchestrationRequest(
            id: UUID(),
            createdAt: Date(timeIntervalSince1970: 456),
            prompt: "Open the knowledge tab",
            task: .chat,
            source: "test",
            sourceKind: .shortcut,
            mode: .general,
            conversation: conversation,
            settingsSnapshot: .default
        )
        let request = makeNormalizedAssistantRequest(prompt: "  Build me a Swift enum  ", task: .analyzeText)

        let fromOrchestration = orchestrationRequest.coreAssistantRequest
        let fromNormalized = request.coreAssistantRequest

        XCTAssertEqual(fromOrchestration.id, orchestrationRequest.id)
        XCTAssertEqual(fromOrchestration.conversationID, orchestrationRequest.conversation.id)
        XCTAssertEqual(fromOrchestration.text, "Open the knowledge tab")
        XCTAssertEqual(fromOrchestration.task, .chat)
        XCTAssertEqual(fromOrchestration.source, .shortcut)

        XCTAssertEqual(fromNormalized.id, request.id)
        XCTAssertEqual(fromNormalized.conversationID, request.conversationID)
        XCTAssertEqual(fromNormalized.text, "Build me a Swift enum")
        XCTAssertEqual(fromNormalized.task, .analyzeText)
        XCTAssertEqual(fromNormalized.source, .chat)
    }

    func testCoreExecutionPlanMapsCurrentPlan() {
        let request = makeNormalizedAssistantRequest(prompt: "Plan a release", task: .chat)
        let step = JarvisAssistantExecutionStep(
            kind: .chooseMode,
            title: "Choose Execution Mode",
            detail: "Pick the path.",
            usesModel: false
        )
        let plan = JarvisAssistantExecutionPlan(
            request: request,
            detectedTask: .chat,
            classification: .default,
            elevatedRequest: makeElevatedRequest(),
            mode: .planOnly,
            responseStyle: .balanced,
            deliveryMode: .streamingText,
            selectedModelLane: .remoteReasoning,
            steps: [step],
            diagnostics: JarvisAssistantDecisionTrace(
                selectedMode: .planOnly,
                reasoning: ["Planning intent detected."],
                usedExistingPromptPipeline: true
            )
        )

        let corePlan = plan.coreExecutionPlan

        XCTAssertEqual(corePlan.id, plan.id)
        XCTAssertEqual(corePlan.requestID, request.id)
        XCTAssertEqual(corePlan.intent.intent, "test_intent")
        XCTAssertEqual(corePlan.intent.mode, .workflow)
        XCTAssertEqual(corePlan.lane, .remoteReasoning)
        XCTAssertEqual(corePlan.steps.count, 1)
        XCTAssertEqual(corePlan.steps.first?.id, step.id)
        XCTAssertEqual(corePlan.steps.first?.kind, .decision)
        XCTAssertNil(corePlan.steps.first?.capability)
    }

    func testCoreExecutionTraceAndTurnResultMapCurrentTurnResult() {
        let request = makeNormalizedAssistantRequest(prompt: "Answer directly", task: .chat)
        let typedIntent = JarvisTypedIntent(
            mode: .respond,
            intent: "answer_directly",
            confidence: 0.91,
            reasoningSummary: "Direct response"
        )
        let plan = JarvisAssistantExecutionPlan(
            request: request,
            detectedTask: .chat,
            classification: .default,
            elevatedRequest: makeElevatedRequest(),
            mode: .directResponse,
            responseStyle: .balanced,
            deliveryMode: .streamingText,
            routeDecision: JarvisRouteDecision(
                typedIntent: typedIntent,
                lane: .localFast,
                reason: "Direct response"
            ),
            selectedModelLane: .localFast,
            steps: [],
            diagnostics: JarvisAssistantDecisionTrace(
                selectedMode: .directResponse,
                reasoning: ["No special execution path was required."],
                usedExistingPromptPipeline: true
            )
        )
        let turnResult = JarvisAssistantTurnResult(
            request: request,
            plan: plan,
            assistantRequest: nil,
            responseText: "Here is the answer.",
            deliveryMode: .streamingText,
            diagnostics: plan.diagnostics
        )

        let coreTrace = turnResult.coreExecutionTrace
        let coreTurnResult = turnResult.coreAssistantTurnResult

        XCTAssertEqual(coreTrace.requestID, request.id)
        XCTAssertEqual(coreTrace.planID, plan.id)
        XCTAssertEqual(coreTrace.lane, .localFast)
        XCTAssertEqual(coreTrace.status, .success)
        XCTAssertTrue(coreTrace.steps.isEmpty)

        XCTAssertEqual(coreTurnResult.requestID, request.id)
        XCTAssertEqual(coreTurnResult.plan.id, plan.id)
        XCTAssertEqual(coreTurnResult.responseText, "Here is the answer.")
        XCTAssertEqual(coreTurnResult.plan.intent.intent, "answer_directly")
        XCTAssertEqual(coreTurnResult.trace.status, .success)
    }

    func testCoreExecutionTraceFallsBackToLegacyAdapterWhenNoStoredTraceExists() {
        let request = makeNormalizedAssistantRequest(prompt: "Take a screenshot", task: .chat)
        let plan = JarvisAssistantExecutionPlan(
            request: request,
            detectedTask: .chat,
            classification: .default,
            elevatedRequest: makeElevatedRequest(),
            mode: .capabilityAction,
            responseStyle: .balanced,
            deliveryMode: .statusOnly,
            selectedModelLane: .localFast,
            steps: [
                JarvisAssistantExecutionStep(
                    kind: .inspectCapabilities,
                    title: "Inspect Capabilities",
                    detail: "Reserve a capability stage.",
                    usesModel: false
                )
            ],
            diagnostics: JarvisAssistantDecisionTrace(
                selectedMode: .capabilityAction,
                reasoning: ["Capability action route."],
                usedExistingPromptPipeline: false
            )
        )
        let turnResult = JarvisAssistantTurnResult(
            request: request,
            plan: plan,
            assistantRequest: nil,
            responseText: "Capability fallback",
            deliveryMode: .statusOnly,
            diagnostics: plan.diagnostics
        )

        let trace = turnResult.coreExecutionTrace

        XCTAssertNil(turnResult.executionTrace)
        XCTAssertEqual(trace.requestID, request.id)
        XCTAssertEqual(trace.planID, plan.id)
        XCTAssertEqual(trace.lane, .localFast)
        XCTAssertTrue(trace.steps.isEmpty)
        XCTAssertEqual(trace.status, .success)
    }

    func testAssistantTurnResultProvidesRequestIDResolvedTextAndAttributionForAppConsumers() {
        let request = makeNormalizedAssistantRequest(prompt: "Answer directly", task: .chat)
        let plan = JarvisAssistantExecutionPlan(
            request: request,
            detectedTask: .chat,
            classification: .default,
            elevatedRequest: makeElevatedRequest(),
            mode: .directResponse,
            responseStyle: .balanced,
            deliveryMode: .streamingText,
            selectedModelLane: .localFast,
            steps: [],
            diagnostics: JarvisAssistantDecisionTrace(
                selectedMode: .directResponse,
                reasoning: ["Direct response"],
                usedExistingPromptPipeline: true
            )
        )
        let attribution = JarvisMessageMemoryAttribution(
            usedMemory: true,
            memorySourceIDs: [UUID()],
            sourceKinds: [.conversationSummary],
            labels: ["Conversation summary"],
            usedSummary: true,
            chosenSkillID: "answer_question"
        )
        let suggestions = [
            JarvisAssistantSuggestionDescriptor(
                title: "Follow up",
                icon: "arrow.right.circle",
                action: .prompt("Tell me more")
            )
        ]
        let turnResult = JarvisAssistantTurnResult(
            request: request,
            plan: plan,
            assistantRequest: nil,
            responseText: "  ",
            suggestions: suggestions,
            deliveryMode: .streamingText,
            diagnostics: plan.diagnostics,
            messageAttribution: attribution
        )
        let coreTurnResult = turnResult.coreAssistantTurnResult

        XCTAssertEqual(turnResult.requestID, request.id)
        XCTAssertEqual(coreTurnResult.requestID, request.id)
        XCTAssertEqual(
            coreTurnResult.finalizedResponseText(
                fallbackStreamingText: "draft from result",
                runtimeStreamingText: "draft from runtime"
            ),
            "draft from result"
        )
        XCTAssertEqual(coreTurnResult.messageAttribution, attribution)
        XCTAssertEqual(coreTurnResult.suggestions, suggestions)
    }

    func testOrchestrationResultExposesCoreAssistantTurnResultForAdapterConsumers() {
        let request = makeNormalizedAssistantRequest(prompt: "Summarize this", task: .chat)
        let plan = JarvisAssistantExecutionPlan(
            request: request,
            detectedTask: .chat,
            classification: .default,
            elevatedRequest: makeElevatedRequest(),
            mode: .directResponse,
            responseStyle: .balanced,
            deliveryMode: .streamingText,
            selectedModelLane: .localFast,
            steps: [],
            diagnostics: JarvisAssistantDecisionTrace(
                selectedMode: .directResponse,
                reasoning: ["Direct response"],
                usedExistingPromptPipeline: true
            )
        )
        let suggestion = JarvisAssistantSuggestionDescriptor(
            title: "Summarize again",
            icon: "text.quote",
            action: .task(.summarize, "Summarize again")
        )
        let legacyTurnResult = JarvisAssistantTurnResult(
            request: request,
            plan: plan,
            assistantRequest: nil,
            responseText: "",
            suggestions: [suggestion],
            deliveryMode: .streamingText,
            diagnostics: plan.diagnostics,
            messageAttribution: JarvisMessageMemoryAttribution(
                usedMemory: false,
                memorySourceIDs: [],
                sourceKinds: [],
                labels: [],
                usedSummary: false,
                chosenSkillID: "summarization"
            )
        )
        let orchestrationResult = JarvisOrchestrationResult(
            request: JarvisOrchestrationRequest(
                id: request.id,
                createdAt: request.createdAt,
                prompt: request.prompt,
                task: request.requestedTask,
                source: request.invocationSource,
                sourceKind: request.sourceKind,
                mode: request.assistantMode,
                conversation: request.conversation,
                routeContext: request.routeContext,
                attachments: request.attachments,
                executionPreferences: request.executionPreferences,
                settingsSnapshot: request.settingsSnapshot
            ),
            normalizedRequest: request,
            executionPlan: plan,
            turnResult: legacyTurnResult,
            classification: .default,
            assistantRequest: JarvisAssistantRequest(
                task: request.requestedTask,
                prompt: request.prompt,
                source: request.invocationSource,
                history: request.conversation.messages,
                tuning: .balanced
            ),
            streamingText: "stream fallback"
        )

        let coreTurnResult = orchestrationResult.coreAssistantTurnResult

        XCTAssertEqual(coreTurnResult.plan.id, plan.id)
        XCTAssertEqual(coreTurnResult.finalizedResponseText(fallbackStreamingText: orchestrationResult.streamingText), "stream fallback")
        XCTAssertEqual(coreTurnResult.suggestions, [suggestion])
        XCTAssertEqual(coreTurnResult.messageAttribution.chosenSkillID, "summarization")
        XCTAssertEqual(orchestrationResult.finalizedTurnResult.plan.id, plan.id)
        XCTAssertEqual(orchestrationResult.finalizedResponseText(), "stream fallback")
        XCTAssertEqual(orchestrationResult.resultPlan.id, plan.id)
        XCTAssertEqual(orchestrationResult.resultDiagnostics, plan.diagnostics)
        XCTAssertEqual(orchestrationResult.resultSuggestions, [suggestion])
        XCTAssertEqual(orchestrationResult.resultMessageAttribution.chosenSkillID, "summarization")
    }

    func testTurnResultKeepsExecutionTraceForMigratedLaneConsumers() {
        let request = makeNormalizedAssistantRequest(prompt: "Respond with steps", task: .chat)
        let plan = JarvisAssistantExecutionPlan(
            request: request,
            detectedTask: .chat,
            classification: .default,
            elevatedRequest: makeElevatedRequest(),
            mode: .directResponse,
            responseStyle: .balanced,
            deliveryMode: .streamingText,
            selectedModelLane: .localFast,
            steps: [],
            diagnostics: JarvisAssistantDecisionTrace(
                selectedMode: .directResponse,
                reasoning: ["Direct response"],
                usedExistingPromptPipeline: true
            )
        )
        var turnResult = JarvisAssistantTurnResult(
            request: request,
            plan: plan,
            assistantRequest: nil,
            responseText: "Done.",
            deliveryMode: .streamingText,
            diagnostics: plan.diagnostics
        )
        let trace = ExecutionTrace(
            requestID: request.id,
            planID: plan.id,
            lane: .localFast,
            steps: [],
            status: .success
        )

        turnResult.executionTrace = trace

        XCTAssertEqual(turnResult.executionTrace, trace)
    }

    func testOrchestrationResultFinalizedResponseUsesTurnResultBeforeRuntimeFallback() {
        let request = makeNormalizedAssistantRequest(prompt: "Answer", task: .chat)
        let plan = JarvisAssistantExecutionPlan(
            request: request,
            detectedTask: .chat,
            classification: .default,
            elevatedRequest: makeElevatedRequest(),
            mode: .directResponse,
            responseStyle: .balanced,
            deliveryMode: .streamingText,
            selectedModelLane: .localFast,
            steps: [],
            diagnostics: JarvisAssistantDecisionTrace(
                selectedMode: .directResponse,
                reasoning: ["Direct response"],
                usedExistingPromptPipeline: true
            )
        )
        let turnResult = JarvisAssistantTurnResult(
            request: request,
            plan: plan,
            assistantRequest: nil,
            responseText: "Final response",
            deliveryMode: .streamingText,
            diagnostics: plan.diagnostics
        )
        let orchestrationResult = JarvisOrchestrationResult(
            request: JarvisOrchestrationRequest(
                id: request.id,
                createdAt: request.createdAt,
                prompt: request.prompt,
                task: request.requestedTask,
                source: request.invocationSource,
                sourceKind: request.sourceKind,
                mode: request.assistantMode,
                conversation: request.conversation,
                routeContext: request.routeContext,
                attachments: request.attachments,
                executionPreferences: request.executionPreferences,
                settingsSnapshot: request.settingsSnapshot
            ),
            normalizedRequest: request,
            executionPlan: plan,
            turnResult: turnResult,
            classification: .default,
            assistantRequest: JarvisAssistantRequest(
                task: request.requestedTask,
                prompt: request.prompt,
                source: request.invocationSource,
                history: request.conversation.messages,
                tuning: .balanced
            ),
            streamingText: "draft fallback"
        )

        XCTAssertEqual(
            orchestrationResult.finalizedResponseText(runtimeStreamingText: "runtime fallback"),
            "Final response"
        )
    }

    @MainActor
    func testMemoryAwareOrchestrationCarriesAttributionThroughTurnResult() async throws {
        let engine = TestGGUFEngine()
        let runtime = JarvisLocalModelRuntime(engine: engine)
        let modelURL = try temporaryGGUFURL(named: "memory-attribution")
        runtime.setSelectedModel(
            JarvisRuntimeModelSelection(
                id: UUID(),
                displayName: "Memory Attribution Model",
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

        let orchestrator = JarvisTaskOrchestrator(runtime: runtime)
        let conversation = JarvisConversationRecord(
            title: "Memory Context",
            updatedAt: Date(),
            messages: [
                JarvisChatMessage(role: .user, text: "Remember that I prefer concise answers."),
                JarvisChatMessage(role: .assistant, text: "I will keep things concise.")
            ]
        )
        let request = JarvisOrchestrationRequest(
            prompt: "What should you keep in mind?",
            task: .chat,
            source: "test",
            sourceKind: .chat,
            mode: .general,
            conversation: conversation,
            settingsSnapshot: .default
        )

        let expectation = expectation(description: "memory attribution")
        var result: JarvisOrchestrationResult?

        orchestrator.orchestrate(request: request, onComplete: { completed in
            result = completed
            expectation.fulfill()
        })

        await fulfillment(of: [expectation], timeout: 2.0)

        let completed = try XCTUnwrap(result)

        XCTAssertEqual(completed.executionPlan.mode, .memoryAugmentedResponse)
        XCTAssertEqual(completed.turnResult.requestID, completed.normalizedRequest.id)
        XCTAssertTrue(completed.turnResult.messageAttribution.usedMemory)
        XCTAssertNotNil(completed.turnResult.messageAttribution.chosenSkillID)
    }

    @MainActor
    func testPassiveObserverRunsAfterMigratedDirectResponseCompletion() async {
        let engine = TestGGUFEngine()
        let runtime = JarvisLocalModelRuntime(engine: engine)
        let executionRuntime = TestExecutionRuntime(tokens: ["hello"])
        let observer = SpyPassiveTurnObserver()
        let orchestrator = JarvisTaskOrchestrator(
            runtime: runtime,
            executionRuntime: executionRuntime,
            passiveTurnObserver: observer
        )
        let request = JarvisOrchestrationRequest(
            prompt: "Say hello",
            task: .chat,
            source: "test",
            sourceKind: .chat,
            mode: .general,
            conversation: JarvisConversationRecord(),
            settingsSnapshot: .default
        )

        let expectation = expectation(description: "passive observer direct")
        var result: JarvisOrchestrationResult?

        orchestrator.orchestrate(request: request, onComplete: { completed in
            result = completed
            expectation.fulfill()
        })

        await fulfillment(of: [expectation], timeout: 2.0)

        let completed = try? XCTUnwrap(result)
        XCTAssertEqual(completed?.turnResult.responseText, "hello")
        XCTAssertEqual(observer.observations.count, 1)
        XCTAssertEqual(observer.observations.first?.requestID, completed?.normalizedRequest.id)
        XCTAssertEqual(observer.observations.first?.planID, completed?.executionPlan.id)
        XCTAssertEqual(observer.observations.first?.status, .success)
        XCTAssertNotNil(observer.observations.first?.trace)
    }

    @MainActor
    func testPassiveObserverFailureDoesNotAffectMigratedTurnCompletion() async {
        let engine = TestGGUFEngine()
        let runtime = JarvisLocalModelRuntime(engine: engine)
        let executionRuntime = TestExecutionRuntime(tokens: ["safe"])
        let observer = FailingPassiveTurnObserver()
        let orchestrator = JarvisTaskOrchestrator(
            runtime: runtime,
            executionRuntime: executionRuntime,
            passiveTurnObserver: observer
        )
        let request = JarvisOrchestrationRequest(
            prompt: "Answer safely",
            task: .chat,
            source: "test",
            sourceKind: .chat,
            mode: .general,
            conversation: JarvisConversationRecord(),
            settingsSnapshot: .default
        )

        let expectation = expectation(description: "passive observer failure")
        var result: JarvisOrchestrationResult?

        orchestrator.orchestrate(request: request, onComplete: { completed in
            result = completed
            expectation.fulfill()
        })

        await fulfillment(of: [expectation], timeout: 2.0)

        XCTAssertEqual(observer.callCount, 1)
        XCTAssertNil(result?.error)
        XCTAssertEqual(result?.turnResult.responseText, "safe")
        XCTAssertEqual(result?.streamingText, "safe")
    }

    @MainActor
    func testPassiveObserverRunsForMigratedMemoryAwareCompletionWithoutTrace() async throws {
        let engine = TestGGUFEngine()
        let runtime = JarvisLocalModelRuntime(engine: engine)
        let modelURL = try temporaryGGUFURL(named: "memory-passive-observer")
        runtime.setSelectedModel(
            JarvisRuntimeModelSelection(
                id: UUID(),
                displayName: "Memory Passive Model",
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
        let observer = SpyPassiveTurnObserver()
        let orchestrator = JarvisTaskOrchestrator(
            runtime: runtime,
            passiveTurnObserver: observer
        )
        let conversation = JarvisConversationRecord(
            title: "Memory Context",
            updatedAt: Date(),
            messages: [
                JarvisChatMessage(role: .user, text: "Remember that I prefer concise answers."),
                JarvisChatMessage(role: .assistant, text: "I will keep things concise.")
            ]
        )
        let request = JarvisOrchestrationRequest(
            prompt: "What should you keep in mind?",
            task: .chat,
            source: "test",
            sourceKind: .chat,
            mode: .general,
            conversation: conversation,
            settingsSnapshot: .default
        )

        let expectation = expectation(description: "passive observer memory")
        var result: JarvisOrchestrationResult?

        orchestrator.orchestrate(request: request, onComplete: { completed in
            result = completed
            expectation.fulfill()
        })

        await fulfillment(of: [expectation], timeout: 2.0)

        let completed = try XCTUnwrap(result)
        XCTAssertEqual(completed.executionPlan.mode, .memoryAugmentedResponse)
        XCTAssertEqual(observer.observations.count, 1)
        XCTAssertNotNil(observer.observations.first?.trace)
        XCTAssertTrue(observer.observations.first?.messageAttribution.usedMemory == true)
    }

    @MainActor
    func testPassiveObserverRunsForCapabilityFallbackPath() async {
        let engine = TestGGUFEngine()
        let runtime = JarvisLocalModelRuntime(engine: engine)
        let observer = SpyPassiveTurnObserver()
        let orchestrator = JarvisTaskOrchestrator(
            runtime: runtime,
            passiveTurnObserver: observer
        )

        let request = JarvisOrchestrationRequest(
            prompt: "take a screenshot of the screen",
            task: .chat,
            source: "test",
            sourceKind: .chat,
            mode: .general,
            conversation: JarvisConversationRecord(),
            settingsSnapshot: .default
        )

        let expectation = expectation(description: "passive observer skipped")
        var result: JarvisOrchestrationResult?

        orchestrator.orchestrate(request: request, onComplete: { completed in
            result = completed
            expectation.fulfill()
        })

        await fulfillment(of: [expectation], timeout: 2.0)

        XCTAssertEqual(result?.executionPlan.mode, .capabilityAction)
        XCTAssertEqual(result?.turnResult.responseText.contains("screenshot action"), true)
        XCTAssertEqual(observer.observations.count, 1)
        XCTAssertNotNil(observer.observations.first?.trace)
    }

    func testCapabilityExecutorReturnsUnsupportedForMacOSOnlyActionOnIOS() async {
        let executor = JarvisToolBackedCapabilityExecutor(registry: JarvisToolBackedCapabilityRegistry())
        let invocation = CapabilityInvocation(
            requestID: UUID(),
            conversationID: UUID(),
            capabilityID: "app.open",
            input: .appOpen(.init(bundleID: "com.apple.Safari", appURL: nil)),
            typedIntent: JarvisTypedIntent(mode: .action, intent: "app.open", confidence: 0.9),
            policyDecision: nil,
            approvalState: .notRequired
        )

        let result = await executor.execute(invocation)

#if os(iOS)
        XCTAssertEqual(result.status, .unsupported)
        XCTAssertEqual(result.verification, .notApplicable)
#else
        XCTAssertTrue([CapabilityExecutionStatus.success, .failed, .unsupported].contains(result.status))
#endif
    }

    func testCapabilityExecutorReturnsRequiresApprovalStateForDestructiveCapability() async {
        let handler = FixedCapabilityHandler(
            descriptor: CapabilityDescriptor(
                id: "file.patch",
                kind: .filePatch,
                requiresApproval: true,
                allowedContexts: [.foregroundConversation],
                supportsCancellation: false,
                platformAvailability: .shared,
                traceCategory: "filesystem.patch"
            ),
            result: CapabilityResult(
                status: .success,
                userMessage: "patched",
                verification: .verified,
                approvalState: .approved,
                traceDetails: ["capability_id": "file.patch"]
            )
        )
        let executor = JarvisToolBackedCapabilityExecutor(
            registry: FixedCapabilityRegistry(descriptor: handler.descriptor, handler: handler)
        )

        let result = await executor.execute(
            CapabilityInvocation(
                requestID: UUID(),
                conversationID: UUID(),
                capabilityID: "file.patch",
                input: .filePatch(.init(path: .init(token: "/tmp/test.swift"), unifiedDiff: "@@")),
                typedIntent: JarvisTypedIntent(mode: .action, intent: "file.patch", confidence: 1.0),
                policyDecision: nil,
                approvalState: .required
            )
        )

        XCTAssertEqual(result.status, .requiresApproval)
        XCTAssertEqual(result.state.kind, .requiresApproval)
        XCTAssertEqual(result.approvalState, .required)
    }

    func testCapabilityExecutorReturnsDeniedStateWhenApprovalIsDenied() async {
        let handler = FixedCapabilityHandler(
            descriptor: CapabilityDescriptor(
                id: "shell.run.safe",
                kind: .shellRunSafe,
                requiresApproval: true,
                allowedContexts: [.foregroundConversation],
                supportsCancellation: true,
                platformAvailability: .macOSOnly,
                traceCategory: "shell.run.safe"
            ),
            result: CapabilityResult(
                status: .success,
                userMessage: "ran",
                verification: .verified,
                approvalState: .approved,
                traceDetails: ["capability_id": "shell.run.safe"]
            )
        )
        let executor = JarvisToolBackedCapabilityExecutor(
            registry: FixedCapabilityRegistry(descriptor: handler.descriptor, handler: handler)
        )

        let result = await executor.execute(
            CapabilityInvocation(
                requestID: UUID(),
                conversationID: UUID(),
                capabilityID: "shell.run.safe",
                input: .shellRunSafe(.init(command: .pwd, cwd: nil)),
                typedIntent: JarvisTypedIntent(mode: .action, intent: "shell.run.safe", confidence: 1.0),
                policyDecision: nil,
                approvalState: .denied
            )
        )

        XCTAssertEqual(result.status, .denied)
        XCTAssertEqual(result.state.kind, .denied)
        XCTAssertEqual(result.approvalState, .denied)
    }

    @MainActor
    func testCapabilityActionUsesExecutorAndFinalizesObservation() async {
        let engine = TestGGUFEngine()
        let runtime = JarvisLocalModelRuntime(engine: engine)
        let observer = SpyPassiveTurnObserver()
        let executor = SpyCapabilityExecutor(
            result: CapabilityResult(
                status: .success,
                userMessage: "Capability completed.",
                verification: .verified,
                approvalState: .notRequired,
                traceDetails: ["capability_id": "file.search"]
            )
        )
        let orchestrator = JarvisTaskOrchestrator(
            runtime: runtime,
            executionPlanner: FixedExecutionPlanner(
                mode: .capabilityAction,
                selectedModelLane: .localFast,
                selectedCapabilityID: "file.search",
                capabilityApprovalRequired: false,
                capabilityPlatformAvailability: .shared
            ),
            passiveTurnObserver: observer,
            capabilityRegistry: FixedCapabilityRegistry(
                descriptor: CapabilityDescriptor(
                    id: "file.search",
                    kind: .fileSearch,
                    requiresApproval: false,
                    allowedContexts: [.foregroundConversation],
                    supportsCancellation: false,
                    platformAvailability: .shared,
                    traceCategory: "filesystem.search"
                )
            ),
            capabilityExecutor: executor
        )

        let request = JarvisOrchestrationRequest(
            prompt: "search files for swift",
            task: .chat,
            source: "test",
            sourceKind: .chat,
            mode: .general,
            conversation: JarvisConversationRecord(),
            settingsSnapshot: .default
        )

        let expectation = expectation(description: "capability executor")
        var result: JarvisOrchestrationResult?

        orchestrator.orchestrate(request: request, onComplete: { completed in
            result = completed
            expectation.fulfill()
        })

        await fulfillment(of: [expectation], timeout: 2.0)

        XCTAssertEqual(engine.loadCount, 0)
        XCTAssertEqual(executor.invocations.count, 1)
        XCTAssertEqual(result?.turnResult.responseText, "Capability completed.")
        XCTAssertEqual(result?.turnResult.capabilityState?.kind, .success)
        XCTAssertNotNil(result?.turnResult.executionTrace)
        XCTAssertEqual(observer.observations.count, 1)
    }

    @MainActor
    func testFileSearchCapabilityActionProducesStructuredCapabilityState() async {
        let engine = TestGGUFEngine()
        let runtime = JarvisLocalModelRuntime(engine: engine)
        let observer = SpyPassiveTurnObserver()
        let searchOutput = CapabilityOutputPayload.fileSearch(
            .init(
                matches: [
                    .init(
                        path: "/tmp/App.swift",
                        name: "App.swift",
                        fileExtension: "swift",
                        size: 512,
                        lastModified: Date(timeIntervalSince1970: 1_700_000_000)
                    )
                ],
                truncated: false
            )
        )
        let executor = SpyCapabilityExecutor(
            result: CapabilityResult(
                status: .success,
                userMessage: "Found 1 file.",
                output: searchOutput,
                verification: .verified,
                approvalState: .notRequired,
                state: .init(
                    capabilityID: "file.search",
                    kind: .success,
                    approvalState: .notRequired,
                    verification: .verified,
                    output: searchOutput,
                    statusMessage: "Found 1 file.",
                    traceDetails: ["capability_id": "file.search"]
                ),
                traceDetails: ["capability_id": "file.search"]
            )
        )
        let orchestrator = JarvisTaskOrchestrator(
            runtime: runtime,
            executionPlanner: FixedExecutionPlanner(
                mode: .capabilityAction,
                selectedModelLane: .localFast,
                selectedCapabilityID: "file.search",
                capabilityApprovalRequired: false,
                capabilityPlatformAvailability: .shared
            ),
            passiveTurnObserver: observer,
            capabilityRegistry: FixedCapabilityRegistry(
                descriptor: CapabilityDescriptor(
                    id: "file.search",
                    kind: .fileSearch,
                    requiresApproval: false,
                    allowedContexts: [.foregroundConversation],
                    supportsCancellation: false,
                    platformAvailability: .shared,
                    traceCategory: "filesystem.search"
                )
            ),
            capabilityExecutor: executor
        )

        let request = JarvisOrchestrationRequest(
            prompt: "search files for App.swift",
            task: .chat,
            source: "test",
            sourceKind: .chat,
            mode: .general,
            conversation: JarvisConversationRecord(),
            settingsSnapshot: .default
        )

        let expectation = expectation(description: "file search capability")
        var result: JarvisOrchestrationResult?

        orchestrator.orchestrate(request: request, onComplete: { completed in
            result = completed
            expectation.fulfill()
        })

        await fulfillment(of: [expectation], timeout: 2.0)

        guard case .fileSearch(let output)? = result?.turnResult.capabilityState?.output else {
            return XCTFail("Expected structured file search output")
        }
        XCTAssertEqual(output.matches.first?.path, "/tmp/App.swift")
        XCTAssertEqual(result?.turnResult.capabilityState?.kind, .success)
        XCTAssertEqual(result?.turnResult.capabilitySurfaces.first?.kind, .fileSearchResults)
        XCTAssertEqual(result?.turnResult.capabilitySurfaces.first?.entries.first?.title, "App.swift")
        XCTAssertEqual(observer.observations.count, 1)
    }

    func testAssistantOutputFormatterReturnsCapabilitySurfacesWithoutTextCards() {
        let surfaces = [
            JarvisAssistantCapabilitySurface(
                kind: .shellResult,
                title: "Shell Result",
                status: .success,
                summary: "Command completed.",
                entries: [
                    JarvisAssistantCapabilityEntry(
                        title: "pwd",
                        subtitle: "/tmp",
                        facts: [JarvisAssistantCapabilityFact(label: "Exit Code", value: "0")]
                    )
                ]
            )
        ]

        let output = JarvisAssistantOutputFormatter.format(
            text: "   ",
            classification: .default,
            memoryContext: MemoryContext(),
            capabilitySurfaces: surfaces
        )

        XCTAssertEqual(output?.cards.count, 0)
        XCTAssertEqual(output?.capabilitySurfaces, surfaces)
    }

    func testCapabilityFormatterBuildsPendingPatchApprovalSurface() {
        let surfaces = JarvisAssistantCapabilityFormatter.format(
            capabilityID: "file.patch",
            input: .filePatch(.init(path: .init(token: "/tmp/Notes.md", displayPath: "/tmp/Notes.md"), unifiedDiff: "@@")),
            result: CapabilityResult(
                status: .requiresApproval,
                userMessage: "Patch preview ready. Approval required.",
                approvalState: .required,
                traceDetails: ["capability_id": "file.patch"]
            ),
            platformAvailability: .shared
        )

        XCTAssertEqual(surfaces.count, 1)
        XCTAssertEqual(surfaces.first?.kind, .patchApproval)
        XCTAssertEqual(surfaces.first?.status, .pending)
        XCTAssertEqual(surfaces.first?.approval?.scenarioID, "file.patch")
        XCTAssertEqual(surfaces.first?.entries.first?.subtitle, "/tmp/Notes.md")
    }

    @MainActor
    func testPassiveObserverRunsForPlatformOnlyPath() async {
        let engine = TestGGUFEngine()
        let runtime = JarvisLocalModelRuntime(engine: engine)
        let observer = SpyPassiveTurnObserver()
        let orchestrator = JarvisTaskOrchestrator(
            runtime: runtime,
            passiveTurnObserver: observer
        )

        let request = JarvisOrchestrationRequest(
            prompt: "hi",
            task: .chat,
            source: "test",
            sourceKind: .chat,
            mode: .general,
            conversation: JarvisConversationRecord(),
            settingsSnapshot: .default
        )

        let expectation = expectation(description: "platform-only observer")
        var result: JarvisOrchestrationResult?

        orchestrator.orchestrate(request: request, onComplete: { completed in
            result = completed
            expectation.fulfill()
        })

        await fulfillment(of: [expectation], timeout: 2.0)

        XCTAssertEqual(result?.streamingText, "Hey. Send me what you need.")
        XCTAssertEqual(observer.observations.count, 1)
        XCTAssertNotNil(observer.observations.first?.trace)
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

    private func makeNormalizedAssistantRequest(
        prompt: String,
        task: JarvisAssistantTask
    ) -> JarvisNormalizedAssistantRequest {
        let conversation = JarvisConversationRecord(
            title: "Test Conversation",
            updatedAt: Date(),
            messages: []
        )
        return JarvisNormalizedAssistantRequest(
            createdAt: Date(timeIntervalSince1970: 1_234),
            prompt: prompt,
            requestedTask: task,
            invocationSource: "test",
            sourceKind: .chat,
            assistantMode: .general,
            conversationID: conversation.id,
            conversation: conversation,
            routeContext: JarvisAssistantRouteContext(),
            settingsSnapshot: .default
        )
    }

    private func makeElevatedRequest() -> JarvisElevatedRequest {
        JarvisElevatedRequest(
            kind: .actionRequest,
            elevatedIntent: "test_intent",
            elevatedPrompt: "test prompt",
            responseContract: JarvisResponseContract()
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

    private func makeFileAccessDefaults() -> UserDefaults {
        let suiteName = "JarvisIOSTests.FileAccess.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    private func makeTemporaryDirectory(named name: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString)-\(name)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

@MainActor
private final class SpyExecutionPlanBuilder: JarvisExecutionPlanBuilding {
    private(set) var recordedRequestID: UUID?
    private(set) var recordedRouteDecision: JarvisRouteDecision?
    private(set) var recordedPolicyDecision: JarvisPolicyDecision?
    private(set) var recordedSelectedModelLane: JarvisModelLane?
    private(set) var recordedSelectedSkillID: String?

    func makePlan(
        for request: JarvisNormalizedAssistantRequest,
        classification: JarvisTaskClassification,
        memoryContextAvailable: Bool,
        elevatedRequest: JarvisElevatedRequest,
        routeDecision: JarvisRouteDecision?,
        policyDecision: JarvisPolicyDecision?,
        selectedModelLane: JarvisModelLane?,
        selectedSkillID: String?
    ) async -> JarvisAssistantExecutionPlan {
        recordedRequestID = request.id
        recordedRouteDecision = routeDecision
        recordedPolicyDecision = policyDecision
        recordedSelectedModelLane = selectedModelLane
        recordedSelectedSkillID = selectedSkillID

        return JarvisAssistantExecutionPlan(
            request: request,
            detectedTask: classification.task,
            classification: classification,
            elevatedRequest: elevatedRequest,
            mode: .directResponse,
            responseStyle: .balanced,
            deliveryMode: .streamingText,
            routeDecision: routeDecision,
            policyDecision: policyDecision,
            selectedModelLane: selectedModelLane,
            steps: [],
            diagnostics: JarvisAssistantDecisionTrace(
                selectedMode: .directResponse,
                selectedModelLane: selectedModelLane?.rawValue,
                policyReason: policyDecision?.reason,
                chosenSkillID: selectedSkillID,
                reasoning: [],
                usedExistingPromptPipeline: true
            )
        )
    }
}

@MainActor
private struct FixedExecutionPlanner: ExecutionPlanner {
    let mode: JarvisAssistantExecutionMode
    let selectedModelLane: JarvisModelLane?
    let selectedCapabilityID: CapabilityID?
    let capabilityApprovalRequired: Bool
    let capabilityPlatformAvailability: CapabilityPlatformAvailability?

    init(
        mode: JarvisAssistantExecutionMode,
        selectedModelLane: JarvisModelLane?,
        selectedCapabilityID: CapabilityID? = nil,
        capabilityApprovalRequired: Bool = false,
        capabilityPlatformAvailability: CapabilityPlatformAvailability? = nil
    ) {
        self.mode = mode
        self.selectedModelLane = selectedModelLane
        self.selectedCapabilityID = selectedCapabilityID
        self.capabilityApprovalRequired = capabilityApprovalRequired
        self.capabilityPlatformAvailability = capabilityPlatformAvailability
    }

    func makePlan(
        for request: JarvisNormalizedAssistantRequest,
        classification: JarvisTaskClassification,
        memoryContextAvailable: Bool,
        elevatedRequest: JarvisElevatedRequest,
        resolvedSkill: JarvisResolvedSkill
    ) async -> JarvisAssistantExecutionPlan {
        _ = memoryContextAvailable
        let steps: [JarvisAssistantExecutionStep] = {
            if mode == .capabilityAction || mode == .capabilityThenRespond {
                return [
                    JarvisAssistantExecutionStep(
                        kind: .normalizeRequest,
                        title: "Normalize Request",
                        detail: "test",
                        usesModel: false
                    ),
                    JarvisAssistantExecutionStep(
                        kind: .inspectCapabilities,
                        title: "Inspect Capabilities",
                        detail: "test",
                        usesModel: false
                    ),
                    JarvisAssistantExecutionStep(
                        kind: .finalizeTurn,
                        title: "Finalize Turn",
                        detail: "test",
                        usesModel: false
                    )
                ]
            }

            return [
                JarvisAssistantExecutionStep(
                    kind: .normalizeRequest,
                    title: "Normalize Request",
                    detail: "test",
                    usesModel: false
                ),
                JarvisAssistantExecutionStep(
                    kind: .infer,
                    title: "Generate Response",
                    detail: "test",
                    usesModel: true
                ),
                JarvisAssistantExecutionStep(
                    kind: .finalizeTurn,
                    title: "Finalize Turn",
                    detail: "test",
                    usesModel: false
                )
            ]
        }()

        return JarvisAssistantExecutionPlan(
            request: request,
            detectedTask: classification.task,
            classification: classification,
            elevatedRequest: elevatedRequest,
            mode: mode,
            responseStyle: request.assistantMode.defaultResponseStyle,
            deliveryMode: .streamingText,
            routeDecision: JarvisRouteDecision(
                typedIntent: JarvisTypedIntent(
                    mode: mode == .capabilityAction || mode == .capabilityThenRespond ? .action : .respond,
                    intent: selectedCapabilityID?.rawValue ?? elevatedRequest.elevatedIntent,
                    confidence: classification.confidence
                ),
                selectedSkillID: resolvedSkill.skill.id,
                lane: selectedModelLane ?? .localFast,
                reason: "fixed-test-plan"
            ),
            policyDecision: JarvisPolicyDecision(
                isAllowed: true,
                riskLevel: .low,
                reason: "fixed-test-plan"
            ),
            selectedModelLane: selectedModelLane,
            selectedCapabilityID: selectedCapabilityID,
            capabilityApprovalRequired: capabilityApprovalRequired,
            capabilityPlatformAvailability: capabilityPlatformAvailability,
            steps: steps,
            diagnostics: JarvisAssistantDecisionTrace(
                selectedMode: mode,
                selectedModelLane: selectedModelLane?.rawValue,
                chosenSkillID: resolvedSkill.skill.id,
                reasoning: ["fixed-test-plan"],
                usedExistingPromptPipeline: true
            )
        )
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

    func generate(
        request: JarvisAssistantRequest,
        onToken: @escaping @Sendable (String) -> Void
    ) async throws -> JarvisRuntimeGenerationOutcome {
        _ = request
        _ = configuration
        onToken("ok")
        return JarvisRuntimeGenerationOutcome(
            stopReason: .normal,
            requestedContextTokenLimit: 768,
            effectiveContextTokenLimit: 768,
            effectiveOutputTokenLimit: 220,
            promptTokenEstimate: 16
        )
    }

    func cancelGeneration() {}
}

@MainActor
private final class SpyMemoryBoundary: MemoryBoundary {
    private(set) var prepareCallCount = 0
    private(set) var recordCallCount = 0
    private(set) var recordedResponseText: String?
    private(set) var recordedRequestID: UUID?
    let snapshot: MemorySnapshot

    init(snapshot: MemorySnapshot) {
        self.snapshot = snapshot
    }

    func prepare(request: MemoryBoundaryRequest) async -> MemorySnapshot {
        recordedRequestID = request.request.id
        prepareCallCount += 1
        return snapshot
    }

    func record(request: MemoryBoundaryRequest, result: AssistantTurnResult) async {
        recordedRequestID = request.request.id
        recordCallCount += 1
        recordedResponseText = result.responseText
    }
}

@MainActor
private final class TestExecutionRuntime: ExecutionRuntime {
    private let tokens: [String]
    private let stopReason: JarvisRuntimeGenerationStopReason

    private(set) var prepareCount = 0
    private(set) var streamCount = 0
    private(set) var cancelCount = 0

    init(tokens: [String], stopReason: JarvisRuntimeGenerationStopReason = .eos) {
        self.tokens = tokens
        self.stopReason = stopReason
    }

    func prepareIfNeeded(tuning: JarvisGenerationTuning?) async throws {
        _ = tuning
        prepareCount += 1
    }

    func streamResponse(request: JarvisAssistantRequest) -> AsyncThrowingStream<String, Error> {
        _ = request
        streamCount += 1
        let tokens = self.tokens
        return AsyncThrowingStream { continuation in
            for token in tokens {
                continuation.yield(token)
            }
            continuation.finish()
        }
    }

    func cancel() {
        cancelCount += 1
    }

    var lastGenerationStopReason: JarvisRuntimeGenerationStopReason? {
        stopReason
    }
}

@MainActor
private final class SpyPassiveTurnObserver: JarvisPassiveTurnObserving {
    private(set) var observations: [JarvisCompletedTurnObservation] = []

    func observe(_ observation: JarvisCompletedTurnObservation) async throws {
        observations.append(observation)
    }
}

private struct FixedCapabilityRegistry: CapabilityRegistry {
    let descriptor: CapabilityDescriptor
    var handler: (any CapabilityHandler)? = nil

    func descriptor(for id: CapabilityID) -> CapabilityDescriptor? {
        descriptor.id == id ? descriptor : nil
    }

    func handler(for id: CapabilityID) -> (any CapabilityHandler)? {
        descriptor.id == id ? handler : nil
    }
}

private struct FixedCapabilityHandler: CapabilityHandler {
    let descriptor: CapabilityDescriptor
    let result: CapabilityResult

    func execute(_ invocation: CapabilityInvocation) async throws -> CapabilityResult {
        _ = invocation
        return result
    }
}

private final class SpyCapabilityExecutor: CapabilityExecutor {
    private(set) var invocations: [CapabilityInvocation] = []
    let result: CapabilityResult

    init(result: CapabilityResult) {
        self.result = result
    }

    func execute(_ invocation: CapabilityInvocation) async -> CapabilityResult {
        invocations.append(invocation)
        return result
    }
}

@MainActor
private final class FailingPassiveTurnObserver: JarvisPassiveTurnObserving {
    private(set) var callCount = 0

    func observe(_ observation: JarvisCompletedTurnObservation) async throws {
        _ = observation
        callCount += 1
        throw Failure()
    }

    private struct Failure: Error {}
}
