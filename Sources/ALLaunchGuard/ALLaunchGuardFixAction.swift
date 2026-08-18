import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

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

/// 内置重置安全模式动作：`fixActions` 为空时由菜单页自动注入的兜底出口
///（spec: safe-mode-ui MODIFIED——安全模式始终存在用户退出路径，
/// 覆盖宿主忘记注册动作与 1.x 升级残留计数首启触发场景）。
///
/// `perform` 恒定成功（`completion(true)`）：成功后经编排层
/// `ALLaunchGuard.perform(_:completion:)` 统一触发一次 `reset()`
///（清零计数、清除粘滞标记、退出回调），用户重启应用即恢复正常。
/// 也可由宿主显式注册到 `fixActions` 中作为“最后一项”退出出口；
/// 注意推荐优先注册业务修复动作（清缓存等），本动作仅为兜底。
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

// MARK: - 内置重启动作

/// 内置重启动作：一键终止进程交由用户下次冷启动恢复（破坏性样式）。
///
/// 时序设计（design D1，load-bearing）：`perform` 先同步回调
/// `completion(true)`——编排层收到成功后将 `reset()`（清零计数、
/// 清除粘滞标记）派发主队列；随后本动作才把 `exitHandler`（默认
/// `exit(0)`）派发主队列晚一拍执行。依赖主队列 FIFO 保证粘滞标记
/// 清除先于进程终止，避免重启后再次进入安全模式。
///
/// 菜单位置由宿主注册顺序决定（约定置于末位），库不自动排序或注入；
/// 与菜单页既有重启按钮（成功后呈现、Alert 二次确认）可并存，
/// 宿主二选一或同用均可。
public final class ALLaunchGuardRestartAction: ALLaunchGuardFixAction {

    /// 默认中文标题
    public let title: String

    /// 默认 SF Symbol 图标名
    public let iconSystemName: String?

    /// 破坏性样式标记：重启属破坏性退出路径，恒定 true
    public let isDestructive: Bool

    /// 进程终止行为（默认 `exit(0)`）：测试可注入替换（非公共 API，
    /// `@testable` 可见），生产语义不可经公共 API 更改。
    /// `@Sendable`（upgrade-swift-6-beta）：消除下方主队列派发捕获
    /// self 的 sending 诊断；测试注入侧同样须提供 @Sendable 闭包。
    internal var exitHandler: @Sendable () -> Void = { exit(0) }

    /// - Parameters:
    ///   - title: 菜单标题（默认“重启应用”）
    ///   - iconSystemName: SF Symbol 图标名（默认 arrow.clockwise）
    public init(
        title: String = "重启应用",
        iconSystemName: String? = "arrow.clockwise"
    ) {
        self.title = title
        self.iconSystemName = iconSystemName
        self.isDestructive = true
    }

    public func perform(completion: @escaping (Bool) -> Void) {
        // 第一步：先回调成功，编排层的 reset 由此先入主队列。
        completion(true)
        // 第二步：主队列晚一拍终止进程。load-bearing——与上一行的
        // 先后顺序不得调换：依赖主队列 FIFO 保证编排层的
        // DispatchQueue.main.async { reset() … } 先执行（粘滞标记
        // 清除先于进程终止），否则重启后仍会因粘滞标记再进安全模式。
        // 快照捕获 exitHandler（upgrade-swift-6-beta）：避免闭包捕获 self；
        // 禁止把此处 Task 化——Task 调度不保证与主队列 FIFO 的相对先后，
        // 会破坏上述 load-bearing 时序。
        DispatchQueue.main.async { [exitHandler] in exitHandler() }
    }
}

// MARK: - 内置白名单缓存全清动作

/// 内置白名单缓存全清动作：深档位清理（design D2），与
/// `ALLaunchGuardClearCacheAction`（仅 Caches 的轻档位）共存，
/// 宿主按需注册其一或同用。
///
/// 清理模型（枚举沙盒根顶层目录，默认 `NSHomeDirectory()`）：
/// - 保护名单内（默认 Documents/Library/SystemData，可扩展）：不删
///   目录本身；Library 特判——进入清理其 Caches 子目录内容；
/// - tmp / .Trash：清空内容（目录本身保留）；
/// - 其余游离顶层项：整个删除。
///
/// 幂等与失败聚合：条目已消失按成功处理；单项删除失败继续清理其余
/// 项，最终聚合 `completion(false)`（安全模式保持激活，用户可重试）。
/// 在后台低优先级队列（`qos: .utility`）执行，逐项 autoreleasepool。
public final class ALLaunchGuardClearAllCacheAction: ALLaunchGuardFixAction {

    /// 默认保护顶层目录名单（保守：用户数据、系统数据与 Library
    /// 非缓存部分），宿主可经构造参数扩展或调整。
    public static let defaultProtectedTopLevelItems = ["Documents", "Library", "SystemData"]

