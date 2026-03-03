import XCTest
@testable import AliceMac

final class ShortcutSettingsStoreTests: XCTestCase {
    func testLoadReturnsDefaultShortcutWhenNothingSaved() {
        let suiteName = "ShortcutSettingsStoreTests.\(#function)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let store = ShortcutSettingsStore(defaults: defaults)

        XCTAssertEqual(store.load(), .defaultConfig)
    }

    func testSaveAndLoadRoundTrip() {
        let suiteName = "ShortcutSettingsStoreTests.\(#function)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let store = ShortcutSettingsStore(defaults: defaults)
        let custom = ShortcutConfiguration(
            key: .k,
            command: false,
            option: true,
            control: true,
            shift: false
        )

        store.save(custom)

        XCTAssertEqual(store.load(), custom)
    }

    func testNormalizedFallsBackToCommandModifierWhenAllDisabled() {
        let config = ShortcutConfiguration(
            key: .z,
            command: false,
            option: false,
            control: false,
            shift: false
        )

        XCTAssertEqual(
            config.normalized(),
            ShortcutConfiguration(
                key: .z,
                command: true,
                option: false,
                control: false,
                shift: false
            )
        )
    }

    func testLoadReturnsOCRDebugFrameEnabledByDefault() {
        let suiteName = "ShortcutSettingsStoreTests.\(#function)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let store = ShortcutSettingsStore(defaults: defaults)

        XCTAssertTrue(store.loadOCRDebugFrameEnabled())
    }

    func testSaveAndLoadOCRDebugFrameEnabledRoundTrip() {
        let suiteName = "ShortcutSettingsStoreTests.\(#function)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let store = ShortcutSettingsStore(defaults: defaults)

        store.saveOCRDebugFrameEnabled(false)

        XCTAssertFalse(store.loadOCRDebugFrameEnabled())
    }
}
