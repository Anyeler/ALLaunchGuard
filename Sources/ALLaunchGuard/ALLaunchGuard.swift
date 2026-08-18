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
/// `@unchecked Sendable`（upgrade-swift-6-beta）：外部同步依据——stateLock 已
/// 串行化全部自身可变状态与锁内 storage 读写（harden-thread-safety design D1，
/// TSan 全绿 + 8 路 hammer 锚定）；锁外副作用（delegate / 最小任务 / UI 安装）
/// 各自有主队列 / 锁外纪律约束。新增可变状态 MUST 纳入 stateLock 保护，
/// 否则本标注失效。否决 @MainActor 单例的依据见 upgrade-swift-6-beta design D1。
public final class ALLaunchGuard: @unchecked Sendable {

    // MARK: - Public

    /// Shared singleton instance.
    public static let shared = ALLaunchGuard()

    /// Returns `true` when the guard has activated safe mode.
    ///
    /// 对外只读（fix-pr3-review-comments：移除公开 setter，恢复 2.0 的
    /// 只读 API 面，外部不得篡改安全模式状态）；内部经 `_isInSafeMode`
    /// 在 `stateLock` 内更新（activateSafeMode 置位 / reset 清零）。
    /// 任意线程可读（harden-thread-safety：读路径经 `stateLock` 串行化）。
    public var isInSafeMode: Bool {
        get { withStateLock { _isInSafeMode } }
    }

    /// Number of consecutive crash-on-launch events before safe mode activates.
    /// Defaults to `3`. 存取经 `stateLock` 串行化。
    public var crashThreshold: Int {
        get { withStateLock { _crashThreshold } }
        set { withStateLock { _crashThreshold = newValue } }
    }

    /// 存活确认时长（秒）：启动后进程存活满该时长即视为一次正常启动，
    /// 计数自动清零，不再依赖宿主手动调用 `markLaunchSuccessful()`。
    /// Defaults to `5`. 存取经 `stateLock` 串行化。
    public var survivalTimeout: TimeInterval {
        get { withStateLock { _survivalTimeout } }
        set { withStateLock { _survivalTimeout = newValue } }
    }

    /// 极早期无副作用查询：读取粘滞安全模式标记或计数与阈值的关系。
    ///
    /// 可在 `start()` 之前（宿主启动最早期）调用，不改变任何存储状态。
    /// 任意线程可读（harden-thread-safety：经 `stateLock` 串行化，并发写
    /// 下不读到撕裂状态）。
    public var shouldEnterSafeMode: Bool {
        withStateLock {
            storage.safeModeActive || storage.consecutiveCrashCount >= _crashThreshold
        }
    }

    /// Delegate to receive safe-mode lifecycle events.
    /// 存取经 `stateLock` 串行化。
    public var delegate: ALLaunchGuardDelegate? {
        get { withStateLock { _delegate } }
        set { withStateLock { _delegate = newValue } }
    }

    /// Configuration for the built-in safe-mode UI.
    ///
    /// Assign before calling `start()` when using `autoPresent = true`.
    /// 存取经 `stateLock` 串行化。
    public var uiConfig: ALLaunchGuardConfig {
        get { withStateLock { _uiConfig } }
        set { withStateLock { _uiConfig = newValue } }
    }

    /// 已注册的修复动作（安全模式菜单项数据源）。
    ///
    /// 宿主可在启动早期（如 `didFinishLaunching` 首行）直接赋值，
    /// 内置动作与自定义动作可混排，注册顺序即菜单展示顺序；默认为空数组。
    /// 库 MUST NOT 在进入安全模式时自动执行任何动作——仅用户显式触发
    ///（通过 `perform(_:completion:)`）。
    ///
    /// 动作会被强持有（生命周期与本单例同长），实现方应轻持有依赖。
    /// 存取经 `stateLock` 串行化。
    public var fixActions: [ALLaunchGuardFixAction] {
        get { withStateLock { _fixActions } }
        set { withStateLock { _fixActions = newValue } }
    }

