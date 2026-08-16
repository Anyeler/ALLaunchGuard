import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// ALLaunchGuard monitors app launch crashes and activates safe mode
/// when consecutive crash-on-launch events are detected.
///
/// Usage:
/// ```swift
/// // In AppDelegate.application(_:didFinishLaunchingWithOptions:)
/// if ALLaunchGuard.shared.shouldEnterSafeMode {
///     // 极早期无副作用查询：可在 start() 之前分流启动路径
/// }
/// if ALLaunchGuard.shared.start() {
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

    /// 存活确认时长（秒）：启动后进程存活满该时长即视为一次正常启动，
    /// 计数自动清零，不再依赖宿主手动调用 `markLaunchSuccessful()`。
    /// Defaults to `5`.
    public var survivalTimeout: TimeInterval = 5

    /// 极早期无副作用查询：读取粘滞安全模式标记或计数与阈值的关系。
    ///
    /// 可在 `start()` 之前（宿主启动最早期）调用，不改变任何存储状态。
    public var shouldEnterSafeMode: Bool {
        storage.safeModeActive || storage.consecutiveCrashCount >= crashThreshold
    }

    /// Delegate to receive safe-mode lifecycle events.
    public weak var delegate: ALLaunchGuardDelegate?

    /// Configuration for the built-in safe-mode UI.
    ///
    /// Assign before calling `start()` when using `autoPresent = true`.
    public var uiConfig: ALLaunchGuardConfig {
        get { _uiConfig }
        set { _uiConfig = newValue }
    }

    /// 已注册的修复动作（安全模式菜单项数据源）。
    ///
    /// 宿主可在启动早期（如 `didFinishLaunching` 首行）直接赋值，
    /// 内置动作与自定义动作可混排，注册顺序即菜单展示顺序；默认为空数组。
    /// 库 MUST NOT 在进入安全模式时自动执行任何动作——仅用户显式触发
    ///（通过 `perform(_:completion:)`）。
    ///
    /// 动作会被强持有（生命周期与本单例同长），实现方应轻持有依赖。
    public var fixActions: [ALLaunchGuardFixAction] = []

    // MARK: - Internal（测试注入）

    /// 存活计时调度器：接收存活确认闭包，并在 `survivalTimeout` 到期后执行。
    ///
    /// 非公共 API：单元测试通过 `@testable` 注入立即执行 / no-op 实现。
    /// 声明处给 no-op 默认值以保证 init 内可安全重建（见 init 说明）。
    internal var survivalScheduler: (@escaping () -> Void) -> Void = { _ in }

    // MARK: - Private

    private let storage: ALLaunchGuardStorage
    private var didStart = false

    /// 会话代际标记：每次启动存活计时时自增。
    /// 计时闭包捕获启动时的代际值，触发时仅当代际仍匹配才执行确认，
    /// 防止旧会话的挂起计时闭包在跨会话竞态中误清新会话计数。
    private var launchGeneration = 0

    /// 本会话 start() 写入的 uptime 打点（供 markLaunchSuccessful 复用校验）。
    private var currentSessionMarkUptime: TimeInterval?

    private var backgroundObserver: NSObjectProtocol?
    private var terminationObserver: NSObjectProtocol?
    private var _uiConfig: ALLaunchGuardConfig = .default

    #if canImport(UIKit)
    /// 安全模式窗口协调器（单实例，tasks 2.1/2.2）。
    ///
    /// 持有方式取舍：由 ALLaunchGuard 持有单实例而非协调器自带 `static shared`——
    /// 窗口语义与 guard 单例生命周期天然一一对应（进程内至多一个安全模式窗口）；
    /// 同时测试注入的独立 guard 实例各自持有协调器，互不共享 UIKit 全局状态，
    /// 避免跨用例残留（install 本身也幂等，双层保险）。
    private let safeModeWindowCoordinator = ALLaunchGuardSafeModeWindowCoordinator()
    #endif

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
        // 默认调度：主队列延迟 survivalTimeout 秒执行。
        // 主线程 hang ⇒ 确认永不发生 ⇒ 看门狗语义正确。
        // [weak self] 避免实例与闭包循环引用，且保证每次读取最新的 timeout 值。
        // （此赋值须在全部存储属性初始化完成后进行，闭包才能安全捕获 self。）
        self.survivalScheduler = { [weak self] work in
            guard let self = self else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + self.survivalTimeout, execute: work)
        }
    }

    deinit {
        if let observer = backgroundObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = terminationObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // MARK: - Public API

    /// Starts the launch guard.
    ///
    /// 判定状态机（预支计数 + 存活确认 + 双重误判防护）：
    /// 1. 裁决上一会话残留状态：
    ///    - 粘滞安全模式标记 → 直接激活安全模式，不递增计数、不启动存活计时（防绕过）；
    ///    - 上次已进入后台（系统回收 / 上滑强杀后台 / 后台 OOM）→ 清零计数；
    ///    - 上次打点 uptime 大于本次 systemUptime（设备重启）→ 清零计数；
    /// 2. 预支递增计数（+1），写入本次启动 uptime 打点，清除后台标记；
    /// 3. 计数达到阈值 → 持久化粘滞标记并激活安全模式；
    /// 4. 未触发 → 启动存活计时，到期后自动清零计数。
    ///
    /// Call this as early as possible in `application(_:didFinishLaunchingWithOptions:)`.
    /// After this call, check `isInSafeMode` to decide whether to show a reduced UI.
    ///
    /// - Precondition: 必须在主线程调用。`didFinishLaunching` 首行调用
    ///   天然满足；Debug 构建违反将以断言暴露误用（`assert`），
    ///   Release 构建容忍（不崩溃）——防闪退库不应在宿主误用时制造
    ///   新的崩溃面，但后台线程调用存在存储读写的数据竞争风险，
    ///   请务必遵守契约。
    /// - Returns: 本次启动是否已进入安全模式（可忽略返回值）。
    @discardableResult
    public func start() -> Bool {
        assert(Thread.isMainThread, "ALLaunchGuard.start() 必须在主线程调用")
        guard !didStart else { return isInSafeMode }
        didStart = true

        registerLifecycleObservers()

        // ── 1. 裁决上一会话残留状态 ──

        // 1a. 粘滞安全模式：直接激活，不递增计数、不启动存活计时，
        //     防止"安全模式页挂满 5 秒计数被清零后杀进程重启绕过检测"。
        if storage.safeModeActive {
            activateSafeMode()
            return true
        }

        // 1b. 上次会话已进入后台：其死亡不计为启动闪退。
        if storage.lastLaunchDiedInBackground {
            storage.consecutiveCrashCount = 0
        }

        // 1c. 上次打点 uptime 大于本次 systemUptime：期间发生过设备重启，
        //     重启导致的进程终止不是启动闪退（单调时钟，不受改时间/NTP 影响）。
        if let lastUptime = storage.lastLaunchMarkUptime,
           lastUptime > ProcessInfo.processInfo.systemUptime {
            storage.consecutiveCrashCount = 0
        }

        // ── 2. 预支递增计数 + 写入本次启动打点 ──

        let count = storage.consecutiveCrashCount + 1
        storage.consecutiveCrashCount = count
        let markUptime = ProcessInfo.processInfo.systemUptime
        storage.lastLaunchMarkUptime = markUptime
        storage.lastLaunchDiedInBackground = false
        currentSessionMarkUptime = markUptime

        // ── 3. 阈值判定：持久化粘滞安全模式标记 ──

        if count >= crashThreshold {
            storage.safeModeActive = true
            activateSafeMode()
            return true
        }

        // ── 4. 启动存活计时：到期自动清零（会话代际 + 打点双重校验防误清）──

        launchGeneration += 1
        let generation = launchGeneration
        survivalScheduler { [weak self] in
            guard let self = self else { return }
            self.confirmLaunchSurvival(generation: generation, markUptime: markUptime)
        }
        return false
    }

    /// Marks the current launch as successful, resetting the crash counter.
    ///
    /// 与存活计时到期自动清零幂等共存（内部走同一确认函数）。
    /// Call this after your app has fully loaded (e.g. once the home screen is
    /// visible and all critical setup is complete).
    ///
    /// - Note: 仅作计数确认，不退出安全模式（安全模式唯一退出路径是
    ///   修复动作成功或 `reset()`）；须在 `start()` 之后调用，start 之前的
    ///   确认请求直接忽略（无会话代际与打点可校验）。
    /// - Precondition: 必须在主线程调用（与 `start()` 契约一致；Debug
    ///   构建违反将以断言暴露，Release 容忍）。
    public func markLaunchSuccessful() {
        assert(Thread.isMainThread, "ALLaunchGuard.markLaunchSuccessful() 必须在主线程调用")
        // 防御：start() 之前调用视为无效确认（无会话代际与打点可校验）
        guard didStart else { return }
        confirmLaunchSurvival(generation: launchGeneration, markUptime: currentSessionMarkUptime)
    }

    /// Resets safe mode and clears the crash counter.
    ///
    /// 唯一的粘滞安全模式退出路径：清零计数、清除粘滞标记并触发退出回调。
    /// Can be called from a safe-mode UI action (e.g. "Clear app data and restart").
    ///
    /// - Precondition: 必须在主线程调用（与 `start()` 契约一致；Debug 构建
    ///   违反将以断言暴露，Release 容忍）。`perform(_:completion:)` 编排层
    ///   内部已在主队列调用本方法，宿主直调也应保证主线程。
    public func reset() {
        assert(Thread.isMainThread, "ALLaunchGuard.reset() 必须在主线程调用")
        let wasInSafeMode = isInSafeMode
        storage.consecutiveCrashCount = 0
        storage.safeModeActive = false
        isInSafeMode = false
        if wasInSafeMode {
            delegate?.launchGuardDidExitSafeMode(self)
        }
    }

    /// 执行指定修复动作并编排结果（统一在主队列收口）。
    ///
    /// 编排语义（spec: fix-actions）：
    /// - 成功 → 触发一次 `reset()`（幂等：清零计数、清除粘滞标记、
    ///   仅曾处于安全模式时触发退出回调）并通知委托成功；
    /// - 失败 → 不改动任何安全模式状态（允许用户重试），仅通知委托失败；
    /// - 动作在调用线程执行，其 completion 可在任意线程回调，
    ///   编排层统一派发主队列处理 reset、委托回调与外部 completion。
    ///
    /// - Parameters:
    ///   - action: 要执行的修复动作（通常来自 `fixActions`）。
    ///   - completion: 动作完成回调（主队列），参数为编排后的最终成功标志。
    public func perform(
        _ action: ALLaunchGuardFixAction,
        completion: ((Bool) -> Void)? = nil
    ) {
        action.perform { [weak self] success in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if success {
                    self.reset()
                }
                self.delegate?.launchGuard(self, didFinishFixAction: action, success: success)
                completion?(success)
            }
        }
    }

    #if DEBUG
    /// 调试强制入口：强制激活安全模式并持久化粘滞标记。
    ///
    /// 仅 `#if DEBUG` 构建存在，用于测试与示例演示；Release 构建下该入口不存在。
    public func enterSafeModeForTesting() {
        storage.safeModeActive = true
        activateSafeMode()
    }
    #endif

    // MARK: - Internal（通知回调模拟入口，供测试直接调用）

    /// 进入后台回调：持久化后台标记。
    ///
    /// 下次启动裁决发现该标记时，本次死亡不计为启动闪退
    /// （覆盖系统回收 / 上滑强杀后台 / 后台 OOM 场景）。
    internal func handleDidEnterBackground() {
        storage.lastLaunchDiedInBackground = true
    }

    /// 应用正常终止回调：兜底清零计数（与存活确认共存）。
    internal func handleWillTerminate() {
        storage.consecutiveCrashCount = 0
    }

    // MARK: - Internal helpers

    /// 存活确认（幂等）：清零计数并同步清除后台死亡标记。
    ///
    /// 由存活计时到期与 `markLaunchSuccessful()` 共用。带双重会话校验：
    /// - `generation` 与当前会话代际一致（防同实例极端重入）；
    /// - 存储中的打点仍是本会话写入的值（防旧会话闭包跨会话竞态误清；
    ///   no-op 存储读回 nil 时放行，保持纯计数降级模式下的自动清零能力）。
    internal func confirmLaunchSurvival(generation: Int, markUptime: TimeInterval?) {
        guard generation == launchGeneration else { return }
        if let expected = markUptime,
           let current = storage.lastLaunchMarkUptime,
           current != expected {
            // 存储打点已被新会话覆盖，本闭包属于旧会话，放弃确认
            return
        }
        storage.consecutiveCrashCount = 0
        storage.lastLaunchDiedInBackground = false
    }

    // MARK: - Private helpers

    private func activateSafeMode() {
        isInSafeMode = true
        delegate?.launchGuardDidEnterSafeMode(self)
        #if canImport(UIKit)
        // 自动展示分流（纯函数判定，spec: safe-mode-window / design D4）：
        // .dedicatedWindow（默认）→ 独立窗口接管；.presentOnRoot → 在宿主
        // rootVC 上 present 菜单页；.none → 不自动展示（宿主自行处理 UI）
        switch Self.presentationRoute(for: _uiConfig) {
        case .none:
            break
        case .dedicatedWindow:
            activateSafeModeWindow()
        case .presentOnRoot:
            presentSafeModeMenu()
        }
        #endif
    }

    /// 注册生命周期通知观察者。
    ///
    /// UIKit 平台使用真实通知名；非 UIKit 平台注册字符串 shim 名
    /// （行为为永不触发，测试通过 internal 方法直接模拟回调）。
    private func registerLifecycleObservers() {
        backgroundObserver = NotificationCenter.default.addObserver(
            forName: ALLaunchGuardDidEnterBackgroundNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            self?.handleDidEnterBackground()
        }

        terminationObserver = NotificationCenter.default.addObserver(
            forName: ALLaunchGuardWillTerminateNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            // A clean termination (user-initiated quit) should not be treated as
            // a crash, so reset the counter here.
            self?.handleWillTerminate()
        }
    }
}

