import XCTest
@testable import ALLaunchGuard

// MARK: - In-memory storage

final class MockStorage: ALLaunchGuardStorage {
    var consecutiveCrashCount: Int = 0
    var lastLaunchMarkUptime: TimeInterval?
    var lastLaunchDiedInBackground = false
    var safeModeActive = false
}

// MARK: - 仅实现旧协议的存储（验证 protocol extension 默认实现的向后兼容）

final class LegacyStorage: ALLaunchGuardStorage {
    var consecutiveCrashCount: Int = 0
}

// MARK: - Fake schedulers（存活计时注入）

/// 立即执行调度器：模拟存活计时立即到期（进程存活满阈值时长）
let immediateScheduler: (@escaping () -> Void) -> Void = { work in work() }

/// no-op 调度器：模拟计时无机会执行（进程在阈值时长内死亡）
let noOpScheduler: (@escaping () -> Void) -> Void = { _ in }

// MARK: - Mock delegate

final class MockDelegate: ALLaunchGuardDelegate {
    var enteredSafeMode = false
    /// 退出安全模式回调次数（0 即未退出；曾为 exitedSafeMode/exitCount 双状态，
    /// cleanup-unused-code 合一）
    var exitCount = 0
    /// 进入安全模式时额外执行的记录闭包（供最小启动任务顺序断言注入）
    var onEnterSafeMode: (() -> Void)?
    /// 已完成的修复动作记录（action, success），供编排层测试断言
    private(set) var finishedActions: [(action: ALLaunchGuardFixAction, success: Bool)] = []

    var finishCount: Int { finishedActions.count }
    var lastFinishSuccess: Bool? { finishedActions.last?.success }

    func launchGuardDidEnterSafeMode(_ guard: ALLaunchGuard) {
        enteredSafeMode = true
        onEnterSafeMode?()
    }

    func launchGuardDidExitSafeMode(_ guard: ALLaunchGuard) {
        exitCount += 1
    }

    func launchGuard(
        _ launchGuard: ALLaunchGuard,
        didFinishFixAction action: ALLaunchGuardFixAction,
        success: Bool
    ) {
        finishedActions.append((action, success))
    }
}

// MARK: - Tests

final class ALLaunchGuardTests: XCTestCase {

    // MARK: Normal launch flow

    func testFirstLaunchIsNotSafeMode() {
        let storage = MockStorage()
        let guard_ = ALLaunchGuard(storage: storage, crashThreshold: 3)
        guard_.start()
        XCTAssertFalse(guard_.isInSafeMode)
    }

    // MARK: Safe mode activation

    func testSafeModeActivatesAtThreshold() {
        let storage = MockStorage()
        storage.consecutiveCrashCount = 2   // will become 3 after start()
        let guard_ = ALLaunchGuard(storage: storage, crashThreshold: 3)
        guard_.start()
        XCTAssertTrue(guard_.isInSafeMode)
    }

    /// 未达阈值不激活；成功启动确认（markLaunchSuccessful）重置预支计数
    ///（原 testSuccessfulLaunchResetsCrashCounter 重叠断言并入，语义不减）
    func testSafeModeNotActivatedBelowThreshold() {
        let storage = MockStorage()
        storage.consecutiveCrashCount = 1   // will become 2 after start()
        let guard_ = ALLaunchGuard(storage: storage, crashThreshold: 3)
        guard_.survivalScheduler = noOpScheduler
        guard_.start()
        XCTAssertFalse(guard_.isInSafeMode)
        guard_.markLaunchSuccessful()
        XCTAssertEqual(storage.consecutiveCrashCount, 0)
    }

    func testDelegateCalledOnSafeModeEntry() {
        let storage = MockStorage()
        storage.consecutiveCrashCount = 2
        let guard_ = ALLaunchGuard(storage: storage, crashThreshold: 3)
        let delegate = MockDelegate()
        guard_.delegate = delegate
        guard_.start()
        XCTAssertTrue(delegate.enteredSafeMode)
    }

