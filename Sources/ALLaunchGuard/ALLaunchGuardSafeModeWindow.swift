#if canImport(UIKit)
import UIKit

/// 安全模式窗口协调器：创建并强持有独立 UIWindow，以菜单式安全模式页为
/// rootViewController 接管显示（spec: safe-mode-window）。
///
/// 挂载时序（fix-safe-mode-window-scene-mount，design D2/D3）：
/// 1. install 时两级查找可用 UIWindowScene——优先 foregroundActive，
///    无则接受任意 UIWindowScene（foregroundInactive/unattached，
///    scene 激活后窗口自然可见），找到则以 `UIWindow(windowScene:)`
///    挂载并 makeKeyAndVisible；
/// 2. 无 scene 时按 scene manifest 检测分流（决策纯函数
///    `ALLaunchGuardWindowMountDecision.decide`）：
///    - 未配置 manifest（经典 AppDelegate 生命周期）→ 立即以全屏 frame
///      降级创建窗口（不等超时，消除 5 秒黑屏）；
///    - 配置了 manifest（SceneDelegate 生命周期，scene 尚未连接）→ 暂存
///      root，监听 `UIScene.willConnectNotification`，scene 连接后重找并
///      挂载；超时仍未挂载则全屏 frame 降级兑底。
///
/// 状态机（fix-review-findings + fix-lifecycle-review-findings，
/// spec: safe-mode-window MODIFIED）：
/// install 后窗口存在三种状态——未创建（等待 scene）/ 已挂 scene（正式
/// 挂载）/ 降级 frame（超时兑底，windowScene == nil）。超时创建降级窗口时
/// **保留** willConnect 观察者（仅取消超时任务）；scene 迟到连接时废弃
/// 降级窗口并以 `UIWindow(windowScene:)` 重新挂载（迁移同一
/// rootViewController），保证 scene 宿主中界面最终可见。
///
/// 观察者持续保持（fix-lifecycle-review-findings design D2）：willConnect
/// 观察者自 install 注册后持续保持至协调器 deinit，**不因正式挂载成功而
/// 移除**——官方语义下系统可随时 disconnect 后台/挂起的 scene 并释放其
/// window 层级（旧窗 windowScene 被置空），scene 重连时 willConnect 再次
/// 发出，由分支②以新 scene 重建窗口并迁移安全模式页，界面自愈；健康
/// 状态下的重复连接通知由分支①幂等拦截。超时任务在任何窗口创建路径
/// 完成后取消（防重复创建），观察者唯一清理点是 deinit。对外幂等语义
/// 保持（同一时刻至多一个有效窗口）。
///
/// 窗口生命周期（design D5）：安全模式激活期间不自动关闭——修复成功后进程
/// 仍处于"本次启动跳过了一切"的状态，关窗会黑屏；等待用户手动重启是唯一
/// 正确语义。协调器由 `ALLaunchGuard` 持有单实例（见其声明处取舍说明）。
///
/// 全部使用 iOS 14 安全 API（UIScene.willConnectNotification（iOS 13+）、
/// UIWindowScene 常规 API，spec: iOS 14 兼容）。
///
/// 注：spec/design 原文写作 "UIScene.didConnectNotification"——UIKit 中
/// 不存在该常量（didConnect 系 UIScreen 的通知），scene 连接通知的实际
/// API 为 `UIScene.willConnectNotification`（iOS 13+），语义与 spec 意图
/// 一致，此处按实际 API 实现。
internal final class ALLaunchGuardSafeModeWindowCoordinator {

    /// scene 等待超时时长（秒）：配置了 scene manifest 但 install 后超过
    /// 该时长仍未挂载，则以全屏 frame 降级创建窗口（极端异常兑底：scene
    /// 迟迟未连接）。独立常量，与 survivalTimeout 无语义关联。
    private static let sceneWaitTimeout: TimeInterval = 5

    /// scene manifest 检测（design D3）：默认读宿主 Info.plist 的
    /// UIApplicationSceneManifest 键（配置即 SceneDelegate 生命周期）。
    ///
    /// internal 注入点：检测结果以 Bool 传入决策纯函数（纯函数本身不读
    /// Bundle.main——测试环境 Bundle.main 为 xctest runner，读不到宿主
    /// Info.plist；表驱动测试见 ALLaunchGuardSafeModeWindowMountTests）。
    internal var sceneManifestDetector: () -> Bool = {
        Bundle.main.infoDictionary?["UIApplicationSceneManifest"] != nil
    }

