import Foundation

/// 安全模式界面的展示样式（spec: safe-mode-window）。
/// String raw 值便于调试与日志埋点（design D4）。
/// `Sendable`（upgrade-swift-6-beta）：v6 语言模式下公共枚举不再隐式
/// 合成 Sendable，显式标注（String 枚举平凡 Sendable，零语义变化）。
public enum ALLaunchGuardPresentationStyle: String, Sendable {
    /// 独立 UIWindow 接管显示（默认）：不依赖宿主是否构建了 window/root VC——
    /// 宿主跳过启动流程时此窗为唯一界面；宿主漏分流时因更高 windowLevel
    /// 形成覆盖兜底（双保险）。
    case dedicatedWindow
    /// 在宿主 key window rootVC 上 present（旧行为兼容路径）：宿主必须已构建
    /// 自身界面，否则无处可挂。
    case presentOnRoot
}

/// Configuration for the built-in safe-mode UI page.
///
/// `Sendable`（upgrade-swift-6-beta）：成员全部为值类型 / Sendable，
/// 编译器可核验；消除 `static let default` 的并发安全诊断。
public struct ALLaunchGuardConfig: Sendable {

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

    /// 安全模式激活后自动展示界面采用的样式（仅 `autoPresent == true` 生效）。
    ///
    /// BREAKING (2.0.0): 默认 `.dedicatedWindow`（独立窗口接管），取代旧的
    /// present-on-root 默认行为；需要旧行为的宿主显式配置 `.presentOnRoot`。
    public var presentationStyle: ALLaunchGuardPresentationStyle

    // MARK: - Init

    public init(
        title: String = "应用启动异常",
        message: String = "检测到应用连续启动异常，已进入安全模式。\n请在下方选择修复项进行修复，完成后重启应用。",
        restartHint: String = "修复完成后，请退出应用重新打开",
        restartButtonTitle: String = "重启应用",
        allowRestartExit: Bool = true,
        tintColor: ALColor = .systemOrange,
        autoPresent: Bool = true,
        presentationStyle: ALLaunchGuardPresentationStyle = .dedicatedWindow
    ) {
        self.title = title
        self.message = message
        self.restartHint = restartHint
        self.restartButtonTitle = restartButtonTitle
        self.allowRestartExit = allowRestartExit
        self.tintColor = tintColor
        self.autoPresent = autoPresent
        self.presentationStyle = presentationStyle
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

/// 无状态类，`Sendable`（upgrade-swift-6-beta）：消除非 UIKit 平台
///（macOS 测试专属）`static let systemOrange` 的并发安全诊断。
public final class ALPlaceholderColor: Sendable {
    public static let systemOrange = ALPlaceholderColor()
    public init() {}
}
#endif