    func testDelegateNotCalledOnResetWhenNotInSafeMode() {
        let storage = MockStorage()
        let guard_ = ALLaunchGuard(storage: storage, crashThreshold: 3)
        let delegate = MockDelegate()
        guard_.delegate = delegate
        guard_.start()   // count=1, not in safe mode
        guard_.reset()
        XCTAssertEqual(delegate.exitCount, 0)
    }

    // MARK: Reset

    func testResetClearsSafeMode() {
        let storage = MockStorage()
        storage.consecutiveCrashCount = 2
        let guard_ = ALLaunchGuard(storage: storage, crashThreshold: 3)
        guard_.start()
        XCTAssertTrue(guard_.isInSafeMode)
        guard_.reset()
        XCTAssertFalse(guard_.isInSafeMode)
        XCTAssertEqual(storage.consecutiveCrashCount, 0)
    }

    func testDelegateCalledOnReset() {
        let storage = MockStorage()
        storage.consecutiveCrashCount = 2
        let guard_ = ALLaunchGuard(storage: storage, crashThreshold: 3)
        let delegate = MockDelegate()
        guard_.delegate = delegate
        guard_.start()
        guard_.reset()
        XCTAssertEqual(delegate.exitCount, 1)
    }

    // MARK: start() idempotency

    func testStartIsIdempotent() {
        let storage = MockStorage()
        let guard_ = ALLaunchGuard(storage: storage, crashThreshold: 3)
        guard_.start()
        guard_.start()
        // Counter should only be incremented once
        XCTAssertEqual(storage.consecutiveCrashCount, 1)
    }

    // MARK: Custom threshold

    func testCustomThreshold() {
        let storage = MockStorage()
        let guard_ = ALLaunchGuard(storage: storage, crashThreshold: 1)
        guard_.start()
        XCTAssertTrue(guard_.isInSafeMode)
    }

    // MARK: ALLaunchGuardConfig

    func testConfigDefaultValues() {
        let config = ALLaunchGuardConfig()
        XCTAssertFalse(config.title.isEmpty)
        XCTAssertFalse(config.message.isEmpty)
        // restartHint 默认重启提示文案非空（fixButtonTitle 已移除，本次迁移）
        XCTAssertFalse(config.restartHint.isEmpty)
        XCTAssertTrue(config.autoPresent)
        // 重启按钮配置默认值（spec: safe-mode-ui MODIFIED）
        XCTAssertEqual(config.restartButtonTitle, "重启应用")
        XCTAssertTrue(config.allowRestartExit)
    }

    func testConfigCustomValues() {
        let config = ALLaunchGuardConfig(
            title: "My Title",
            message: "My Message",
            restartHint: "Please restart the app",
            restartButtonTitle: "Relaunch Now",
            allowRestartExit: false,
            autoPresent: false
        )
        XCTAssertEqual(config.title, "My Title")
        XCTAssertEqual(config.message, "My Message")
        XCTAssertEqual(config.restartHint, "Please restart the app")
        XCTAssertFalse(config.autoPresent)
        XCTAssertEqual(config.restartButtonTitle, "Relaunch Now")
        XCTAssertFalse(config.allowRestartExit)
    }

    /// uiConfig setter 冒烟：macOS 测试环境下 autoPresent 无可影响的行为面
    ///（展示分流仅存在于 UIKit），仅验证赋值与读回；激活行为不受 autoPresent
    /// 影响已由阈值/任务类用例覆盖（原全链路用例断言语义无损失）。
    func testAutoPresentFalseUiConfigSetterSmoke() {
        let guard_ = ALLaunchGuard(storage: MockStorage(), crashThreshold: 3)
        var config = ALLaunchGuardConfig()
        config.autoPresent = false
        guard_.uiConfig = config
        XCTAssertFalse(guard_.uiConfig.autoPresent)
    }

    // MARK: 展示样式与自动展示分流（tasks 1.1，spec: safe-mode-window）