    /// 安全模式窗口（强持有防释放；激活期间不自动关闭，design D5）。
    private var window: UIWindow?

    /// scene 未就绪时暂存的 root view controller（挂载成功后消费清空，
    /// 同时作为"安装已发起"的幂等门控依据）。
    private var pendingRootViewController: UIViewController?

    /// scene 连接观察者（自 install 注册后持续保持至 deinit——覆盖
    /// scene 被系统断连后重连的自愈路径，design D2）。
    private var sceneObserver: NSObjectProtocol?

    /// 超时降级任务（触发或任一窗口创建路径完成后取消清理，防重复创建）。
    private var timeoutWorkItem: DispatchWorkItem?

    // MARK: - Install

    /// 安装安全模式窗口接管（幂等）：已安装（已挂载或已发起等待）直接返回，
    /// 重复调用不创建新窗口——自动分流路径与显式入口共用（tasks 2.2）。
    ///
    /// - Parameter rootViewController: 安全模式页（作为窗口 rootViewController）。
    /// - Precondition: 主线程调用（UIKit 状态访问；公共入口已派发主队列）。
    func install(rootViewController: UIViewController) {
        // 与 start()/reset() 同策略：Debug 断言暴露误用、Release 容忍
        //（防闪退库不在宿主误用时于 Release 崩溃）。公共入口
        // activateSafeModeWindow 已保证主线程派发，此断言防御未来新增调用点。
        assert(Thread.isMainThread, "安全模式窗口安装必须在主线程执行")

        // 幂等门控：窗口已挂载（window != nil），或安装已发起、正等待
        // scene 连接/超时（pendingRootViewController != nil）——均直接返回，
        // 先到的 root 生效，后到的被丢弃。
        if window != nil || pendingRootViewController != nil { return }

        // ── ① 立即尝试：两级 scene 候选查找（design D2）──
        if let scene = Self.bestAvailableWindowScene() {
            mount(rootViewController: rootViewController, in: scene)
            return
        }

        // ── ② 无可用 scene：按 manifest 检测分流（design D3，决策纯函数）──
        // 此处必然无 scene（hasWindowScene 恒 false，attach 分支不可达）；
        // 纯函数完整签名（含 attach）由表驱动测试覆盖。
        if ALLaunchGuardWindowMountDecision.decide(
            hasWindowScene: false,
            sceneManifestConfigured: sceneManifestDetector()
        ) == .immediateFrameFallback {
            // 经典 AppDelegate 生命周期（未配置 scene manifest）：立即以
            // 全屏 frame 降级创建，不等超时（消除 5 秒黑屏）。
            // UIScreen.main 弃用锚定：iOS 26.0 起 SDK 弃用，仅此无 scene
            // 兜底路径使用（该路径必然无 scene，语义仍正确）；正常路径
            // 一律 `UIWindow(windowScene:)` 挂载。
            let window = UIWindow(frame: UIScreen.main.bounds)
            show(window: window, rootViewController: rootViewController)
        } else {
            // SceneDelegate 生命周期（scene 尚未连接）：暂存 root，等待
            // scene 连接通知，并保留超时降级兑底。
            pendingRootViewController = rootViewController
            observeSceneWillConnect()
            scheduleFallbackTimeout()
        }
    }

    deinit {
        // 观察者与超时任务的唯一清理点（design D2：观察者不因正式挂载
        // 成功而移除，持续保持至协调器释放，覆盖 scene 断连重连自愈）。
        cleanupMountWaiters()
    }

    // MARK: - Private（挂载与等待回调）

    /// 以给定 scene 创建窗口并展示（唯一 scene 挂载路径）。
    private func mount(rootViewController: UIViewController, in scene: UIWindowScene) {
        let window = UIWindow(windowScene: scene)
        show(window: window, rootViewController: rootViewController)
    }

