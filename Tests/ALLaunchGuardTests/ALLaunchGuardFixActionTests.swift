import XCTest
@testable import ALLaunchGuard

// MARK: - 可控 mock 动作

/// 可控修复动作：预设成败结果、记录 perform 调用次数；
/// 故意不实现 isDestructive——顺带验证协议扩展默认值 false。
final class MockFixAction: ALLaunchGuardFixAction {
    let title: String = "Mock 修复动作"
    let iconSystemName: String? = "wrench"
    var result: Bool = true
    private(set) var performCount = 0

    func perform(completion: @escaping (Bool) -> Void) {
        performCount += 1
        completion(result)
    }
}

// MARK: - 仅实现既有回调的委托（验证新回调默认实现的向后兼容）

final class LegacyDelegate: ALLaunchGuardDelegate {
    var enteredSafeMode = false

    func launchGuardDidEnterSafeMode(_ guard: ALLaunchGuard) {
        enteredSafeMode = true
    }
}

// MARK: - Tests

final class ALLaunchGuardFixActionTests: XCTestCase {

    // MARK: 测试辅助

    /// 构造一个已处于安全模式的 guard（计数=3、粘滞标记已持久化、委托已挂接）
    private func makeGuardInSafeMode(
        storage: MockStorage,
        delegate: MockDelegate
    ) -> ALLaunchGuard {
        storage.consecutiveCrashCount = 2   // start() 预支递增后达到阈值 3
        let guard_ = ALLaunchGuard(storage: storage, crashThreshold: 3)
        guard_.delegate = delegate
        guard_.survivalScheduler = noOpScheduler
        XCTAssertTrue(guard_.start())
        XCTAssertTrue(guard_.isInSafeMode)
        XCTAssertTrue(storage.safeModeActive)
        return guard_
    }