    /// presentationStyle 默认 .dedicatedWindow（独立窗口接管，BREAKING 2.0.0）
    func testConfigPresentationStyleDefaultsToDedicatedWindow() {
        XCTAssertEqual(ALLaunchGuardConfig().presentationStyle, .dedicatedWindow)
        XCTAssertEqual(ALLaunchGuardConfig.default.presentationStyle, .dedicatedWindow)
    }

    /// 自定义 .presentOnRoot：构造参数注入与事后赋值均生效（兼容旧行为）
    func testConfigPresentationStyleCustomPresentOnRoot() {
        let custom = ALLaunchGuardConfig(presentationStyle: .presentOnRoot)
        XCTAssertEqual(custom.presentationStyle, .presentOnRoot)

        var mutated = ALLaunchGuardConfig()
        mutated.presentationStyle = .presentOnRoot
        XCTAssertEqual(mutated.presentationStyle, .presentOnRoot)
    }

    /// 分流纯函数表驱动：autoPresent × presentationStyle → 期望展示路径
    func testPresentationRouteTableDriven() {
        let cases: [
            (autoPresent: Bool,
             style: ALLaunchGuardPresentationStyle,
             expected: ALLaunchGuardPresentationRoute)
        ] = [
            // autoPresent 为真：按 presentationStyle 分流
            (true,  .dedicatedWindow, .dedicatedWindow),   // 默认：独立窗口接管
            (true,  .presentOnRoot,   .presentOnRoot),     // 兼容旧 present 路径
            // autoPresent 为假：不自动展示，与样式无关
            (false, .dedicatedWindow, .none),
            (false, .presentOnRoot,   .none),
        ]
        for testCase in cases {
            let config = ALLaunchGuardConfig(
                autoPresent: testCase.autoPresent,
                presentationStyle: testCase.style
            )
            XCTAssertEqual(
                ALLaunchGuard.presentationRoute(for: config),
                testCase.expected,
                "autoPresent=\(testCase.autoPresent), style=\(testCase.style)"
            )
        }
    }

    // MARK: 存储协议扩展向后兼容（tasks 1.3）

    func testLegacyStorageUsesNoOpDefaultsAndDegradesToPureCounting() {
        let storage = LegacyStorage()

        // 默认实现：读取返回 nil / false
        XCTAssertNil(storage.lastLaunchMarkUptime)
        XCTAssertFalse(storage.lastLaunchDiedInBackground)
        XCTAssertFalse(storage.safeModeActive)

        // 默认实现：写入被忽略
        storage.lastLaunchMarkUptime = 123
        storage.lastLaunchDiedInBackground = true
        storage.safeModeActive = true
        XCTAssertNil(storage.lastLaunchMarkUptime)
        XCTAssertFalse(storage.lastLaunchDiedInBackground)
        XCTAssertFalse(storage.safeModeActive)

        // 降级为纯计数模式：计数仍递增，达阈值仍进安全模式，不崩溃
        storage.consecutiveCrashCount = 2
        let guard_ = ALLaunchGuard(storage: storage, crashThreshold: 3)
        guard_.start()
        XCTAssertTrue(guard_.isInSafeMode)
        XCTAssertEqual(storage.consecutiveCrashCount, 3)
    }

    func testUserDefaultsStorageRoundTripsNewFields() {
        let suiteName = "ALLaunchGuardTests.defaults.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let storage = UserDefaultsLaunchGuardStorage(defaults: defaults)

        // 初始：无记录
        XCTAssertNil(storage.lastLaunchMarkUptime)
        XCTAssertFalse(storage.lastLaunchDiedInBackground)
        XCTAssertFalse(storage.safeModeActive)

        // 写入后读回保持一致
        storage.lastLaunchMarkUptime = 12345.678
        storage.lastLaunchDiedInBackground = true
        storage.safeModeActive = true
        XCTAssertEqual(storage.lastLaunchMarkUptime ?? -1, 12345.678, accuracy: 0.0001)
        XCTAssertTrue(storage.lastLaunchDiedInBackground)
        XCTAssertTrue(storage.safeModeActive)

        // 0 是合法打点值，不得被当作“无记录”（nil 语义）
        storage.lastLaunchMarkUptime = 0
        XCTAssertEqual(storage.lastLaunchMarkUptime ?? -1, 0, accuracy: 0.0001)

        // 置 nil 后恢复无记录状态
        storage.lastLaunchMarkUptime = nil
        XCTAssertNil(storage.lastLaunchMarkUptime)

        // 同 suite 的新实例读到同一持久化结果
        storage.lastLaunchDiedInBackground = true
        let another = UserDefaultsLaunchGuardStorage(defaults: defaults)
        XCTAssertTrue(another.lastLaunchDiedInBackground)
        XCTAssertTrue(another.safeModeActive)
    }