    /// 配置并展示窗口（scene 挂载路径与降级路径共用收口：设 root、抬层级、
    /// makeKeyAndVisible），随后取消超时降级任务（防重复创建降级窗口）。
    ///
    /// willConnect 观察者在任何路径下都**保留**（fix-lifecycle-review-
    /// findings design D2）：正式挂载成功后系统仍可能断连 scene（释放
    /// window 层级）并在重连时再次发出 willConnect，观察者持续保持至
    /// deinit 才能覆盖该自愈路径；观察者唯一清理点是 deinit。
    private func show(window: UIWindow, rootViewController: UIViewController) {
        window.rootViewController = rootViewController
        // design D3：高于一切常规窗口（宿主漏分流时覆盖兑底），
        // 不与系统 alert 层冲突（菜单页自身的 UIAlert 仍可正常弹出）。
        window.windowLevel = .normal + 100
        window.makeKeyAndVisible()
        self.window = window
        pendingRootViewController = nil
        // 仅取消超时任务，保留观察者（正式挂载与可恢复降级统一语义）
        cancelFallbackTimeout()
    }

    /// scene 连接回调（主队列）：两分支状态裁决（design D1/D2，
    /// spec: safe-mode-window MODIFIED）。
    private func handleSceneWillConnect(_ notification: Notification) {
        // 分支 ①：当前窗口已挂 scene（正式挂载且健康）→ 幂等返回。
        // **不**清理任何等待资源（fix-lifecycle-review-findings design D2）：
        // willConnect 观察者须持续保持至 deinit——官方语义下系统可随时
        // disconnect 后台/挂起的 scene 并释放其 window 层级，重连时
        // willConnect 再次发出；若此处移除观察者，断连后修复页将永久
        // 丢失（宿主已跳过 UI 构建 → 黑屏）。此分支仅拦截健康状态下的
        // 重复连接通知（超时任务已在挂载时取消，无泄漏）。
        if let current = window, current.windowScene != nil {
            return
        }

        // root 来源（分支 ②前置）：未挂载（window == nil）取暂存 root；
        // 已存在窗口但未挂 scene（windowScene == nil）复用其
        // rootViewController——同一 root 转移至新窗口，不重建页面。
        // windowScene == nil 覆盖两种来源：超时降级的 frame 窗口，以及
        // scene 被系统断连后 window 层级被释放的旧窗（重连自愈路径，
        // design D3：不监听 didDisconnect，断连即置空，重连走本分支）。
        let root = window?.rootViewController ?? pendingRootViewController
        guard let root = root else { return }

        // 候选 1：两级全局重找（foregroundActive 优先 → 任意 UIWindowScene，
        // 覆盖 install 后才连接/激活的时序）；
        // 候选 2：本次刚连接的 scene（通知 object）——willConnect 时
        // activationState 尚未变为 foregroundActive，直接以连接事件为准挂载，
        // 满足 spec "scene 连接后自动挂载并可见"的场景语义。
        // 均不可用则保留观察者，等待下一次连接（降级/断连旧窗保持现状）。
        let scene = Self.bestAvailableWindowScene()
            ?? (notification.object as? UIWindowScene)
        guard let scene = scene else { return }

        // 分支 ②：未挂载（nil）、降级 frame 窗口或断连旧窗 → 以新 scene
        // 正式挂载重建。先保存旧窗口引用（show 会覆盖 self.window），新窗口
        // makeKeyAndVisible 后废弃旧窗口（isHidden 后释放，root 已迁移）。
        let legacyWindow = window
        mount(rootViewController: root, in: scene)
        legacyWindow?.isHidden = true
    }

    /// 超时降级回调（主队列）：仍未挂载则以全屏 frame 创建**可恢复**降级窗口。
    ///
    /// 可恢复语义（design D1 / spec: safe-mode-window MODIFIED）：创建降级
    /// 窗口时仅取消超时任务，保留 willConnect 观察者——scene 宿主中无 scene
    /// 的 frame 窗口不可见，scene 迟到连接时由 `handleSceneWillConnect`
    /// 废弃降级窗口并以 `UIWindow(windowScene:)` 重新挂载，界面最终可见。
    ///（经典 AppDelegate 生命周期走 install 的立即降级路径，不经此回调。）
    private func handleFallbackTimeout() {
        timeoutWorkItem = nil
        // 状态门控：已挂载（scene 路径先行完成）则不创建
        guard window == nil, let root = pendingRootViewController else { return }
        // UIScreen.main 弃用锚定：iOS 26.0 起 SDK 弃用，仅此无 scene 兜底
        // 路径使用（该路径必然无 scene，语义仍正确）；正常路径一律
        // `UIWindow(windowScene:)` 挂载。
        let window = UIWindow(frame: UIScreen.main.bounds)
        show(window: window, rootViewController: root)
    }

