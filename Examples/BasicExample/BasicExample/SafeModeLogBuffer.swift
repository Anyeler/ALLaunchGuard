import Foundation

/// 安全模式最小启动任务演示：纯 Foundation 内存级模拟日志模块。
///
/// 作为 `safeModeLaunchTasks` 的任务目标（见 AppDelegate 步骤 2），
/// 演示最小任务约束四要点：
/// 1. **自包含**：不依赖宿主正常启动图中的任何模块——安全模式下
///    正常启动图被整体跳过（`start()` 返回 true 后直接 return）；
/// 2. **轻量同步**：在安全模式首帧前于主线程同步执行，只做内存操作，
///    重量级初始化会拖慢修复页呈现；
/// 3. **无磁盘 IO**：本模块仅维护内存缓冲，不落盘（AppDelegate 中
///    追加的一次性演示标记写入属示例豁免，生产最小任务不得效仿）；
/// 4. **不触碰编排器**：不访问任何启动编排器的内部状态。
///
/// 与 MPLaunchExample 的桥接形态对照：那里的任务闭包经
/// `MainActor.assumeIsolated` 桥接 `LaunchSession.runSafeModeTasks`
/// （编排器以最小集拓扑执行模块同步任务）；本通用示例无编排器依赖，
/// 纯 Foundation 直调。
///
/// 注意：本类是宿主侧演示代码——库只负责按注册顺序同步执行闭包，
/// 不理解也不感知闭包内部内容。
final class DemoSafeModeLogger {

    /// 单例：两个任务闭包共享同一份内存缓冲
    static let shared = DemoSafeModeLogger()

    /// 内存日志缓冲（仅内存，不落盘）
    private(set) var buffer: [String] = []

    /// 幂等初始化标记：每个进程生命周期仅初始化一次
    private var bootstrapped = false

    private init() {}

    /// 任务 1：幂等初始化内存日志缓冲（重复调用无副作用）
    static func bootstrap() {
        guard !shared.bootstrapped else { return }
        shared.bootstrapped = true
        print("🛡️ [SafeModeTask 1/2] 内存日志缓冲已初始化")
    }

    /// 任务 2：记录一条安全模式事件到内存缓冲（依赖任务 1 先行）
    static func log(_ message: String) {
        shared.buffer.append(message)
        print("🛡️ [SafeModeTask 2/2] \(message)（缓冲条目数：\(shared.buffer.count)）")
    }
}
