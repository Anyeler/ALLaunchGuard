import Foundation

/// Protocol for persisting the consecutive-crash counter.
public protocol ALLaunchGuardStorage: AnyObject {
    /// The number of consecutive launches that ended in a crash.
    var consecutiveCrashCount: Int { get set }
}

/// Default `UserDefaults`-backed implementation of `ALLaunchGuardStorage`.
public final class UserDefaultsLaunchGuardStorage: ALLaunchGuardStorage {

    private let key = "ALLaunchGuard.consecutiveCrashCount"
    private let defaults: UserDefaults

    /// Creates a storage instance.
    /// - Parameter defaults: The `UserDefaults` suite to use. Defaults to `.standard`.
    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var consecutiveCrashCount: Int {
        get { defaults.integer(forKey: key) }
        set { defaults.set(newValue, forKey: key) }
    }
}
