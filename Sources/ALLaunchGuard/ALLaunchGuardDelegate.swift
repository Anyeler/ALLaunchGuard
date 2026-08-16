import Foundation

/// Delegate protocol for `ALLaunchGuard` safe-mode lifecycle events.
public protocol ALLaunchGuardDelegate: AnyObject {
    /// Called when the guard activates safe mode.
    func launchGuardDidEnterSafeMode(_ guard: ALLaunchGuard)

    /// Called when safe mode is exited via `reset()`.
    func launchGuardDidExitSafeMode(_ guard: ALLaunchGuard)
}

/// Default empty implementations so conforming types only override what they need.
public extension ALLaunchGuardDelegate {
    func launchGuardDidEnterSafeMode(_ guard: ALLaunchGuard) {}
    func launchGuardDidExitSafeMode(_ guard: ALLaunchGuard) {}
}