    // MARK: 判定状态机（tasks 2.1，spec: crash-detection）

    /// 3 次短命启动第 3 次触发；第 4 次因粘滞标记直接安全模式且计数不递增
    func testThreeShortLivedLaunchesTriggerSafeModeOnThird() {
        let storage = MockStorage()
        for _ in 0..<2 {
            let guard_ = ALLaunchGuard(storage: storage, crashThreshold: 3)
            guard_.survivalScheduler = noOpScheduler   // 短命：存活计时无机会执行
            XCTAssertFalse(guard_.start())
            XCTAssertFalse(guard_.isInSafeMode)
        }
        XCTAssertEqual(storage.consecutiveCrashCount, 2)

        // 第 3 次启动：预支递增后达到阈值，当场触发
        let third = ALLaunchGuard(storage: storage, crashThreshold: 3)
        third.survivalScheduler = noOpScheduler
        XCTAssertTrue(third.start())
        XCTAssertTrue(third.isInSafeMode)
        XCTAssertTrue(storage.safeModeActive)
        XCTAssertEqual(storage.consecutiveCrashCount, 3)

        // 第 4 次启动：粘滞标记直接安全模式，计数不再递增
        let fourth = ALLaunchGuard(storage: storage, crashThreshold: 3)
        fourth.survivalScheduler = noOpScheduler
        XCTAssertTrue(fourth.start())
        XCTAssertEqual(storage.consecutiveCrashCount, 3)
    }

    /// 进程存活满 survivalTimeout：计时到期自动清零计数，不依赖宿主手动调用
    func testSurvivalConfirmationClearsCounterAutomatically() {
        let storage = MockStorage()
        let guard_ = ALLaunchGuard(storage: storage, crashThreshold: 3)
        guard_.survivalScheduler = immediateScheduler
        XCTAssertFalse(guard_.start())
        // 预支递增为 1 后，存活计时立即到期，计数被自动清零
        XCTAssertEqual(storage.consecutiveCrashCount, 0)
    }

    /// no-op 计时（进程在阈值时长内死亡）：计数保留，供下次启动裁决
    func testNoOpSchedulerKeepsCounterForNextLaunch() {
        let storage = MockStorage()
        let guard_ = ALLaunchGuard(storage: storage, crashThreshold: 3)
        guard_.survivalScheduler = noOpScheduler
        guard_.start()
        XCTAssertEqual(storage.consecutiveCrashCount, 1)
    }

    /// 上次已进入后台（系统回收/上滑强杀后台/后台 OOM）：下次启动不计为闪退
    func testBackgroundDeathNotCountedAsCrash() {
        let storage = MockStorage()
        storage.consecutiveCrashCount = 5
        storage.lastLaunchDiedInBackground = true
        let guard_ = ALLaunchGuard(storage: storage, crashThreshold: 3)
        guard_.survivalScheduler = noOpScheduler
        XCTAssertFalse(guard_.start())
        XCTAssertEqual(storage.consecutiveCrashCount, 1)   // 先清零再预支递增
        XCTAssertFalse(storage.lastLaunchDiedInBackground) // 标记被消费清除
    }

