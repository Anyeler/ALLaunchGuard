import Foundation

/// Configuration for the built-in safe-mode UI page.
public struct ALLaunchGuardConfig {

    // MARK: - Properties

    /// Large title shown at the top of the safe-mode page.
    /// Defaults to "应用启动异常" (App Launch Error).
    public var title: String

    /// Body message shown below the title.
    /// Defaults to a Chinese explanation guiding the user to pick a fix item
    /// from the menu list below (2.0 menu-style safe-mode page wording).
    public var message: String

    /// 底部常驻展示的重启提示文案；任一修复动作成功后强调展示（tintColor + 加粗）。
    /// Defaults to "修复完成后，请退出应用重新打开".
    ///
    /// BREAKING (2.0.0): 取代已移除的 `fixButtonTitle` 字段。
    public var restartHint: String

    /// 修复成功后展示的“重启应用”按钮文案（spec: safe-mode-ui MODIFIED）。
    /// Defaults to "重启应用".
    public var restartButtonTitle: String

    /// 是否允许修复成功后展示“重启应用”按钮（spec: safe-mode-ui MODIFIED）：
    /// `true`（默认）时任一动作修复成功后展示按钮，用户点击并经二次确认后
    /// 终止进程（exit(0)）——下次冷启动恢复正常流程；
    /// `false` 时按钮恒不展示，保留纯文字提示旧行为（供审核敏感宿主选择）。
    /// Defaults to `true`.
    public var allowRestartExit: Bool

    /// Accent colour applied to the fix button and icon.
    /// Defaults to the system orange colour.
    public var tintColor: ALColor

    /// When `true`, `ALLaunchGuard.start()` automatically presents the safe-mode
    /// page as soon as safe mode is activated, without any additional caller code.
    /// Defaults to `true`.
    public var autoPresent: Bool

    // MARK: - Init

    public init(
        title: String = "应用启动异常",
        message: String = "检测到应用连续启动异常，已进入安全模式。\n请在下方选择修复项进行修复，完成后重启应用。",
        restartHint: String = "修复完成后，请退出应用重新打开",
        restartButtonTitle: String = "重启应用",
        allowRestartExit: Bool = true,
        tintColor: ALColor = .systemOrange,
        autoPresent: Bool = true
    ) {
        self.title = title
        self.message = message
        self.restartHint = restartHint
        self.restartButtonTitle = restartButtonTitle
        self.allowRestartExit = allowRestartExit
        self.tintColor = tintColor
        self.autoPresent = autoPresent
    }

    /// Default configuration.
    public static let `default` = ALLaunchGuardConfig()
}

// MARK: - Platform colour alias

#if canImport(UIKit)
import UIKit
public typealias ALColor = UIColor
#else
import Foundation
/// Fallback colour type when UIKit is not available (e.g. unit-test targets on Linux).
public typealias ALColor = ALPlaceholderColor

public final class ALPlaceholderColor {
    public static let systemOrange = ALPlaceholderColor()
    public init() {}
}
#endif