// MARK: - 展示路径分流（跨平台纯函数，可在 macOS/Linux 单测）

/// 安全模式激活后自动展示路径的判定结果（design D4）。
internal enum ALLaunchGuardPresentationRoute: Equatable {
    /// 不自动展示（`autoPresent == false`，宿主自行处理 UI）
    case none
    /// 独立 UIWindow 接管（默认，spec: safe-mode-window）
    case dedicatedWindow
    /// 在宿主 key window rootVC 上 present（root 挂载展示选项）
    case presentOnRoot
}

extension ALLaunchGuard {
    /// 展示路径分流纯函数（无 UIKit 依赖，macOS/Linux 可直接单测）：
    /// - `autoPresent == false` → `.none`（与样式无关）；
    /// - 否则按 `presentationStyle` 分流：`.dedicatedWindow`（默认）/
    ///   `.presentOnRoot`（在宿主 rootVC 上 present 菜单页）。
    internal static func presentationRoute(
        for config: ALLaunchGuardConfig
    ) -> ALLaunchGuardPresentationRoute {
        guard config.autoPresent else { return .none }
        switch config.presentationStyle {
        case .dedicatedWindow:
            return .dedicatedWindow
        case .presentOnRoot:
            return .presentOnRoot
        }
    }
}

// MARK: - 菜单式安全模式页展示（UIKit）