    /// 安全模式最小启动任务：进入安全模式时同步按序执行。
    ///
    /// 安全模式激活时（阈值触发 / 粘滞触发 / 调试直入，任一路径），库在
    /// `isInSafeMode` 置位后、委托回调 `launchGuardDidEnterSafeMode` 与安全
    /// 模式 UI 安装**之前**，按注册顺序同步执行全部任务，保证最小模块
    /// （如日志上报 SDK）在修复页呈现前就绪。每个进程生命周期内仅执行
    /// 一次（同进程内重复激活不重复执行；进程重启即新实例，会再次执行）。
    /// 任务内可安全读取 `isInSafeMode`（已置位）。
    ///
    /// 任务约束（宿主必须遵守，库不做运行时防护）：
    /// - 自包含：不得依赖宿主正常启动图中的模块（安全模式下正常启动图
    ///   被整体跳过）；
    /// - 轻量同步：在安全模式首帧前的主线程执行，重量级任务会拖慢
    ///   修复页呈现，且任务崩溃会导致安全模式页无法呈现（由粘滞标记
    ///   兜底：下次启动仍进安全模式）；
    /// - 不做磁盘 IO；
    /// - 禁止触碰启动编排器内部状态。使用启动编排器的宿主可在闭包内
    ///   桥接编排器的最小任务执行能力——本库不依赖、不引用任何启动
    ///   编排器。
    ///
    /// 默认空数组：行为与未引入本能力时完全一致。存取经 `stateLock` 串行化。
    public var safeModeLaunchTasks: [() -> Void] {
        get { withStateLock { _safeModeLaunchTasks } }
        set { withStateLock { _safeModeLaunchTasks = newValue } }
    }

    // MARK: - Internal（测试注入）

    /// 存活计时调度器：接收存活确认闭包，并在 `survivalTimeout` 到期后执行。
    ///
    /// 非公共 API：单元测试通过 `@testable` 注入立即执行 / no-op 实现。
    /// 声明处给 no-op 默认值以保证 init 内可安全重建（见 init 说明）。
    internal var survivalScheduler: (@escaping () -> Void) -> Void = { _ in }

    // MARK: - Private

    private let storage: ALLaunchGuardStorage

    /// 核心状态串行化锁（harden-thread-safety，design D1）：保护全部自身
    /// 可变状态与锁内的 storage 读写，使任意线程读路径（shouldEnterSafeMode /
    /// isInSafeMode）在并发写下不读到撕裂或中间状态。负载为启动期个位数次
    /// 微秒级临界区，故选 NSLock（非递归）而非读写锁 / Actor。
    ///
    /// 纪律红线（防重入死锁）：锁内 MUST NOT 触达宿主代码——delegate 回调、
    /// safeModeLaunchTasks 执行、窗口安装 / present、action.perform 与
    /// completion 派发一律锁外执行；锁内只算决策快照，解锁后再执行副作用。
    /// 锁内如需读写受保护状态，直接访问下方 `_` 前缀私有存储属性
    ///（经计算属性会重入加锁而死锁）。
    private let stateLock = NSLock()

    /// 加锁执行并返回结果（harden-thread-safety design D1）。
    @inline(__always)
    private func withStateLock<T>(_ body: () -> T) -> T {
        stateLock.lock()
        defer { stateLock.unlock() }
        return body()
    }

    private var didStart = false

    /// 最小启动任务幂等门控（design D2）：首次执行后置 true，
    /// 同一进程内重复激活安全模式不重复执行；进程重启即新实例，语义为
    /// “每进程一次”。
    private var didRunSafeModeLaunchTasks = false

    /// 会话代际标记：每次启动存活计时时自增。
    /// 计时闭包捕获启动时的代际值，触发时仅当代际仍匹配才执行确认，
    /// 防止旧会话的挂起计时闭包在跨会话竞态中误清新会话计数。
    private var launchGeneration = 0

    /// 本会话 start() 写入的 uptime 打点（供 markLaunchSuccessful 复用校验）。
    private var currentSessionMarkUptime: TimeInterval?

    private var backgroundObserver: NSObjectProtocol?
    private var terminationObserver: NSObjectProtocol?
    private var _uiConfig: ALLaunchGuardConfig = .default

