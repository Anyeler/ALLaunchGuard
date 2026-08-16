import Foundation

/// Delegate protocol for `ALLaunchGuard` safe-mode lifecycle events.
public protocol ALLaunchGuardDelegate: AnyObject {
    /// Called when the guard activates safe mode.
    func launchGuardDidEnterSafeMode(_ guard: ALLaunchGuard)

    /// Called when safe mode is exited via `reset()`.
    func launchGuardDidExitSafeMode(_ guard: ALLaunchGuard)

    /// Called when a fix action finishes executing
    /// (via `ALLaunchGuard.perform(_:completion:)`).
    ///
    /// `success` 为 true 表示动作成功且安全模式已重置；
    /// false 表示动作失败，安全模式保持激活，用户可重试。
    func launchGuard(
        _ launchGuard: ALLaunchGuard,
        didFinishFixAction action: ALLaunchGuardFixAction,
        success: Bool
    )
}

/// Default empty implementations so conforming types only override what they need.
public extension ALLaunchGuardDelegate {
    func launchGuardDidEnterSafeMode(_ guard: ALLaunchGuard) {}
    func launchGuardDidExitSafeMode(_ guard: ALLaunchGuard) {}
    func launchGuard(
        _ launchGuard: ALLaunchGuard,
        didFinishFixAction action: ALLaunchGuardFixAction,
        success: Bool
    ) {}
}