#if canImport(UIKit)
public extension ALLaunchGuard {

    /// 显式窗口接管入口：以独立 UIWindow 接管显示菜单式安全模式页
    ///（spec: safe-mode-window）。
    ///
    /// 供宿主在 `didFinishLaunching` 中 `start()` 返回 true 后、return 前
    /// 手动调用（宿主跳过全部启动任务的分流范式）；与自动展示路径
    ///（`presentationStyle == .dedicatedWindow`）共用同一协调器且幂等——
    /// 重复调用不会创建多个窗口。任意线程调用均安全：已在主线程时同步
    /// 执行（design D1——didFinishLaunching 首行调用时，willConnect 观察
    /// 者先于通知发出注册，修复 main.async 派发错过通知的时序缺陷），
    /// 非主线程派发主队列。窗口在安全模式激活期间不会自动关闭，等待
    /// 用户修复并手动重启。
    func activateSafeModeWindow() {
        let installWindow: () -> Void = { [weak self] in
            guard let self = self else { return }
            self.safeModeWindowCoordinator.install(
                rootViewController: ALLaunchGuardSafeModeViewController(
                    launchGuard: self,
                    config: self.uiConfig
                )
            )
        }
        if Thread.isMainThread {
            installWindow()
        } else {
            DispatchQueue.main.async(execute: installWindow)
        }
    }

