import XCTest
@testable import Jarvis

final class SettingsStoreTests: XCTestCase {
    func testPersistTone() {
        guard let defaults = UserDefaults(suiteName: "com.jarvis.tests") else {
            XCTFail("Missing suite"); return
        }
        defaults.removePersistentDomain(forName: "com.jarvis.tests")
        let store = SettingsStore(defaults: defaults)
        store.setTone(.friendly)
        XCTAssertEqual(store.tone(), .friendly)
    }
}

final class RoutingIsolationTests: XCTestCase {
    private let classifier = IntentClassifier()
    private let planner = RoutePlanner()

    func testIntentClassificationForSearchAndDiagnostics() {
        let searchSignal = RouteSignal(selectedSurface: .chat, quickActionKind: nil, hasImportedDocument: false, hasClipboardText: false, hasIndexedFolders: true)
        let searchIntent = classifier.classify(prompt: "find my latest invoice pdf", signal: searchSignal)
        XCTAssertEqual(searchIntent.intent, .searchQuery)

        let diagnosticsSignal = RouteSignal(selectedSurface: .why, quickActionKind: nil, hasImportedDocument: false, hasClipboardText: false, hasIndexedFolders: false)
        let diagnosticsIntent = classifier.classify(prompt: "why did this happen after the last update", signal: diagnosticsSignal)
        XCTAssertEqual(diagnosticsIntent.intent, .diagnosticsQuery)
    }

    func testRouteSelectionUsesIntentSpecificPromptAndTools() {
        let signal = RouteSignal(selectedSurface: .fileSearch, quickActionKind: nil, hasImportedDocument: false, hasClipboardText: false, hasIndexedFolders: true)
        let classification = IntentClassification(intent: .searchQuery, confidence: 0.9, reasons: ["explicit file lookup"])
        let plan = planner.makePlan(classification: classification, signal: signal)

        XCTAssertEqual(plan.promptTemplate, .searchAssistant)
        XCTAssertEqual(plan.memoryScope, .searchTransient)
        XCTAssertTrue(plan.allowedTools.contains(.searchLocalDocs))
        XCTAssertFalse(plan.allowedTools.contains(.ocrCurrentWindow))
    }

    func testMemoryIsolationAcrossModes() {
        let mailSignal = RouteSignal(selectedSurface: .email, quickActionKind: nil, hasImportedDocument: false, hasClipboardText: true, hasIndexedFolders: false)
        let mailPlan = planner.makePlan(classification: IntentClassification(intent: .mailDraft, confidence: 0.8, reasons: []), signal: mailSignal)

        let chatSignal = RouteSignal(selectedSurface: .chat, quickActionKind: nil, hasImportedDocument: false, hasClipboardText: false, hasIndexedFolders: false)
        let chatPlan = planner.makePlan(classification: IntentClassification(intent: .generalChat, confidence: 0.6, reasons: []), signal: chatSignal)

        XCTAssertEqual(mailPlan.memoryScope, .mailSession)
        XCTAssertEqual(chatPlan.memoryScope, .chatThread)
        XCTAssertNotEqual(mailPlan.memoryScope, chatPlan.memoryScope)
        XCTAssertNotEqual(mailPlan.promptTemplate, chatPlan.promptTemplate)
    }

    func testQuickActionDoesNotHijackNormalChatClassification() {
        let normalSignal = RouteSignal(selectedSurface: .chat, quickActionKind: nil, hasImportedDocument: false, hasClipboardText: false, hasIndexedFolders: false)
        let normalIntent = classifier.classify(prompt: "help me summarize this architecture", signal: normalSignal)
        XCTAssertNotEqual(normalIntent.intent, .quickActionCommand)

        let quickSignal = RouteSignal(selectedSurface: .chat, quickActionKind: .summarizeClipboard, hasImportedDocument: false, hasClipboardText: true, hasIndexedFolders: false)
        let quickIntent = classifier.classify(prompt: "Summarize this clipboard content", signal: quickSignal)
        XCTAssertEqual(quickIntent.intent, .quickActionCommand)
    }

    func testDiagnosticsRouteUsesDiagnosticsPromptTemplate() {
        let signal = RouteSignal(selectedSurface: .diagnostics, quickActionKind: nil, hasImportedDocument: false, hasClipboardText: false, hasIndexedFolders: false)
        let plan = planner.makePlan(classification: IntentClassification(intent: .diagnosticsQuery, confidence: 0.85, reasons: []), signal: signal)
        XCTAssertEqual(plan.promptTemplate, .diagnostics)
        XCTAssertEqual(plan.memoryScope, .diagnosticsTask)
        XCTAssertFalse(plan.allowedTools.contains(.searchLocalDocs))
    }