    /// 构造含文件与子目录（子目录内再含文件）的临时目录，模拟 Caches
    private func makePopulatedCacheDirectory() throws -> URL {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("ALLaunchGuardTests-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("dummy".utf8).write(to: root.appendingPathComponent("cache.db"))

        let subdir = root.appendingPathComponent("subdir", isDirectory: true)
        try fileManager.createDirectory(at: subdir, withIntermediateDirectories: true)
        try Data("nested".utf8).write(to: subdir.appendingPathComponent("nested.log"))
        return root
    }

    // MARK: 注册（spec: 修复动作注册）

    /// fixActions 默认空数组；赋值保序（注册顺序 = 菜单展示顺序）
    func testFixActionsDefaultsToEmptyAndPreservesOrder() {
        let guard_ = ALLaunchGuard(storage: MockStorage(), crashThreshold: 3)
        XCTAssertTrue(guard_.fixActions.isEmpty)

        let first = MockFixAction()
        let second = ALLaunchGuardClearCacheAction()
        let third = ALLaunchGuardClosureAction(title: "第三项") { _ in }
        guard_.fixActions = [first, second, third]

        XCTAssertEqual(guard_.fixActions.count, 3)
        XCTAssertTrue(guard_.fixActions[0] === first)
        XCTAssertTrue(guard_.fixActions[1] === second)
        XCTAssertTrue(guard_.fixActions[2] === third)
    }

    // MARK: 动作元数据与协议默认值（spec: 修复动作协议契约）

    /// 自定义动作元数据完整可读；ClosureAction 默认 iconSystemName 为 nil
    func testActionMetadataReadable() {
        let action: ALLaunchGuardFixAction = ALLaunchGuardClosureAction(
            title: "重置广告标识",
            iconSystemName: "arrow.counterclockwise",
            isDestructive: false
        ) { _ in }
        XCTAssertEqual(action.title, "重置广告标识")
        XCTAssertEqual(action.iconSystemName, "arrow.counterclockwise")
        XCTAssertFalse(action.isDestructive)

        XCTAssertNil(ALLaunchGuardClosureAction(title: "无图标") { _ in }.iconSystemName)
    }

    /// 未实现 isDestructive 的动作读取协议扩展默认值 false；显式指定时透传
    func testIsDestructiveDefaultsToFalseAndPassesThrough() {
        XCTAssertFalse((MockFixAction() as ALLaunchGuardFixAction).isDestructive)
        XCTAssertFalse((ALLaunchGuardClearCacheAction() as ALLaunchGuardFixAction).isDestructive)

        XCTAssertTrue(
            ALLaunchGuardClosureAction(title: "抹掉数据", isDestructive: true) { _ in }.isDestructive
        )
        XCTAssertFalse(
            ALLaunchGuardClosureAction(title: "普通动作") { _ in }.isDestructive
        )
    }

    /// 内置清缓存动作默认元数据：中文标题 + trash 图标
    func testClearCacheActionDefaultMetadata() {
        let action = ALLaunchGuardClearCacheAction()
        XCTAssertEqual(action.title, "清理缓存")
        XCTAssertEqual(action.iconSystemName, "trash")
        XCTAssertFalse(action.isDestructive)
    }

    // MARK: 执行编排（spec: 执行编排与安全模式退出）

    /// 首个成功动作退出安全模式：状态清零、exit 回调一次、didFinish(success: true)
    func testPerformSuccessActionExitsSafeMode() {
        let storage = MockStorage()
        let delegate = MockDelegate()
        let guard_ = makeGuardInSafeMode(storage: storage, delegate: delegate)

        let action = MockFixAction()
        action.result = true
        let exp = expectation(description: "fix action completion")
        var completionSuccess: Bool?
        guard_.perform(action) { success in
            completionSuccess = success
            exp.fulfill()
        }
        wait(for: [exp], timeout: 2)

        XCTAssertEqual(action.performCount, 1)
        XCTAssertEqual(completionSuccess, true)
        XCTAssertFalse(guard_.isInSafeMode)                // 安全模式退出
        XCTAssertEqual(storage.consecutiveCrashCount, 0)   // 计数清零
        XCTAssertFalse(storage.safeModeActive)             // 粘滞标记清除
        XCTAssertEqual(delegate.exitCount, 1)              // 退出回调恰好一次
        XCTAssertEqual(delegate.finishCount, 1)
        XCTAssertEqual(delegate.lastFinishSuccess, true)
        XCTAssertTrue(delegate.finishedActions[0].action === action)
    }

    /// 失败动作不退出安全模式：状态不变、无 exit 回调、didFinish(success: false)，可重试
    func testPerformFailureKeepsSafeModeAndAllowsRetry() {
        let storage = MockStorage()
        let delegate = MockDelegate()
        let guard_ = makeGuardInSafeMode(storage: storage, delegate: delegate)

        let action = MockFixAction()
        action.result = false
        let exp = expectation(description: "fix action failure completion")
        var completionSuccess: Bool?
        guard_.perform(action) { success in
            completionSuccess = success
            exp.fulfill()
        }
        wait(for: [exp], timeout: 2)

        XCTAssertEqual(completionSuccess, false)
        XCTAssertTrue(guard_.isInSafeMode)                 // 安全模式保持激活
        XCTAssertEqual(storage.consecutiveCrashCount, 3)   // 计数不变
        XCTAssertTrue(storage.safeModeActive)              // 粘滞标记不变
        XCTAssertEqual(delegate.exitCount, 0)              // 无退出回调
        XCTAssertEqual(delegate.finishCount, 1)
        XCTAssertEqual(delegate.lastFinishSuccess, false)

        // 同一动作失败后可重试：重试成功仍能退出安全模式
        action.result = true
        let retryExp = expectation(description: "retry completion")
        guard_.perform(action) { _ in retryExp.fulfill() }
        wait(for: [retryExp], timeout: 2)
        XCTAssertEqual(action.performCount, 2)
        XCTAssertFalse(guard_.isInSafeMode)
        XCTAssertEqual(delegate.exitCount, 1)
        XCTAssertEqual(delegate.finishCount, 2)
        XCTAssertEqual(delegate.lastFinishSuccess, true)
    }

    /// 多次成功动作幂等：exit 回调仅在曾处于安全模式时触发一次
    func testMultipleSuccessActionsTriggerExitOnlyOnce() {
        let storage = MockStorage()
        let delegate = MockDelegate()
        let guard_ = makeGuardInSafeMode(storage: storage, delegate: delegate)

        let first = MockFixAction()
        let second = MockFixAction()
        let exp1 = expectation(description: "first success")
        guard_.perform(first) { _ in exp1.fulfill() }
        wait(for: [exp1], timeout: 2)
        XCTAssertEqual(delegate.exitCount, 1)

        let exp2 = expectation(description: "second success")
        guard_.perform(second) { _ in exp2.fulfill() }
        wait(for: [exp2], timeout: 2)

        // 第二次成功：状态保持清零，exit 不再触发，didFinish 仍逐次通知
        XCTAssertFalse(guard_.isInSafeMode)
        XCTAssertEqual(storage.consecutiveCrashCount, 0)
        XCTAssertFalse(storage.safeModeActive)
        XCTAssertEqual(delegate.exitCount, 1)
        XCTAssertEqual(delegate.finishCount, 2)
        XCTAssertEqual(delegate.lastFinishSuccess, true)
    }

    /// 非安全模式下执行成功动作：reset 幂等、不触发 exit 回调
    func testPerformSuccessOutsideSafeModeDoesNotNotifyExit() {
        let storage = MockStorage()
        let delegate = MockDelegate()
        let guard_ = ALLaunchGuard(storage: storage, crashThreshold: 3)
        guard_.delegate = delegate
        guard_.survivalScheduler = noOpScheduler
        XCTAssertFalse(guard_.start())   // 正常启动，count = 1

        let exp = expectation(description: "completion outside safe mode")
        guard_.perform(MockFixAction()) { success in
            XCTAssertTrue(success)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 2)

        XCTAssertEqual(storage.consecutiveCrashCount, 0)
        XCTAssertEqual(delegate.exitCount, 0)
        XCTAssertEqual(delegate.finishCount, 1)
    }

    // MARK: 闭包包装动作（spec: 闭包包装动作）

    /// 闭包包装动作与自定义实现表现一致：completion 结果透传到编排层
    func testClosureActionPassesResultThroughOrchestration() {
        let storage = MockStorage()
        let delegate = MockDelegate()
        let guard_ = makeGuardInSafeMode(storage: storage, delegate: delegate)

        var executed = false
        let action = ALLaunchGuardClosureAction(title: "重建索引", iconSystemName: "doc.on.doc") { completion in
            executed = true
            completion(true)
        }
        let exp = expectation(description: "closure action completion")
        guard_.perform(action) { success in
            XCTAssertTrue(success)
            XCTAssertTrue(executed)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 2)

        XCTAssertFalse(guard_.isInSafeMode)
        XCTAssertEqual(delegate.exitCount, 1)
        XCTAssertTrue(delegate.finishedActions[0].action === action)
        XCTAssertEqual(delegate.lastFinishSuccess, true)
    }

    // MARK: 内置重置安全模式动作（fix-review-findings tasks 2.1/3.1，spec: safe-mode-ui MODIFIED）

    /// 内置重置动作默认元数据：中文标题 + arrow.counterclockwise 图标 + 破坏性标记
    func testResetSafeModeActionDefaultMetadata() {
        let action = ALLaunchGuardResetSafeModeAction()
        XCTAssertEqual(action.title, "重置安全模式")
        XCTAssertEqual(action.iconSystemName, "arrow.counterclockwise")
        XCTAssertTrue(action.isDestructive)

        // 构造参数可自定义标题与图标；破坏性标记恒定 true（语义固定）
        let custom = ALLaunchGuardResetSafeModeAction(
            title: "Exit Safe Mode", iconSystemName: "arrow.uturn.backward")
        XCTAssertEqual(custom.title, "Exit Safe Mode")
        XCTAssertEqual(custom.iconSystemName, "arrow.uturn.backward")
        XCTAssertTrue(custom.isDestructive)
    }

    /// 编排：重置动作成功触发 reset 退出安全模式 + 委托回调
    ///（空 fixActions 兜底出口的核心链路，tasks 3.1；
    /// perform 编排层既有回归见上方执行编排节）
    func testResetSafeModeActionOrchestrationExitsSafeMode() {
        let storage = MockStorage()
        let delegate = MockDelegate()
        let guard_ = makeGuardInSafeMode(storage: storage, delegate: delegate)

        let action = ALLaunchGuardResetSafeModeAction()
        let exp = expectation(description: "reset action completion")
        var completionSuccess: Bool?
        guard_.perform(action) { success in
            completionSuccess = success
            exp.fulfill()
        }
        wait(for: [exp], timeout: 2)

        XCTAssertEqual(completionSuccess, true)
        XCTAssertFalse(guard_.isInSafeMode)                // 安全模式退出（reset）
        XCTAssertEqual(storage.consecutiveCrashCount, 0)   // 计数清零
        XCTAssertFalse(storage.safeModeActive)             // 粘滞标记清除
        XCTAssertEqual(delegate.exitCount, 1)              // 退出回调恰好一次
        XCTAssertEqual(delegate.finishCount, 1)
        XCTAssertEqual(delegate.lastFinishSuccess, true)
        XCTAssertTrue(delegate.finishedActions[0].action === action)

        // 退出后下次启动恢复正常流程（不粘滞）
        let next = ALLaunchGuard(storage: storage, crashThreshold: 3)
        next.survivalScheduler = noOpScheduler
        XCTAssertFalse(next.start())
        XCTAssertEqual(storage.consecutiveCrashCount, 1)
    }

    /// 升级残留粘滞标记首启直接进入安全模式：宿主未注册任何动作时，
    /// 重置动作仍是有效退出出口（proposal 缺陷 ② 兜底场景）
    func testResetSafeModeActionExitsStickySafeModeFromLegacyResidue() {
        let storage = MockStorage()
        storage.safeModeActive = true   // 1.x 升级残留粘滞标记
        let delegate = MockDelegate()
        let guard_ = ALLaunchGuard(storage: storage, crashThreshold: 3)
        guard_.delegate = delegate
        XCTAssertTrue(guard_.fixActions.isEmpty)   // 宿主未注册任何动作
        XCTAssertTrue(guard_.start())              // 首启直接安全模式

        let exp = expectation(description: "reset exits sticky safe mode")
        guard_.perform(ALLaunchGuardResetSafeModeAction()) { success in
            XCTAssertTrue(success)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 2)

        XCTAssertFalse(guard_.isInSafeMode)
        XCTAssertFalse(storage.safeModeActive)
        XCTAssertEqual(delegate.exitCount, 1)
    }

    // MARK: 委托完成回调（spec: 委托完成回调）

    /// 既有委托实现者零改动：只实现进入回调也能编译，didFinish 走默认空实现
    func testLegacyDelegateUnaffectedByNewCallback() {
        let storage = MockStorage()
        storage.consecutiveCrashCount = 2
        let delegate = LegacyDelegate()
        let guard_ = ALLaunchGuard(storage: storage, crashThreshold: 3)
        guard_.delegate = delegate
        guard_.survivalScheduler = noOpScheduler
        XCTAssertTrue(guard_.start())
        XCTAssertTrue(delegate.enteredSafeMode)

        // 默认空实现：不崩溃，既有回调不受影响
        let exp = expectation(description: "legacy delegate completion")
        guard_.perform(MockFixAction()) { _ in exp.fulfill() }
        wait(for: [exp], timeout: 2)
        XCTAssertFalse(guard_.isInSafeMode)
    }

    // MARK: 内置清缓存动作（spec: 内置清缓存动作）

    /// 清理含内容的目录：内容清空（含子目录）、completion(true)、目录本身保留
    func testClearCacheActionClearsPopulatedDirectory() throws {
        let root = try makePopulatedCacheDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let action = ALLaunchGuardClearCacheAction(cachesDirectory: root)
        let exp = expectation(description: "clear populated directory")
        var result: Bool?
        action.perform { success in
            result = success
            exp.fulfill()
        }
        wait(for: [exp], timeout: 2)

        XCTAssertEqual(result, true)
        let fileManager = FileManager.default
        XCTAssertTrue(fileManager.fileExists(atPath: root.path))                    // 目录本身保留
        XCTAssertEqual(try fileManager.contentsOfDirectory(atPath: root.path).count, 0)  // 内容清空
    }

    /// 目录不存在：completion(true)，不报错
    func testClearCacheActionSucceedsWhenDirectoryMissing() {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("ALLaunchGuardTests-missing-\(UUID().uuidString)")
        let action = ALLaunchGuardClearCacheAction(cachesDirectory: missing)
        let exp = expectation(description: "missing directory")
        var result: Bool?
        action.perform { success in
            result = success
            exp.fulfill()
        }
        wait(for: [exp], timeout: 2)
        XCTAssertEqual(result, true)
    }

    /// 子项删除失败：completion(false)。
    /// 策略：目录设为只读（posixPermissions 0555）——有 r 权限可列举、缺 w 权限删除失败；
    /// 先探测当前进程环境下权限法是否有效（root 进程可无视权限），无效则如实跳过。
    func testClearCacheActionFailsWhenEntryDeletionFails() throws {
        let fileManager = FileManager.default
        let root = try makePopulatedCacheDirectory()
        defer {
            // 恢复权限便于清理临时目录
            try? fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: root.path)
            try? fileManager.removeItem(at: root)
        }

        try fileManager.setAttributes([.posixPermissions: 0o555], ofItemAtPath: root.path)

        // 权限法有效性探测：若删除居然成功（如以 root 运行），本环境无法构造失败路径
        do {
            try fileManager.removeItem(at: root.appendingPathComponent("cache.db"))
            throw XCTSkip("权限限制在当前进程无效（疑似 root 进程），无法构造子项删除失败场景")
        } catch let skip as XCTSkip {
            throw skip
        } catch {
            // 预期抛出权限错误 ⇒ 权限法有效，探测文件保留，进入正式断言
        }

        let action = ALLaunchGuardClearCacheAction(cachesDirectory: root)
        let exp = expectation(description: "clear readonly directory")
        var result: Bool?
        action.perform { success in
            result = success
            exp.fulfill()
        }
        wait(for: [exp], timeout: 2)
        XCTAssertEqual(result, false)
    }

