import Foundation

/// Configuration for the built-in safe-mode UI page.
public struct ALLaunchGuardConfig {

    // MARK: - Properties

    /// Large title shown at the top of the safe-mode page.
    /// Defaults to "应用启动异常" (App Launch Error).
    public var title: String

    /// Body message shown below the title.
    /// Defaults to a Chinese explanation asking the user to tap Fix.
    public var message: String

    /// Label of the primary action button.
    /// Defaults to "修复" (Fix).
    public var fixButtonTitle: String

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
        message: String = "检测到应用连续启动崩溃，已进入安全模式。\n请点击下方\u{201C}修复\u{201D}按钮清除异常状态后重新启动。",
        fixButtonTitle: String = "修复",
        tintColor: ALColor = .systemOrange,
        autoPresent: Bool = true
    ) {
        self.title = title
        self.message = message
        self.fixButtonTitle = fixButtonTitle
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
    public static let label       = ALPlaceholderColor()
    public static let secondaryLabel = ALPlaceholderColor()
    public static let systemBackground = ALPlaceholderColor()
    public init() {}
}
#endif