    func testStreamOwnershipCancelsStaleRequests() {
        var controller = StreamOwnershipController()
        let chatPlan = planner.makePlan(
            classification: IntentClassification(intent: .generalChat, confidence: 0.7, reasons: []),
            signal: RouteSignal(selectedSurface: .chat, quickActionKind: nil, hasImportedDocument: false, hasClipboardText: false, hasIndexedFolders: false)
        )
        let first = controller.begin(conversationID: UUID(), routePlan: chatPlan)
        XCTAssertTrue(controller.owns(first.requestID))

        let second = controller.begin(conversationID: UUID(), routePlan: chatPlan)
        XCTAssertFalse(controller.owns(first.requestID))
        XCTAssertTrue(controller.owns(second.requestID))

        controller.complete(requestID: first.requestID)
        XCTAssertTrue(controller.owns(second.requestID))

        controller.complete(requestID: second.requestID)
        XCTAssertFalse(controller.owns(second.requestID))
    }

    func testTabSwitchAndStalePublishingSemantics() {
        var controller = StreamOwnershipController()
        let plan = planner.makePlan(
            classification: IntentClassification(intent: .generalChat, confidence: 0.7, reasons: []),
            signal: RouteSignal(selectedSurface: .chat, quickActionKind: nil, hasImportedDocument: false, hasClipboardText: false, hasIndexedFolders: false)
        )
        let active = controller.begin(conversationID: UUID(), routePlan: plan)
        XCTAssertTrue(controller.owns(active.requestID))

        _ = controller.cancelActive()
        XCTAssertFalse(controller.owns(active.requestID))
    }

    func testScopedMessagesExcludeTransientModesFromGeneralChat() {
        let chatPlan = planner.makePlan(
            classification: IntentClassification(intent: .generalChat, confidence: 0.7, reasons: []),
            signal: RouteSignal(selectedSurface: .chat, quickActionKind: nil, hasImportedDocument: false, hasClipboardText: false, hasIndexedFolders: false)
        )
        let searchPlan = planner.makePlan(
            classification: IntentClassification(intent: .searchQuery, confidence: 0.9, reasons: []),
            signal: RouteSignal(selectedSurface: .fileSearch, quickActionKind: nil, hasImportedDocument: false, hasClipboardText: false, hasIndexedFolders: true)
        )

        let conversation = Conversation(
            title: "Scoped",
            model: "local",
            messages: [
                ChatMessage(role: .user, text: "chat-1", metadata: ["memoryScope": MemoryScope.chatThread.rawValue]),
                ChatMessage(role: .assistant, text: "chat-2", metadata: ["memoryScope": MemoryScope.chatThread.rawValue]),
                ChatMessage(role: .user, text: "search-1", metadata: ["memoryScope": MemoryScope.searchTransient.rawValue]),
                ChatMessage(role: .assistant, text: "search-2", metadata: ["memoryScope": MemoryScope.searchTransient.rawValue])
            ]
        )

        let scoped = ConversationScopeFilter.messages(for: conversation, routePlan: chatPlan)
        XCTAssertEqual(scoped.map(\.text), ["chat-1", "chat-2"])
        XCTAssertFalse(scoped.map(\.text).contains("search-1"))
        XCTAssertFalse(scoped.map(\.text).contains("search-2"))
        XCTAssertEqual(searchPlan.memoryScope, .searchTransient)
    }

    func testScopedMessagesForNonChatScopeUseMatchingHistory() {
        let searchPlan = planner.makePlan(
            classification: IntentClassification(intent: .searchQuery, confidence: 0.9, reasons: []),
            signal: RouteSignal(selectedSurface: .fileSearch, quickActionKind: nil, hasImportedDocument: false, hasClipboardText: false, hasIndexedFolders: true)
        )

        let conversation = Conversation(
            title: "Scoped Search",
            model: "local",
            messages: [
                ChatMessage(role: .user, text: "chat turn", metadata: ["memoryScope": MemoryScope.chatThread.rawValue]),
                ChatMessage(role: .assistant, text: "chat answer", metadata: ["memoryScope": MemoryScope.chatThread.rawValue]),
                ChatMessage(role: .user, text: "search turn", metadata: ["memoryScope": MemoryScope.searchTransient.rawValue]),
                ChatMessage(role: .assistant, text: "search answer", metadata: ["memoryScope": MemoryScope.searchTransient.rawValue])
            ]
        )

        let scoped = ConversationScopeFilter.messages(for: conversation, routePlan: searchPlan)
        XCTAssertEqual(scoped.map(\.text), ["search turn", "search answer"])
    }

    func testScopedMessagesLegacyFallbackIncludesLatestUserForNonChat() {
        let diagnosticsPlan = planner.makePlan(
            classification: IntentClassification(intent: .diagnosticsQuery, confidence: 0.8, reasons: []),
            signal: RouteSignal(selectedSurface: .diagnostics, quickActionKind: nil, hasImportedDocument: false, hasClipboardText: false, hasIndexedFolders: false)
        )

        let latestUser = ChatMessage(role: .user, text: "why is this failing")
        let conversation = Conversation(
            title: "Legacy",
            model: "local",
            messages: [
                ChatMessage(role: .assistant, text: "old answer"),
                ChatMessage(role: .user, text: "old question"),
                latestUser
            ]
        )

        let scoped = ConversationScopeFilter.messages(for: conversation, routePlan: diagnosticsPlan)
        XCTAssertEqual(scoped.count, 1)
        XCTAssertEqual(scoped.first?.id, latestUser.id)
    }
}