    // MARK: 内置重启动作（spec: fix-actions ADDED——内置重启动作，design D1）

    /// 内置重启动作默认元数据：中文标题 + arrow.clockwise 图标 + 破坏性标记
    func testRestartActionDefaultMetadata() {
        let action = ALLaunchGuardRestartAction()
        XCTAssertEqual(action.title, "重启应用")
        XCTAssertEqual(action.iconSystemName, "arrow.clockwise")
        XCTAssertTrue(action.isDestructive)

        // 构造参数可自定义标题与图标；破坏性标记恒定 true（语义固定）
        let custom = ALLaunchGuardRestartAction(title: "Restart", iconSystemName: "arrow.triangle.2.circlepath")
        XCTAssertEqual(custom.title, "Restart")
        XCTAssertEqual(custom.iconSystemName, "arrow.triangle.2.circlepath")
        XCTAssertTrue(custom.isDestructive)
    }

    /// 经编排层执行重启动作（design D1 时序锚定）：
    /// reset 生效（粘滞标记清除 + 计数清零）先于 exitHandler 被调用；
    /// exitHandler 恰好一次。依赖主队列 FIFO——completion(true) 先行使
    /// 编排层 reset 先入队，exitHandler 晚一拍入队。
    func testRestartActionResetHappensBeforeExitHandlerViaOrchestration() {
        let storage = MockStorage()
        let delegate = MockDelegate()
        let guard_ = makeGuardInSafeMode(storage: storage, delegate: delegate)

        let action = ALLaunchGuardRestartAction()
        var order: [String] = []   // 两个记录点均在主队列执行，无竞争风险
        var exitCount = 0
        let exitExp = expectation(description: "exitHandler invoked")
        action.exitHandler = {
            exitCount += 1
            order.append("exitHandler")
            exitExp.fulfill()
        }

        let exp = expectation(description: "restart action orchestration")
        guard_.perform(action) { success in
            XCTAssertTrue(success)
            // 编排层 completion 在 reset() 之后回调：此刻粘滞标记应已清零
            XCTAssertFalse(storage.safeModeActive)
            XCTAssertEqual(storage.consecutiveCrashCount, 0)
            order.append("reset")
            exp.fulfill()
        }
        wait(for: [exp, exitExp], timeout: 2)

        XCTAssertEqual(order, ["reset", "exitHandler"])   // reset 生效先于进程终止
        XCTAssertEqual(exitCount, 1)                        // exitHandler 恰好一次
        XCTAssertFalse(guard_.isInSafeMode)
        XCTAssertEqual(delegate.exitCount, 1)
    }