    /// 上次打点 uptime 大于本次 systemUptime（设备重启）：不计为闪退
    func testDeviceRebootNotCountedAsCrash() {
        let storage = MockStorage()
        storage.consecutiveCrashCount = 5
        // 打点值大于本次 systemUptime，说明期间发生过设备重启
        storage.lastLaunchMarkUptime = ProcessInfo.processInfo.systemUptime + 1000
        let guard_ = ALLaunchGuard(storage: storage, crashThreshold: 3)
        guard_.survivalScheduler = noOpScheduler
        XCTAssertFalse(guard_.start())
        XCTAssertEqual(storage.consecutiveCrashCount, 1)   // 先清零再预支递增
        XCTAssertFalse(guard_.isInSafeMode)
    }

    /// 安全模式启动防绕过：不递增计数、不启动存活计时（即使计时立即到期）
    func testSafeModeLaunchDoesNotIncrementOrStartSurvivalTimer() {
        let storage = MockStorage()
        storage.consecutiveCrashCount = 3
        storage.safeModeActive = true
        let guard_ = ALLaunchGuard(storage: storage, crashThreshold: 3)
        guard_.survivalScheduler = immediateScheduler   // 若误启动计时，计数将被清零
        XCTAssertTrue(guard_.start())
        XCTAssertTrue(guard_.isInSafeMode)
        XCTAssertEqual(storage.consecutiveCrashCount, 3)  // 计数保持阈值

        // 模拟杀进程重启后：仍处于安全模式（无法绕过）
        let relaunch = ALLaunchGuard(storage: storage, crashThreshold: 3)
        relaunch.survivalScheduler = immediateScheduler
        XCTAssertTrue(relaunch.start())
        XCTAssertEqual(storage.consecutiveCrashCount, 3)
    }

    /// 挂起计时不误清新会话（跨会话竞态，会话代际标记防护）
    func testStaleSurvivalClosureDoesNotClearNewSessionCount() {
        let storage = MockStorage()
        // 旧会话：存活确认闭包被挂起未执行
        var staleWork: (() -> Void)?
        let oldGuard = ALLaunchGuard(storage: storage, crashThreshold: 3)
        oldGuard.survivalScheduler = { work in staleWork = work }
        oldGuard.start()   // count = 1
        XCTAssertEqual(storage.consecutiveCrashCount, 1)

        // 新会话开始（模拟新进程启动，共享同一存储）
        let newGuard = ALLaunchGuard(storage: storage, crashThreshold: 3)
        newGuard.survivalScheduler = noOpScheduler
        newGuard.start()   // count = 2
        XCTAssertEqual(storage.consecutiveCrashCount, 2)

        // 旧会话的计时闭包此刻才触发（竞态）：不得清除新会话计数
        staleWork?()
        XCTAssertEqual(storage.consecutiveCrashCount, 2)
    }

    /// shouldEnterSafeMode：极早期纯读查询，无副作用
    func testShouldEnterSafeModeIsSideEffectFree() {
        let storage = MockStorage()
        storage.safeModeActive = true
        storage.consecutiveCrashCount = 7
        let guard_ = ALLaunchGuard(storage: storage, crashThreshold: 3)
        XCTAssertTrue(guard_.shouldEnterSafeMode)
        XCTAssertFalse(guard_.isInSafeMode)   // 查询不激活
        // 存储状态未被改变
        XCTAssertTrue(storage.safeModeActive)
        XCTAssertEqual(storage.consecutiveCrashCount, 7)

        // 计数达阈值路径（无粘滞标记）
        let storage2 = MockStorage()
        storage2.consecutiveCrashCount = 3
        XCTAssertTrue(ALLaunchGuard(storage: storage2, crashThreshold: 3).shouldEnterSafeMode)

        // 未达阈值路径
        let storage3 = MockStorage()
        storage3.consecutiveCrashCount = 2
        XCTAssertFalse(ALLaunchGuard(storage: storage3, crashThreshold: 3).shouldEnterSafeMode)
    }