    /// 锁保护的存储属性（经上方同名计算属性对外暴露，harden-thread-safety）。
    private var _isInSafeMode = false
    private var _crashThreshold: Int
    private var _survivalTimeout: TimeInterval = 5
    private weak var _delegate: ALLaunchGuardDelegate?
    private var _fixActions: [ALLaunchGuardFixAction] = []
    private var _safeModeLaunchTasks: [() -> Void] = []

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
        self._crashThreshold = crashThreshold
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
        return performStart()
    }

    /// 内部测试入口（fix-pr3-review-comments tasks 1.3）：与 `start()` 语义
    /// 完全一致，仅豁免主线程断言——供并发幂等用例从多线程并发调用
    ///（公开契约仍要求主线程调用，Release 下后台线程 start 本就容忍不崩）。
    /// 非公共 API，仅 `@testable` 可见。
    internal func startForConcurrencyTesting() -> Bool {
        performStart()
    }

    /// start() 主体：单次加锁的原子 check-and-set 决策（fix-pr3-review-comments
    /// tasks 1.1，修复 didStart 检查与置位分裂在两个临界区的幂等缺陷）。
    ///
    /// 锁内一次性完成：幂等门控检查-置位 + 裁决上一会话残留 + 预支写序列
    /// + 阈值粘滞置位 + 存活计时会话快照；锁外仅执行副作用（通知注册、
    /// 激活安全模式、存活计时调度）。锁内只算决策快照，激活副作用
    ///（最小任务 / delegate / UI）一律锁外执行（design D1 纪律红线）。
    private func performStart() -> Bool {
        /// 单次加锁决策段产出的快照（锁内只算决策，锁外执行副作用）。
        struct StartDecision {
            let alreadyStarted: Bool
            let shouldActivate: Bool
            /// 未激活路径的存活计时会话快照（代际 + 本次打点）
            let survivalGeneration: Int
            let survivalMarkUptime: TimeInterval
        }

        let decision: StartDecision = withStateLock {
            // ── 幂等门控：检查-置位原子化（同一临界区内完成）──
            // 重复调用直接返回快照，不再注册观察者、不再写存储。
            guard !didStart else {
                return StartDecision(
                    alreadyStarted: true,
                    shouldActivate: false,
                    survivalGeneration: 0,
                    survivalMarkUptime: 0
                )
            }
            didStart = true

            // ── 1. 裁决上一会话残留状态 ──

            // 1a. 粘滞安全模式：直接激活，不递增计数、不启动存活计时，
            //     防止“安全模式页挂满 5 秒计数被清零后杀进程重启绕过检测”。
            //     （isInSafeMode 置位由 activateSafeMode 锁内决策完成）
            if storage.safeModeActive {
                return StartDecision(
                    alreadyStarted: false,
                    shouldActivate: true,
                    survivalGeneration: 0,
                    survivalMarkUptime: 0
                )
            }

            // 1b/1c. 上一会话死亡不计为启动闪退时清零计数（两条裁决依据，任一成立即可）：
            //     ① 上次已进入后台（系统回收 / 上滑强杀后台 / 后台 OOM）；
            //     ② 上次打点 uptime 大于本次 systemUptime：期间发生过设备重启，
            //        重启导致的进程终止不是启动闪退（单调时钟，不受改时间/NTP 影响）。
            if storage.lastLaunchDiedInBackground
                || (storage.lastLaunchMarkUptime.map { $0 > ProcessInfo.processInfo.systemUptime } ?? false) {
                storage.consecutiveCrashCount = 0
            }

            // ── 2. 预支递增计数 + 写入本次启动打点（新写序，design D2）──
            //
            // 崩溃原子性偏向多计：标记清零 → 打点 → count 最后写。任意相邻
            // 两次写之间进程终止时，次启裁决保留本次闪退计数：
            // ①标记已清、打点未写 → 次启按“无打点”处理，旧计数保留 +1
            //   （多计一次，安全）；②打点已写、count 未写 → 次启读到新打点
            //   与旧计数，正常 +1（正确）。宁可多计触发安全模式（宿主有
            //   reset 出口），不可漏检崩溃循环（旧序 count 先写会在“count
            //   已写、标记未清”死亡时被残留标记误清零）。
            let count = storage.consecutiveCrashCount + 1
            let markUptime = ProcessInfo.processInfo.systemUptime
            storage.lastLaunchDiedInBackground = false
            storage.lastLaunchMarkUptime = markUptime
            storage.consecutiveCrashCount = count
            currentSessionMarkUptime = markUptime

            // ── 3. 阈值判定：持久化粘滞安全模式标记 ──

            if count >= _crashThreshold {
                storage.safeModeActive = true
                return StartDecision(
                    alreadyStarted: false,
                    shouldActivate: true,
                    survivalGeneration: 0,
                    survivalMarkUptime: 0
                )
            }

            // ── 4. 未触发：产出存活计时会话快照（代际自增 + 本次打点）──
            launchGeneration += 1
            return StartDecision(
                alreadyStarted: false,
                shouldActivate: false,
                survivalGeneration: launchGeneration,
                survivalMarkUptime: currentSessionMarkUptime ?? 0
            )
        }

        // 重复调用：返回当前 isInSafeMode 的锁内快照（不重复注册观察者）。
        guard !decision.alreadyStarted else { return withStateLock { _isInSafeMode } }

        // 通知观察者注册在锁外（无自身状态读写，回调统一主队列，tasks 2.1）；
        // didStart 原子 check-and-set 保证仅首次调用执行到此处（恰一次）。
        registerLifecycleObservers()

        // ── 锁外副作用：激活安全模式（最小任务 / delegate / UI）──
        if decision.shouldActivate {
            activateSafeMode()
            return true
        }

        // ── 启动存活计时：到期自动清零（会话代际 + 打点双重校验防误清）──
        survivalScheduler { [weak self] in
            guard let self = self else { return }
            self.confirmLaunchSurvival(
                generation: decision.survivalGeneration,
                markUptime: decision.survivalMarkUptime
            )
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
        // 锁内取会话快照；防御：start() 之前调用视为无效确认（无会话代际与打点可校验）
        let snapshot: (generation: Int, markUptime: TimeInterval?)? = withStateLock {
            guard didStart else { return nil }
            return (launchGeneration, currentSessionMarkUptime)
        }
        guard let (generation, markUptime) = snapshot else { return }
        confirmLaunchSurvival(generation: generation, markUptime: markUptime)
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
        // 锁内：状态读 + storage 写 + isInSafeMode 写原子化
        let wasInSafeMode = withStateLock { () -> Bool in
            let was = _isInSafeMode
            storage.consecutiveCrashCount = 0
            storage.safeModeActive = false
            _isInSafeMode = false
            return was
        }
        // 锁外：delegate 退出回调（防重入死锁，design D1 纪律红线）
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
        // upgrade-swift-6-beta：本方法为任务隔离上下文，action/completion 经
        // 主队列派发跨隔离发送，在新编译器下从计划预期的 warning 升级为
        // sending error；以 nonisolated(unsafe) 快照捕获作最小收口（运行时
        // 语义不变：completion 统一主队列收口、action 生命周期与单例同长），
        // 根治（协议族 Sendable 化）留待转正 3.0 路线图（design D2）。
        nonisolated(unsafe) let sentAction = action
        nonisolated(unsafe) let sentCompletion = completion
        action.perform { [weak self] success in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if success {
                    self.reset()
                }
                self.delegate?.launchGuard(self, didFinishFixAction: sentAction, success: success)
                sentCompletion?(success)
            }
        }
    }

    #if DEBUG
    /// 调试强制入口：强制激活安全模式并持久化粘滞标记。
    ///
    /// 仅 `#if DEBUG` 构建存在，用于测试与示例演示；Release 构建下该入口不存在。
    public func enterSafeModeForTesting() {
        // 锁内写粘滞标记；激活决策（isInSafeMode 置位）由 activateSafeMode
        // 锁内完成，副作用锁外执行
        withStateLock { storage.safeModeActive = true }
        activateSafeMode()
    }
    #endif

    // MARK: - Internal（通知回调模拟入口，供测试直接调用）

    /// 进入后台回调：持久化后台标记。
    ///
    /// 下次启动裁决发现该标记时，本次死亡不计为启动闪退
    /// （覆盖系统回收 / 上滑强杀后台 / 后台 OOM 场景）。
    /// storage 写入经 withStateLock 串行化（upgrade-swift-6-beta 竞态收口）：
    /// 与任意线程锁内读的 shouldEnterSafeMode 同锁保护，无撕裂读。
    internal func handleDidEnterBackground() {
        withStateLock { storage.lastLaunchDiedInBackground = true }
    }

    /// 应用正常终止回调：兜底清零计数（与存活确认共存）。
    /// storage 写入经 withStateLock 串行化（upgrade-swift-6-beta 竞态收口，
    /// 同 handleDidEnterBackground 依据）。
    internal func handleWillTerminate() {
        withStateLock { storage.consecutiveCrashCount = 0 }
    }

    // MARK: - Internal helpers

    /// 存活确认（幂等）：清零计数并同步清除后台死亡标记。
    ///
    /// 由存活计时到期与 `markLaunchSuccessful()` 共用。带双重会话校验：
    /// - `generation` 与当前会话代际一致（防同实例极端重入）；
    /// - 存储中的打点仍是本会话写入的值（防旧会话闭包跨会话竞态误清；
    ///   no-op 存储读回 nil 时放行，保持纯计数降级模式下的自动清零能力）。
    internal func confirmLaunchSurvival(generation: Int, markUptime: TimeInterval?) {
        // 锁内：代际 / 打点校验与两处 storage 写原子化（harden-thread-safety）
        withStateLock {
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
    }

    // MARK: - Private helpers

    /// 激活安全模式（harden-thread-safety design D1）：锁内决策快照 + 锁外副作用。
    ///
    /// 三条激活路径（start 阈值 / 粘滞 / DEBUG 入口）统一走本方法，锁内
    /// 完成 isInSafeMode 置位与最小任务门控（didRunSafeModeLaunchTasks，
    /// 防重复置位 / 重复执行），锁外执行全部宿主副作用——delegate 回调、
    /// safeModeLaunchTasks、窗口安装 / present 均不持锁（防重入死锁），
    /// 宿主回调内可安全回读受保护状态（shouldEnterSafeMode / isInSafeMode）。
    private func activateSafeMode() {
        // 锁内决策：置位 + 门控，并快照本次应执行的任务清单
        let tasksToRun: [() -> Void]? = withStateLock {
            _isInSafeMode = true
            guard !didRunSafeModeLaunchTasks else { return nil }
            didRunSafeModeLaunchTasks = true
            return _safeModeLaunchTasks
        }

        // 锁外副作用①：安全模式最小启动任务（spec: crash-detection ADDED，
        // design D1/D2）——在委托回调与 UI 安装之前同步按序执行，每进程仅
        // 一次；任务内可安全读 isInSafeMode（已在锁内置位）。
        tasksToRun?.forEach { $0() }

        // 锁外副作用②：delegate 进入回调
        delegate?.launchGuardDidEnterSafeMode(self)

        #if canImport(UIKit)
        // 锁外副作用③：自动展示分流（纯函数判定，spec: safe-mode-window /
        // design D4）：.dedicatedWindow（默认）→ 独立窗口接管；.presentOnRoot
        // → 在宿主 rootVC 上 present 菜单页；.none → 不自动展示
        //（宿主自行处理 UI）
        switch Self.presentationRoute(for: uiConfig) {
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
    ///（行为为永不触发，测试通过 internal 方法直接模拟回调）。
    ///
    /// 观察队列显式绑定主队列（harden-thread-safety tasks 2.1）：UIKit 生命
    /// 周期通知本就主线程发帖，行为不变但隐式主线程契约升级为结构保证；
    /// 回调与锁路径同队列，无新竞争。
    private func registerLifecycleObservers() {
        backgroundObserver = NotificationCenter.default.addObserver(
            forName: ALLaunchGuardDidEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleDidEnterBackground()
        }

        terminationObserver = NotificationCenter.default.addObserver(
            forName: ALLaunchGuardWillTerminateNotification,
            object: nil,
            queue: .main
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
