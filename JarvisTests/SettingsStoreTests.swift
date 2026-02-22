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