    // MARK: 内置白名单缓存全清动作（spec: fix-actions ADDED——内置白名单缓存全清动作，design D2）

    /// 构造完整模拟沙盒结构：Documents/f1、Library/Caches/f2、Library/Preferences/f3、
    /// tmp/f4、SystemData/、.Trash/f5、游离文件 stray.txt、游离目录 strayDir/
    private func makeSandboxRoot() throws -> URL {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("ALLaunchGuardSandbox-\(UUID().uuidString)", isDirectory: true)
        func makeDir(_ relativePath: String) throws {
            try fileManager.createDirectory(
                at: root.appendingPathComponent(relativePath),
                withIntermediateDirectories: true)
        }
        func makeFile(_ relativePath: String) throws {
            try Data("dummy".utf8).write(to: root.appendingPathComponent(relativePath))
        }
        try makeDir("Documents");           try makeFile("Documents/f1.txt")
        try makeDir("Library/Caches");      try makeFile("Library/Caches/f2.cache")
        try makeDir("Library/Preferences"); try makeFile("Library/Preferences/f3.plist")
        try makeDir("tmp");                 try makeFile("tmp/f4.tmp")
        try makeDir("SystemData")
        try makeDir(".Trash");              try makeFile(".Trash/f5.trash")
        try makeFile("stray.txt")
        try makeDir("strayDir");            try makeFile("strayDir/inner.txt")
        return root
    }