    /// markLaunchSuccessful 与自动清零幂等共存（内部走同一确认函数）
    func testMarkLaunchSuccessfulAndAutoClearAreIdempotent() {
        let storage = MockStorage()
        let guard_ = ALLaunchGuard(storage: storage, crashThreshold: 3)
        var pendingWork: (() -> Void)?
        guard_.survivalScheduler = { work in pendingWork = work }
        guard_.start()   // count = 1
        XCTAssertEqual(storage.consecutiveCrashCount, 1)

        guard_.markLaunchSuccessful()   // 宿主提前确认
        XCTAssertEqual(storage.consecutiveCrashCount, 0)

        pendingWork?()   // 计时随后到期：幂等，保持清零
        XCTAssertEqual(storage.consecutiveCrashCount, 0)
        pendingWork?()   // 多次触发同样幂等
        XCTAssertEqual(storage.consecutiveCrashCount, 0)
        XCTAssertFalse(storage.lastLaunchDiedInBackground)
    }

    /// 进入后台后进程仍正常存活：确认函数同时清零计数与后台标记（无双计）
    func testSurvivalConfirmationAlsoClearsBackgroundFlag() {
        let storage = MockStorage()
        let guard_ = ALLaunchGuard(storage: storage, crashThreshold: 3)
        guard_.survivalScheduler = noOpScheduler
        guard_.start()
        guard_.handleDidEnterBackground()   // 进入后台，持久化标记
        XCTAssertTrue(storage.lastLaunchDiedInBackground)
        guard_.markLaunchSuccessful()   // 存活确认（提前入口）
        XCTAssertFalse(storage.lastLaunchDiedInBackground)   // 标记同步清除
        XCTAssertEqual(storage.consecutiveCrashCount, 0)
    }

    /// reset()：清零计数 + 清除粘滞标记 + 退出回调；下次启动恢复正常流程
    func testResetClearsStickySafeModeFlag() {
        let storage = MockStorage()
        storage.consecutiveCrashCount = 2
        let guard_ = ALLaunchGuard(storage: storage, crashThreshold: 3)
        let delegate = MockDelegate()
        guard_.delegate = delegate
        guard_.survivalScheduler = noOpScheduler
        XCTAssertTrue(guard_.start())
        XCTAssertTrue(storage.safeModeActive)

        guard_.reset()
        XCTAssertFalse(guard_.isInSafeMode)
        XCTAssertFalse(storage.safeModeActive)
        XCTAssertEqual(storage.consecutiveCrashCount, 0)
        XCTAssertEqual(delegate.exitCount, 1)

        // 下次启动恢复正常流程
        let next = ALLaunchGuard(storage: storage, crashThreshold: 3)
        next.survivalScheduler = noOpScheduler
        XCTAssertFalse(next.start())
        XCTAssertEqual(storage.consecutiveCrashCount, 1)
    }

    /// didEnterBackground 回调：持久化后台标记
    func testHandleDidEnterBackgroundSetsFlag() {
        let storage = MockStorage()
        let guard_ = ALLaunchGuard(storage: storage, crashThreshold: 3)
        guard_.handleDidEnterBackground()
        XCTAssertTrue(storage.lastLaunchDiedInBackground)
    }

    /// willTerminate 回调：兜底清零计数
    func testHandleWillTerminateClearsCounter() {
        let storage = MockStorage()
        storage.consecutiveCrashCount = 2
        let guard_ = ALLaunchGuard(storage: storage, crashThreshold: 3)
        guard_.handleWillTerminate()
        XCTAssertEqual(storage.consecutiveCrashCount, 0)
    }

    /// survivalTimeout 默认 5 秒
    func testSurvivalTimeoutDefaultValue() {
        XCTAssertEqual(ALLaunchGuard().survivalTimeout, 5)
    }

    /// DEBUG 强制入口：激活安全模式并持久化粘滞标记
    func testEnterSafeModeForTestingActivatesStickyMode() {
        #if DEBUG
        let storage = MockStorage()
        let guard_ = ALLaunchGuard(storage: storage, crashThreshold: 3)
        guard_.enterSafeModeForTesting()
        XCTAssertTrue(guard_.isInSafeMode)
        XCTAssertTrue(storage.safeModeActive)

        // 下次启动直接安全模式且计数不递增
        let next = ALLaunchGuard(storage: storage, crashThreshold: 3)
        next.survivalScheduler = noOpScheduler
        XCTAssertTrue(next.start())
        XCTAssertEqual(storage.consecutiveCrashCount, 0)
        #endif
    }

