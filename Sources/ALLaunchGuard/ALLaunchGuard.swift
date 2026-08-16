import Foundation

/// ALLaunchGuard monitors app launch crashes and activates safe mode
/// when consecutive crash-on-launch events are detected.
///
/// Usage:
/// ```swift
/// // In AppDelegate.application(_:didFinishLaunchingWithOptions:)
/// ALLaunchGuard.shared.start()
/// if ALLaunchGuard.shared.isInSafeMode {
///     // Show safe mode UI
/// }
/// ```
public final class ALLaunchGuard {

    // MARK: - Public

    /// Shared singleton instance.
    public static let shared = ALLaunchGuard()

    /// Returns `true` when the guard has activated safe mode.
    public private(set) var isInSafeMode: Bool = false

    /// Number of consecutive crash-on-launch events before safe mode activates.
    /// Defaults to `3`.
    public var crashThreshold: Int

    /// Delegate to receive safe-mode lifecycle events.
    public weak var delegate: ALLaunchGuardDelegate?

    /// Configuration for the built-in safe-mode UI.
    ///
    /// Assign before calling `start()` when using `autoPresent = true`.
    public var uiConfig: ALLaunchGuardConfig {
        get { _uiConfig }
        set { _uiConfig = newValue }
    }

    // MARK: - Private

    private let storage: ALLaunchGuardStorage
    private var didStart = false
    private var terminationObserver: NSObjectProtocol?
    private var _uiConfig: ALLaunchGuardConfig = .default

    // MARK: - Init

    /// Creates a guard instance backed by the provided storage.
    ///
    /// - Parameters:
    ///   - storage: The persistence back-end. Defaults to `UserDefaults.standard`.
    ///   - crashThreshold: Consecutive crash count required to enter safe mode. Defaults to `3`.
    public init(
        storage: ALLaunchGuardStorage = UserDefaultsLaunchGuardStorage(),
        crashThreshold: Int = 3
    ) {
        self.storage = storage
        self.crashThreshold = crashThreshold
    }

    deinit {
        if let observer = terminationObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // MARK: - Public API

    /// Starts the launch guard.
    ///
    /// Call this as early as possible in `application(_:didFinishLaunchingWithOptions:)`.
    /// After this call, check `isInSafeMode` to decide whether to show a reduced UI.
    public func start() {
        guard !didStart else { return }
        didStart = true

        let count = storage.consecutiveCrashCount + 1
        storage.consecutiveCrashCount = count

        if count >= crashThreshold {
            activateSafeMode()
        }

        terminationObserver = NotificationCenter.default.addObserver(
            forName: UIApplicationWillTerminateNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            // A clean termination (user-initiated quit) should not be treated as
            // a crash, so reset the counter here.
            self?.storage.consecutiveCrashCount = 0
        }
    }

    /// Marks the current launch as successful, resetting the crash counter.
    ///
    /// Call this after your app has fully loaded (e.g. once the home screen is
    /// visible and all critical setup is complete).
    public func markLaunchSuccessful() {
        storage.consecutiveCrashCount = 0
    }

    /// Resets safe mode and clears the crash counter.
    ///
    /// Can be called from a safe-mode UI action (e.g. "Clear app data and restart").
    public func reset() {
        let wasInSafeMode = isInSafeMode
        storage.consecutiveCrashCount = 0
        isInSafeMode = false
        if wasInSafeMode {
            delegate?.launchGuardDidExitSafeMode(self)
        }
    }

    // MARK: - Private helpers

    private func activateSafeMode() {
        isInSafeMode = true
        delegate?.launchGuardDidEnterSafeMode(self)
        #if canImport(UIKit)
        if _uiConfig.autoPresent {
            presentSafeModeUIIfNeeded()
        }
        #endif
    }
}

// MARK: - UIApplication notification name shim

/// Cross-SDK name for `UIApplication.willTerminateNotification`.
private let UIApplicationWillTerminateNotification = Notification.Name("UIApplicationWillTerminateNotification")