    /// 内置全清动作默认元数据：中文标题 + trash.slash 图标 + 破坏性标记
    func testClearAllCacheActionDefaultMetadata() {
        let action = ALLaunchGuardClearAllCacheAction()
        XCTAssertEqual(action.title, "深度清理缓存")
        XCTAssertEqual(action.iconSystemName, "trash.slash")
        XCTAssertTrue(action.isDestructive)
    }

    /// 默认白名单保护（spec 场景）：Documents、SystemData 与 Library 中 Caches
    /// 之外的内容保留；tmp 内容、.Trash、游离顶层项与 Library/Caches 内容被清空
    func testClearAllCacheActionDefaultWhitelistClearsAndProtects() throws {
        let fileManager = FileManager.default
        let root = try makeSandboxRoot()
        defer { try? fileManager.removeItem(at: root) }

        let action = ALLaunchGuardClearAllCacheAction(sandboxRoot: root)
        let exp = expectation(description: "clear all cache")
        var result: Bool?
        action.perform { success in
            result = success
            exp.fulfill()
        }
        wait(for: [exp], timeout: 5)
        XCTAssertEqual(result, true)

        // 保护项保留
        XCTAssertTrue(fileManager.fileExists(atPath: root.appendingPathComponent("Documents/f1.txt").path))
        var isDirectory = ObjCBool(false)
        XCTAssertTrue(fileManager.fileExists(atPath: root.appendingPathComponent("SystemData").path, isDirectory: &isDirectory))
        XCTAssertTrue(isDirectory.boolValue)
        XCTAssertTrue(fileManager.fileExists(atPath: root.appendingPathComponent("Library/Preferences/f3.plist").path))

        // 清理项清空（目录本身保留）
        XCTAssertEqual(
            try fileManager.contentsOfDirectory(atPath: root.appendingPathComponent("Library/Caches").path).count, 0)
        XCTAssertEqual(
            try fileManager.contentsOfDirectory(atPath: root.appendingPathComponent("tmp").path).count, 0)
        XCTAssertEqual(
            try fileManager.contentsOfDirectory(atPath: root.appendingPathComponent(".Trash").path).count, 0)

        // 游离项整个删除
        XCTAssertFalse(fileManager.fileExists(atPath: root.appendingPathComponent("stray.txt").path))
        XCTAssertFalse(fileManager.fileExists(atPath: root.appendingPathComponent("strayDir").path))
    }