    // MARK: 安全模式最小启动任务（tasks 1.1，spec: crash-detection ADDED）

    /// 阈值触发：两个任务按注册顺序各执行一次，且先于 delegate 进入回调
    func testSafeModeLaunchTasksRunInOrderBeforeDelegateOnThreshold() {
        let storage = MockStorage()
        storage.consecutiveCrashCount = 2   // start() 后达阈值 3
        let guard_ = ALLaunchGuard(storage: storage, crashThreshold: 3)
        var config = ALLaunchGuardConfig()
        config.autoPresent = false
        guard_.uiConfig = config

        // 任务与 delegate 回调写入同一顺序数组
        var order: [String] = []
        guard_.safeModeLaunchTasks = [
            { order.append("task1") },
            { order.append("task2") },
        ]
        let delegate = MockDelegate()
        delegate.onEnterSafeMode = { order.append("delegate") }
        guard_.delegate = delegate

        XCTAssertTrue(guard_.start())
        XCTAssertEqual(order, ["task1", "task2", "delegate"])
        XCTAssertTrue(delegate.enteredSafeMode)
    }

    /// 粘滞路径：storage.safeModeActive = true 后 start() 激活，任务执行一次
    func testSafeModeLaunchTasksRunOnStickyPath() {
        let storage = MockStorage()
        storage.safeModeActive = true
        let guard_ = ALLaunchGuard(storage: storage, crashThreshold: 3)
        var config = ALLaunchGuardConfig()
        config.autoPresent = false
        guard_.uiConfig = config

        var runCount = 0
        guard_.safeModeLaunchTasks = [{ runCount += 1 }]
        guard_.delegate = MockDelegate()

        XCTAssertTrue(guard_.start())
        XCTAssertEqual(runCount, 1)

        // 模拟杀进程重启（新实例共享存储，每进程一次语义）：再次执行一次
        let relaunch = ALLaunchGuard(storage: storage, crashThreshold: 3)
        var relaunchCount = 0
        relaunch.safeModeLaunchTasks = [{ relaunchCount += 1 }]
        XCTAssertTrue(relaunch.start())
        XCTAssertEqual(relaunchCount, 1)
    }

    /// DEBUG 直入路径：enterSafeModeForTesting 激活时任务同样执行
    func testSafeModeLaunchTasksRunOnDebugEntryPath() {
        #if DEBUG
        let storage = MockStorage()
        let guard_ = ALLaunchGuard(storage: storage, crashThreshold: 3)
        var config = ALLaunchGuardConfig()
        config.autoPresent = false
        guard_.uiConfig = config

        var runCount = 0
        guard_.safeModeLaunchTasks = [{ runCount += 1 }]

        guard_.enterSafeModeForTesting()
        XCTAssertEqual(runCount, 1)
        #endif
    }

    /// 同进程二次激活不重复执行（每进程一次幂等，design D2）
    func testSafeModeLaunchTasksRunOnlyOncePerProcess() {
        #if DEBUG
        let storage = MockStorage()
        storage.consecutiveCrashCount = 2   // start() 阈值触发
        let guard_ = ALLaunchGuard(storage: storage, crashThreshold: 3)
        var config = ALLaunchGuardConfig()
        config.autoPresent = false
        guard_.uiConfig = config

        var runCount = 0
        guard_.safeModeLaunchTasks = [{ runCount += 1 }]

        guard_.start()                          // 第一次激活：执行
        guard_.enterSafeModeForTesting()        // 同进程叠加第二次激活
        XCTAssertEqual(runCount, 1)
        #endif
    }

    /// 未注册无副作用：默认空数组时行为与未引入本需求一致
    func testSafeModeLaunchTasksEmptyByDefaultHasNoSideEffect() {
        let storage = MockStorage()
        storage.consecutiveCrashCount = 2
        let guard_ = ALLaunchGuard(storage: storage, crashThreshold: 3)
        var config = ALLaunchGuardConfig()
        config.autoPresent = false
        guard_.uiConfig = config
        let delegate = MockDelegate()
        guard_.delegate = delegate

        XCTAssertTrue(guard_.safeModeLaunchTasks.isEmpty)
        XCTAssertTrue(guard_.start())
        XCTAssertTrue(guard_.isInSafeMode)
        XCTAssertTrue(delegate.enteredSafeMode)   // 既有行为不变
        XCTAssertEqual(storage.consecutiveCrashCount, 3)
    }

