import XCTest
@testable import JarvisIOS

final class JarvisIOSTests: XCTestCase {
    @MainActor
    func testRuntimeTransitionsFromColdToReady() async throws {
        let engine = TestGGUFEngine()
        let runtime = JarvisLocalModelRuntime(engine: engine)
        let modelURL = try temporaryGGUFURL(named: "runtime-ready")

        runtime.setSelectedModel(
            JarvisRuntimeModelSelection(displayName: "Test Model", path: modelURL.path)
        )
        XCTAssertEqual(runtime.state, .cold(modelName: "Test Model"))

        try await runtime.prepareIfNeeded()
        XCTAssertEqual(runtime.state, .ready(modelName: "Test Model"))
        XCTAssertEqual(engine.loadCount, 1)
    }

    func testSettingsStoreRoundTripsMeaningfulPreferences() throws {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let store = JarvisAssistantSettingsStore(defaults: defaults)
        let settings = JarvisAssistantSettings(
            startupRoute: .assistant,
            autoWarmOnLaunch: true,
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
        XCTAssertEqual(appModel.statusText, "Import a GGUF model to continue")
    }

    @MainActor
    func testModelLibraryRoutePresentsLibraryFromSettings() {
        let appModel = makeAppModel()

        appModel.apply(route: JarvisLaunchRoute(action: .modelLibrary, source: "test"))

        XCTAssertEqual(appModel.selectedTab, .settings)
        XCTAssertTrue(appModel.isModelLibraryPresented)
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
        try Data("test".utf8).write(to: url, options: [.atomic])
        return url
    }
}

private final class TestGGUFEngine: JarvisGGUFEngine {
    var name: String { "test-engine" }
    var isInstalled: Bool { true }
    var capability: JarvisGGUFEngineCapability { .fullInference }

    private(set) var loadCount = 0
    private(set) var loadedPath: String?
    private var configuration = JarvisRuntimeConfiguration()

    func updateConfiguration(_ configuration: JarvisRuntimeConfiguration) {
        self.configuration = configuration
    }

    func loadModel(at path: String) async throws {
        loadCount += 1
        loadedPath = path
    }

    func unloadModel() async {
        loadedPath = nil
    }

    func generate(prompt: String, history: [JarvisChatMessage], onToken: @escaping @Sendable (String) -> Void) async throws {
        _ = prompt
        _ = history
        _ = configuration
        onToken("ok")
    }

    func cancelGeneration() {}
}