    /// 自定义 protectedTopLevelItems：宿主自建顶层目录加入保护名单后被保留
    func testClearAllCacheActionCustomProtectedItemsPreserved() throws {
        let fileManager = FileManager.default
        let root = try makeSandboxRoot()
        defer { try? fileManager.removeItem(at: root) }

        let action = ALLaunchGuardClearAllCacheAction(
            sandboxRoot: root,
            protectedTopLevelItems: ["Documents", "Library", "SystemData", "strayDir"])
        let exp = expectation(description: "custom protected items")
        var result: Bool?
        action.perform { success in
            result = success
            exp.fulfill()
        }
        wait(for: [exp], timeout: 5)
        XCTAssertEqual(result, true)

        // 自定义保护目录保留（含内容）；名单外游离文件仍被删除
        XCTAssertTrue(fileManager.fileExists(atPath: root.appendingPathComponent("strayDir/inner.txt").path))
        XCTAssertFalse(fileManager.fileExists(atPath: root.appendingPathComponent("stray.txt").path))
    }

    /// 沙盒根目录缺失：幂等成功（completion(true)）
    func testClearAllCacheActionSucceedsWhenSandboxRootMissing() {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("ALLaunchGuardSandbox-missing-\(UUID().uuidString)")
        let action = ALLaunchGuardClearAllCacheAction(sandboxRoot: missing)
        let exp = expectation(description: "missing sandbox root")
        var result: Bool?
        action.perform { success in
            result = success
            exp.fulfill()
        }
        wait(for: [exp], timeout: 5)
        XCTAssertEqual(result, true)
    }