    /// 在 key window 的 root view controller 上展示菜单式安全模式页。
    ///
    /// root 挂载展示路径（spec: safe-mode-window）：`presentationStyle == .presentOnRoot`
    /// 且 autoPresent 时由库在激活时自动调用，宿主也可随时手动调用。
    /// present 派发主队列异步执行，keyWindow 查找兼容 iOS 15（scene.keyWindow）
    /// 与 iOS 14（windows 过滤）。默认路径（.dedicatedWindow）为独立
    /// UIWindow 接管（见 `activateSafeModeWindow()`）。
    ///
    /// 防重入（fix-review-findings design D3）：present 闭包内沿 rootVC 的
    /// presented 链递归检查，链上任一节点已是菜单页时跳过本次展示——
    /// 避免激活回调与宿主手动调用叠加多页、并发执行同一动作。
    func presentSafeModeMenu() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            guard let rootVC = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .compactMap({ scene -> UIViewController? in
                    if #available(iOS 15.0, *) {
                        return scene.keyWindow?.rootViewController
                    } else {
                        return scene.windows.first(where: { $0.isKeyWindow })?.rootViewController
                    }
                })
                .first else { return }

            // 防重入：沿 presented 链递归检查（含 rootVC 自身），
            // 已存在菜单页则跳过本次展示
            var candidate: UIViewController? = rootVC
            while let current = candidate {
                if current is ALLaunchGuardSafeModeViewController { return }
                candidate = current.presentedViewController
            }

            let vc = ALLaunchGuardSafeModeViewController(launchGuard: self, config: self.uiConfig)
            rootVC.present(vc, animated: true)
        }
    }
}
#endif

// MARK: - UIApplication notification name shims

/// 跨平台通知名：UIKit 下用真实通知，非 UIKit 平台用字符串 shim 保持可编译。
#if canImport(UIKit)
private let ALLaunchGuardDidEnterBackgroundNotification = UIApplication.didEnterBackgroundNotification
private let ALLaunchGuardWillTerminateNotification = UIApplication.willTerminateNotification
#else
private let ALLaunchGuardDidEnterBackgroundNotification = Notification.Name(
    "UIApplicationDidEnterBackgroundNotification"
)
private let ALLaunchGuardWillTerminateNotification = Notification.Name(
    "UIApplicationWillTerminateNotification"
)
#endif