    // MARK: 并发安全（harden-thread-safety tasks 1.1，spec: crash-detection ADDED）

    /// hammer：8 路并发读 shouldEnterSafeMode/isInSafeMode，同时主线程串行
    /// start/reset 写路径（独立实例 + 独立 MockStorage）——读路径不崩不死锁。
    /// XCTestExpectation 超时保护：若锁引入死锁，等待超期即测试失败。
    func testConcurrentReadsDuringStartResetDoNotCrashOrDeadlock() {
        let hammerExpectation = expectation(description: "并发读路径 hammer 完成")
        hammerExpectation.expectedFulfillmentCount = 8

        // 读侧：共享单例（UserDefaults 后端），任意线程读路径
        let shared = ALLaunchGuard.shared
        DispatchQueue.concurrentPerform(iterations: 8) { _ in
            for _ in 0..<2000 {
                _ = shared.shouldEnterSafeMode
                _ = shared.isInSafeMode
            }
            hammerExpectation.fulfill()
        }

        // 写侧：主线程串行循环 start/reset（独立实例 + 独立 MockStorage，
        // 不触碰共享存储；与上方读线程并发执行）
        for _ in 0..<20 {
            let storage = MockStorage()
            storage.consecutiveCrashCount = 2   // start() 后达阈值触发安全模式
            let guard_ = ALLaunchGuard(storage: storage, crashThreshold: 3)
            guard_.survivalScheduler = noOpScheduler
            guard_.start()
            guard_.reset()
        }

        wait(for: [hammerExpectation], timeout: 30)
    }

    /// 写序崩溃原子性推演（design D2）：模拟预支写入中途进程终止的残留态
    /// ——后台标记已清、本次打点已写、计数未写——次启裁决不得误清旧计数，
    /// 本次启动正常预支递增（2 → 3），偏向多计而非漏检。
    func testPartialWriteResidualStateIsNotMisCleared() {
        let storage = MockStorage()
        storage.lastLaunchDiedInBackground = false             // 标记已清（第一步已写）
        storage.lastLaunchMarkUptime = 123                     // 打点已写（第二步已写，小于当前 uptime 非设备重启）
        storage.consecutiveCrashCount = 2                      // 计数未写（进程在此前终止）
        let guard_ = ALLaunchGuard(storage: storage, crashThreshold: 5)
        guard_.survivalScheduler = noOpScheduler
        XCTAssertFalse(guard_.start())
        XCTAssertEqual(storage.consecutiveCrashCount, 3)       // 未被误清：旧值 + 1
    }

    /// 死锁回归：阈值触发路径下 delegate 进入回调内回读 shouldEnterSafeMode /
    /// isInSafeMode（回调在锁外执行，加锁后不得重入死锁）。
    func testDelegateReadingShouldEnterSafeModeInsideCallbackDoesNotDeadlock() {
        let storage = MockStorage()
        storage.consecutiveCrashCount = 2   // start() 后达阈值触发
        let guard_ = ALLaunchGuard(storage: storage, crashThreshold: 3)
        let delegate = MockDelegate()
        var readsInCallback: (shouldEnter: Bool, isInSafeMode: Bool)?
        delegate.onEnterSafeMode = {
            readsInCallback = (guard_.shouldEnterSafeMode, guard_.isInSafeMode)
        }
        guard_.delegate = delegate

        // 若误在锁内触发回调，此处即死锁挂起——测试超时报错即暴露回归
        XCTAssertTrue(guard_.start())
        XCTAssertEqual(readsInCallback?.shouldEnter, true)
        XCTAssertEqual(readsInCallback?.isInSafeMode, true)
    }
}