    /// 单项删除失败：继续清理其余项，最终聚合 completion(false)（可重试）。
    /// 策略：游离目录 strayDir 设为只读（0o555）——removeItem 递归删除其
    /// 内容时因缺 w 权限失败；先探测权限法在当前进程环境下是否有效。
    func testClearAllCacheActionContinuesOnSingleItemFailureAndAggregatesFalse() throws {
        let fileManager = FileManager.default
        let root = try makeSandboxRoot()
        let strayDir = root.appendingPathComponent("strayDir")
        defer {
            // 恢复权限便于清理临时目录
            try? fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: strayDir.path)
            try? fileManager.removeItem(at: root)
        }

        try fileManager.setAttributes([.posixPermissions: 0o555], ofItemAtPath: strayDir.path)

        // 权限法有效性探测：若删除居然成功（如以 root 运行），本环境无法构造失败路径
        do {
            try fileManager.removeItem(at: strayDir)
            throw XCTSkip("权限限制在当前进程无效（疑似 root 进程），无法构造单项删除失败场景")
        } catch let skip as XCTSkip {
            throw skip
        } catch {
            // 预期抛出权限错误 ⇒ 权限法有效，进入正式断言
        }

        let action = ALLaunchGuardClearAllCacheAction(sandboxRoot: root)
        let exp = expectation(description: "single item failure aggregation")
        var result: Bool?
        action.perform { success in
            result = success
            exp.fulfill()
        }
        wait(for: [exp], timeout: 5)

        XCTAssertEqual(result, false)   // 聚合失败（用户可重试）
        // 其余项不受单项失败影响，继续清理完成
        XCTAssertEqual(
            try fileManager.contentsOfDirectory(atPath: root.appendingPathComponent("tmp").path).count, 0)
        XCTAssertEqual(
            try fileManager.contentsOfDirectory(atPath: root.appendingPathComponent(".Trash").path).count, 0)
        XCTAssertEqual(
            try fileManager.contentsOfDirectory(atPath: root.appendingPathComponent("Library/Caches").path).count, 0)
        XCTAssertFalse(fileManager.fileExists(atPath: root.appendingPathComponent("stray.txt").path))
        // 保护项仍保留
        XCTAssertTrue(fileManager.fileExists(atPath: root.appendingPathComponent("Documents/f1.txt").path))
    }
}
