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
            hapticsEnabled: false
        )

        store.save(settings)
        XCTAssertEqual(store.load(), settings)
    }

    func testLaunchRouteParsesModelLibraryRoute() throws {
        let route = try XCTUnwrap(JarvisLaunchRoute.parse(url: XCTUnwrap(URL(string: "jarvis://models?source=test"))))
        XCTAssertEqual(route.action, .modelLibrary)
        XCTAssertEqual(route.source, "test")
    }

    @MainActor
    func testAskRouteWithoutModelShowsSetupInsteadOfDeadEnd() {
        let appModel = makeAppModel()

        appModel.apply(route: JarvisLaunchRoute(action: .ask, source: "test"))

        XCTAssertTrue(appModel.showSetupFlow)
        XCTAssertEqual(appModel.selectedTab, .home)
        XCTAssertEqual(appModel.statusText, "Import and activate a local model to continue")
    }

    @MainActor
    func testModelLibraryRoutePresentsLibraryFromSettings() {
        let appModel = makeAppModel()

        appModel.apply(route: JarvisLaunchRoute(action: .modelLibrary, source: "test"))

        XCTAssertEqual(appModel.selectedTab, .settings)
        XCTAssertTrue(appModel.isModelLibraryPresented)
    }

    func testSupportedModelCatalogMatchesGemmaGoldPathFilename() {
        let assessment = JarvisSupportedModelCatalog.assess(
            filename: "gemma-3-4b-it-q4_0.gguf",
            fileSizeBytes: 3_400_000_000,
            format: .gguf
        )

        XCTAssertEqual(assessment.status, .ready)
        XCTAssertEqual(assessment.supportedProfileID, .gemma3_4b_it_q4_0)
    }

    func testModelLibraryImportStoresBookmarkAndDoesNotAutoActivate() throws {
        let suffix = UUID().uuidString
        let library = JarvisModelLibrary(payloadFilename: "JarvisModelLibrary-\(suffix).json")
        let supportedURL = try temporarySparseGGUFURL(
            named: "gemma-3-4b-it-q4_0",
            size: 3_400_000_000
        )

        let imported = try library.importModel(from: supportedURL)

        XCTAssertEqual(imported.status, .ready)
        XCTAssertEqual(imported.supportedProfileID, .gemma3_4b_it_q4_0)
        XCTAssertEqual(imported.primaryAsset.storageKind, .securityScopedBookmark)
        XCTAssertNotNil(imported.primaryAsset.bookmarkData)
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

        XCTAssertEqual(imported.status, .ready)
        XCTAssertNil(imported.supportedProfileID)
        XCTAssertEqual(imported.family, .qwen)
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
        XCTAssertEqual(updated.projectorAsset?.storageKind, .securityScopedBookmark)
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

    func loadModel(at path: String, projectorPath: String?) async throws {
        loadCount += 1
        loadedPath = path
        loadedProjectorPath = projectorPath
    }

    func unloadModel() async {
        loadedPath = nil
        loadedProjectorPath = nil
    }

    func generate(prompt: String, history: [JarvisChatMessage], onToken: @escaping @Sendable (String) -> Void) async throws {
        _ = prompt
        _ = history
        _ = configuration
        onToken("ok")
    }

    func cancelGeneration() {}
}
