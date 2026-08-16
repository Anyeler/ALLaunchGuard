import Foundation

// MARK: - 修复动作协议

/// 安全模式下的修复动作协议（菜单项契约）。
///
/// 动作以协议化菜单项形式由宿主或库注册（`ALLaunchGuard.fixActions`），
/// 仅在用户显式触发时执行；实现方 MUST 保证 `perform(completion:)`
/// 恰好回调一次 completion（`true` 成功 / `false` 失败）。
///
/// 动作为 class 协议（AnyObject）：生命周期与 guard 单例同长，
/// 实现方应轻持有依赖，避免延长宿主对象图。
public protocol ALLaunchGuardFixAction: AnyObject {
    /// 菜单标题
    var title: String { get }

    /// SF Symbol 图标名；nil 时 UI 侧使用默认图标
    var iconSystemName: String? { get }

    /// 破坏性样式标记：true 时 UI 呈现警示样式。默认 false（见协议扩展）。
    var isDestructive: Bool { get }

    /// 执行修复动作（用户点击菜单项后调用）。
    ///
    /// 实现方可自由选择执行线程（耗时 IO 建议后台队列），
    /// completion 可在任意线程回调，编排层会统一派发到主队列：
    /// - `true`：修复成功，编排层将触发一次安全模式重置；
    /// - `false`：修复失败，安全模式保持激活，允许用户重试。
    func perform(completion: @escaping (Bool) -> Void)
}

/// 协议默认实现：非破坏性动作。
public extension ALLaunchGuardFixAction {
    var isDestructive: Bool { false }
}

// MARK: - 闭包包装动作

/// 便捷闭包包装动作：一行注册轻量修复逻辑，便于宿主快速接入。
///
/// ```swift
/// ALLaunchGuard.shared.fixActions = [
///     ALLaunchGuardClearCacheAction(),
///     ALLaunchGuardClosureAction(title: "重置账号") { completion in
///         MyAccountCenter.reset { completion(true) }
///     }
/// ]
/// ```
public final class ALLaunchGuardClosureAction: ALLaunchGuardFixAction {

    /// 菜单标题
    public let title: String

    /// SF Symbol 图标名；nil 时 UI 侧使用默认图标
    public let iconSystemName: String?

    /// 破坏性样式标记
    public let isDestructive: Bool

    private let handler: (@escaping (Bool) -> Void) -> Void

    /// - Parameters:
    ///   - title: 菜单标题
    ///   - iconSystemName: SF Symbol 图标名（默认 nil，UI 侧使用默认图标）
    ///   - isDestructive: 破坏性样式标记（默认 false）
    ///   - handler: 执行闭包，接收编排层传入的 completion；
    ///     须恰好回调一次（`true` 成功 / `false` 失败）
    public init(
        title: String,
        iconSystemName: String? = nil,
        isDestructive: Bool = false,
        handler: @escaping (@escaping (Bool) -> Void) -> Void
    ) {
        self.title = title
        self.iconSystemName = iconSystemName
        self.isDestructive = isDestructive
        self.handler = handler
    }

    public func perform(completion: @escaping (Bool) -> Void) {
        handler(completion)
    }
}

// MARK: - 内置重置安全模式动作

/// 内置重置安全模式动作：`fixActions` 为空时由菜单页自动注入的兑底出口
///（spec: safe-mode-ui MODIFIED——安全模式始终存在用户退出路径，
/// 覆盖宿主忘记注册动作与 1.x 升级残留计数首启触发场景）。
///
/// `perform` 恒定成功（`completion(true)`）：成功后经编排层
/// `ALLaunchGuard.perform(_:completion:)` 统一触发一次 `reset()`
///（清零计数、清除粘滞标记、退出回调），用户重启应用即恢复正常。
/// 也可由宿主显式注册到 `fixActions` 中作为“最后一项”退出出口；
/// 注意推荐优先注册业务修复动作（清缓存等），本动作仅为兑底。
public final class ALLaunchGuardResetSafeModeAction: ALLaunchGuardFixAction {

    /// 默认中文标题
    public let title: String

    /// 默认 SF Symbol 图标名
    public let iconSystemName: String?

    /// 破坏性样式标记：重置安全模式属破坏性退出出口，恒定 true
    public let isDestructive: Bool

    /// - Parameters:
    ///   - title: 菜单标题（默认“重置安全模式”）
    ///   - iconSystemName: SF Symbol 图标名（默认 arrow.counterclockwise）
    public init(
        title: String = "重置安全模式",
        iconSystemName: String? = "arrow.counterclockwise"
    ) {
        self.title = title
        self.iconSystemName = iconSystemName
        self.isDestructive = true
    }

    public func perform(completion: @escaping (Bool) -> Void) {
        // 重置本身无实际清理工作，恒定成功：
        // 成功后由编排层统一触发 reset（与“首个成功动作触发 reset”编排天然一致）
        completion(true)
    }
}

// MARK: - 内置清缓存动作

/// 内置清缓存动作：清理应用沙盒 Caches 目录内容（含子目录）。
///
/// - 目录不存在或为空 → 视为成功（completion(true)）；
/// - 任一项删除失败（抛出错误）→ 整体失败（completion(false)）；
/// - 仅清 Caches（系统本可随时回收的目录），不触碰 Documents/Library 其他目录。
public final class ALLaunchGuardClearCacheAction: ALLaunchGuardFixAction {

    /// 默认中文标题
    public let title: String

    /// 默认 SF Symbol 图标名
    public let iconSystemName: String?

    /// 待清理目录（默认应用沙盒 Caches；测试可注入任意目录模拟）
    private let cachesDirectory: URL

    /// 默认构造：清理应用沙盒 Caches 目录。
    public init(
        title: String = "清理缓存",
        iconSystemName: String? = "trash"
    ) {
        self.title = title
        self.iconSystemName = iconSystemName
        self.cachesDirectory = FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask)
            .first
            ?? FileManager.default.temporaryDirectory
    }

    /// 测试注入构造：以指定目录模拟 Caches（非公共 API，`@testable` 可见）。
    init(
        cachesDirectory: URL,
        title: String = "清理缓存",
        iconSystemName: String? = "trash"
    ) {
        self.title = title
        self.iconSystemName = iconSystemName
        self.cachesDirectory = cachesDirectory
    }

    public func perform(completion: @escaping (Bool) -> Void) {
        // 清缓存为耗时 IO：在后台队列执行（动作自行决定执行线程，编排层只收口结果）
        DispatchQueue.global(qos: .userInitiated).async { [cachesDirectory] in
            let fileManager = FileManager.default
            // 目录不存在视为成功（空目录 contentsOfDirectory 返回空数组，同样成功）
            guard fileManager.fileExists(atPath: cachesDirectory.path) else {
                completion(true)
                return
            }
            do {
                let entries = try fileManager.contentsOfDirectory(atPath: cachesDirectory.path)
                for entry in entries {
                    // removeItem 同时适用于文件与子目录（递归删除）
                    try fileManager.removeItem(at: cachesDirectory.appendingPathComponent(entry))
                }
                completion(true)
            } catch {
                // 任一项删除失败或列举失败：整体失败
                completion(false)
            }
        }
    }
}