    /// 默认中文标题（与 ClearCacheAction 的“清理缓存”区分档位）
    public let title: String

    /// 默认 SF Symbol 图标名
    public let iconSystemName: String?

    /// 破坏性样式标记：全清属高风险操作，恒定 true
    public let isDestructive: Bool

    /// 沙盒根目录（默认应用沙盒；测试可注入任意目录模拟）
    private let sandboxRoot: URL

    /// 保护顶层目录名单
    private let protectedTopLevelItems: [String]

    /// 默认构造：清理应用沙盒。
    ///
    /// - Parameters:
    ///   - title: 菜单标题（默认“深度清理缓存”）
    ///   - iconSystemName: SF Symbol 图标名（默认 trash.slash）
    ///   - protectedTopLevelItems: 保护顶层目录名单（默认
    ///     Documents/Library/SystemData），可追加宿主自建目录
    public init(
        title: String = "深度清理缓存",
        iconSystemName: String? = "trash.slash",
        protectedTopLevelItems: [String] = ALLaunchGuardClearAllCacheAction.defaultProtectedTopLevelItems
    ) {
        self.title = title
        self.iconSystemName = iconSystemName
        self.isDestructive = true
        self.sandboxRoot = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        self.protectedTopLevelItems = protectedTopLevelItems
    }

    /// 测试注入构造：以指定目录模拟沙盒根（非公共 API，`@testable` 可见）。
    init(
        sandboxRoot: URL,
        title: String = "深度清理缓存",
        iconSystemName: String? = "trash.slash",
        protectedTopLevelItems: [String] = ALLaunchGuardClearAllCacheAction.defaultProtectedTopLevelItems
    ) {
        self.title = title
        self.iconSystemName = iconSystemName
        self.isDestructive = true
        self.sandboxRoot = sandboxRoot
        self.protectedTopLevelItems = protectedTopLevelItems
    }

    public func perform(completion: @escaping (Bool) -> Void) {
        // 全清为耗时 IO：后台低优先级队列执行，逐项 autoreleasepool
        DispatchQueue.global(qos: .utility).async { [sandboxRoot, protectedTopLevelItems] in
            let fileManager = FileManager.default
            // 沙盒根不存在：幂等成功（与 ClearCacheAction 语义一致）
            guard fileManager.fileExists(atPath: sandboxRoot.path) else {
                completion(true)
                return
            }
            guard let entries = try? fileManager.contentsOfDirectory(atPath: sandboxRoot.path) else {
                // 列举失败（非常罕见，如权限异常）：如实报失败供重试
                completion(false)
                return
            }

            var failed = false
            for entry in entries {
                autoreleasepool {
                    // 白名单在删除循环内逐条评估（不预过滤快照）：
                    // 判定以删除时刻为准，TOCTOU 安全（design D2）。
                    if protectedTopLevelItems.contains(entry) {
                        if entry == "Library" {
                            // Library 特判：保留目录本身，仅清理 Caches 子目录内容
                            let caches = sandboxRoot.appendingPathComponent("Library/Caches", isDirectory: true)
                            if !Self.clearContents(of: caches, fileManager: fileManager) {
                                failed = true
                            }
                        }
                        // 保护名单内其余目录：整体保留
                        return
                    }

                    let url = sandboxRoot.appendingPathComponent(entry)
                    if entry == "tmp" || entry == ".Trash" {
                        // 临时/回收站目录：清空内容，目录本身保留
                        if !Self.clearContents(of: url, fileManager: fileManager) {
                            failed = true
                        }
                        return
                    }

                    // 其余游离顶层项：整个删除；条目已消失按成功（幂等）
                    guard fileManager.fileExists(atPath: url.path) else { return }
                    do {
                        try fileManager.removeItem(at: url)
                    } catch {
                        // 单项失败记录后继续清理其余项，最终聚合失败
                        failed = true
                    }
                }
            }
            completion(!failed)
        }
    }

    /// 清空目录内容（目录本身保留）；目录不存在按成功。返回是否全部成功。
    private static func clearContents(of directory: URL, fileManager: FileManager) -> Bool {
        guard fileManager.fileExists(atPath: directory.path) else { return true }
        guard let children = try? fileManager.contentsOfDirectory(atPath: directory.path) else {
            return false
        }
        var allSucceeded = true
        for child in children {
            let childURL = directory.appendingPathComponent(child)
            // 条目已消失按成功（幂等）
            guard fileManager.fileExists(atPath: childURL.path) else { continue }
            do {
                try fileManager.removeItem(at: childURL)
            } catch {
                // 单项失败记录后继续清理其余项
                allSucceeded = false
            }
        }
        return allSucceeded
    }
}