    // MARK: - Private（等待资源管理）

    /// 监听 scene 连接通知（回调收口主队列；仅注册一次）。
    private func observeSceneWillConnect() {
        guard sceneObserver == nil else { return }
        sceneObserver = NotificationCenter.default.addObserver(
            forName: UIScene.willConnectNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.handleSceneWillConnect(notification)
        }
    }

    /// 排定超时降级检查（仅排定一次；任一窗口创建路径完成后取消）。
    private func scheduleFallbackTimeout() {
        guard timeoutWorkItem == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            self?.handleFallbackTimeout()
        }
        timeoutWorkItem = work
        DispatchQueue.main.asyncAfter(
            deadline: .now() + Self.sceneWaitTimeout,
            execute: work
        )
    }

    /// 取消超时降级任务（任何窗口创建路径完成后调用，防重复创建降级窗口）。
    ///
    /// 职责拆分说明（fix-lifecycle-review-findings design D2）：本函数
    /// **不**触碰 willConnect 观察者——观察者不因挂载成功而移除。
    private func cancelFallbackTimeout() {
        timeoutWorkItem?.cancel()
        timeoutWorkItem = nil
    }

    /// 清理全部挂载等待资源（观察者 + 超时任务），仅协调器 deinit 时调用
    ///（观察者唯一清理点，design D2）。
    private func cleanupMountWaiters() {
        if let observer = sceneObserver {
            NotificationCenter.default.removeObserver(observer)
            sceneObserver = nil
        }
        cancelFallbackTimeout()
    }

    // MARK: - Private（scene 查找）

    /// 两级 scene 候选查找（design D2）：优先 foregroundActive；无则接受
    /// 任意 UIWindowScene（foregroundInactive/unattached——scene 激活后
    /// 绑定的窗口自然可见，系统行为）。
    /// design（Non-Goals）：多 scene 并发（iPad 分屏）下不做精细策略，
    /// 单窗口语义；完全无 scene 时由调用方的分流链路兑底。
    private static func bestAvailableWindowScene() -> UIWindowScene? {
        let windowScenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
        return windowScenes.first { $0.activationState == .foregroundActive }
            ?? windowScenes.first
    }
}
#endif

// MARK: - 挂载决策（跨平台纯函数，macOS/Linux 可单测）

/// install 挂载策略决策结果（design D3/D4）。
internal enum ALLaunchGuardWindowMountDecision: Equatable {
    /// 有可用 UIWindowScene：立即以 `UIWindow(windowScene:)` 挂载
    case attach
    /// 无 scene 且未配置 scene manifest（经典 AppDelegate 生命周期）：
    /// 立即以全屏 frame 降级创建窗口，不等超时
    case immediateFrameFallback
    /// 无 scene 但配置了 scene manifest（scene 尚未连接）：注册
    /// willConnect 观察 + 超时降级兑底
    case waitSceneWithTimeout

    /// 决策纯函数（无 UIKit 依赖，macOS/Linux 可直接单测）：
    /// - 有可用 scene → `.attach`（与 manifest 配置无关）；
    /// - 无 scene + 无 manifest → `.immediateFrameFallback`（不等超时）；
    /// - 无 scene + 有 manifest → `.waitSceneWithTimeout`。
    ///
    /// 注：`Bundle.main` 读取仅存在于协调器的 `sceneManifestDetector`
    /// 默认闭包——检测结果以 Bool 参数注入本函数，测试环境（xctest
    /// runner 的 Bundle.main）不进入纯函数（design D3 风险处置）。
    static func decide(
        hasWindowScene: Bool,
        sceneManifestConfigured: Bool
    ) -> ALLaunchGuardWindowMountDecision {
        if hasWindowScene { return .attach }
        return sceneManifestConfigured
            ? .waitSceneWithTimeout
            : .immediateFrameFallback
    }
}
