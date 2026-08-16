import XCTest
@testable import ALLaunchGuard

// MARK: - In-memory storage

final class MockStorage: ALLaunchGuardStorage {
    var consecutiveCrashCount: Int = 0
}

// MARK: - Mock delegate

final class MockDelegate: ALLaunchGuardDelegate {
    var enteredSafeMode = false
    var exitedSafeMode = false

    func launchGuardDidEnterSafeMode(_ guard: ALLaunchGuard) {
        enteredSafeMode = true
    }

    func launchGuardDidExitSafeMode(_ guard: ALLaunchGuard) {
        exitedSafeMode = true
    }
}

// MARK: - Tests

final class ALLaunchGuardTests: XCTestCase {

    // MARK: Normal launch flow

    func testFirstLaunchIsNotSafeMode() {
        let storage = MockStorage()
        let guard_ = ALLaunchGuard(storage: storage, crashThreshold: 3)
        guard_.start()
        XCTAssertFalse(guard_.isInSafeMode)
    }

    func testSuccessfulLaunchResetsCrashCounter() {
        let storage = MockStorage()
        storage.consecutiveCrashCount = 2
        let guard_ = ALLaunchGuard(storage: storage, crashThreshold: 3)
        guard_.start()
        guard_.markLaunchSuccessful()
        XCTAssertEqual(storage.consecutiveCrashCount, 0)
        XCTAssertFalse(guard_.isInSafeMode)
    }

    // MARK: Safe mode activation

    func testSafeModeActivatesAtThreshold() {
        let storage = MockStorage()
        storage.consecutiveCrashCount = 2   // will become 3 after start()
        let guard_ = ALLaunchGuard(storage: storage, crashThreshold: 3)
        guard_.start()
        XCTAssertTrue(guard_.isInSafeMode)
    }

    func testSafeModeNotActivatedBelowThreshold() {
        let storage = MockStorage()
        storage.consecutiveCrashCount = 1   // will become 2 after start()
        let guard_ = ALLaunchGuard(storage: storage, crashThreshold: 3)
        guard_.start()
        XCTAssertFalse(guard_.isInSafeMode)
    }

    func testDelegateCalledOnSafeModeEntry() {
        let storage = MockStorage()
        storage.consecutiveCrashCount = 2
        let guard_ = ALLaunchGuard(storage: storage, crashThreshold: 3)
        let delegate = MockDelegate()
        guard_.delegate = delegate
        guard_.start()
        XCTAssertTrue(delegate.enteredSafeMode)
    }

    func testDelegateNotCalledOnResetWhenNotInSafeMode() {
        let storage = MockStorage()
        let guard_ = ALLaunchGuard(storage: storage, crashThreshold: 3)
        let delegate = MockDelegate()
        guard_.delegate = delegate
        guard_.start()   // count=1, not in safe mode
        guard_.reset()
        XCTAssertFalse(delegate.exitedSafeMode)
    }

    // MARK: Reset

    func testResetClearsSafeMode() {
        let storage = MockStorage()
        storage.consecutiveCrashCount = 2
        let guard_ = ALLaunchGuard(storage: storage, crashThreshold: 3)
        guard_.start()
        XCTAssertTrue(guard_.isInSafeMode)
        guard_.reset()
        XCTAssertFalse(guard_.isInSafeMode)
        XCTAssertEqual(storage.consecutiveCrashCount, 0)
    }

    func testDelegateCalledOnReset() {
        let storage = MockStorage()
        storage.consecutiveCrashCount = 2
        let guard_ = ALLaunchGuard(storage: storage, crashThreshold: 3)
        let delegate = MockDelegate()
        guard_.delegate = delegate
        guard_.start()
        guard_.reset()
        XCTAssertTrue(delegate.exitedSafeMode)
    }

    // MARK: start() idempotency

    func testStartIsIdempotent() {
        let storage = MockStorage()
        let guard_ = ALLaunchGuard(storage: storage, crashThreshold: 3)
        guard_.start()
        guard_.start()
        // Counter should only be incremented once
        XCTAssertEqual(storage.consecutiveCrashCount, 1)
    }

    // MARK: Custom threshold

    func testCustomThreshold() {
        let storage = MockStorage()
        let guard_ = ALLaunchGuard(storage: storage, crashThreshold: 1)
        guard_.start()
        XCTAssertTrue(guard_.isInSafeMode)
    }

    // MARK: ALLaunchGuardConfig

    func testConfigDefaultValues() {
        let config = ALLaunchGuardConfig()
        XCTAssertFalse(config.title.isEmpty)
        XCTAssertFalse(config.message.isEmpty)
        XCTAssertFalse(config.fixButtonTitle.isEmpty)
        XCTAssertTrue(config.autoPresent)
    }

    func testConfigCustomValues() {
        let config = ALLaunchGuardConfig(
            title: "My Title",
            message: "My Message",
            fixButtonTitle: "Fix Now",
            autoPresent: false
        )
        XCTAssertEqual(config.title, "My Title")
        XCTAssertEqual(config.message, "My Message")
        XCTAssertEqual(config.fixButtonTitle, "Fix Now")
        XCTAssertFalse(config.autoPresent)
    }

    func testAutoPresentFalseDoesNotChangeGuardBehaviour() {
        // When autoPresent is false the guard still enters safe mode;
        // the UI is just not shown automatically.
        let storage = MockStorage()
        storage.consecutiveCrashCount = 2
        let guard_ = ALLaunchGuard(storage: storage, crashThreshold: 3)
        var config = ALLaunchGuardConfig()
        config.autoPresent = false
        guard_.uiConfig = config
        guard_.start()
        XCTAssertTrue(guard_.isInSafeMode)
    }
}
