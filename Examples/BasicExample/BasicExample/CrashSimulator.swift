#if DEBUG
import Foundation

/// 连续启动闪退模拟器（仅 DEBUG，spec: example-apps MODIFIED / design D3）：
/// 配合首页开关演示"连续闪退 → 安全模式接管"完整链路。
///
/// 库为预支递增计数：达到闪退阈值的那次启动 `start()` 直接返回 true
/// 进入安全模式，不会消耗 remaining——默认阈值 3 时演示为"前两次启动
/// 自动崩溃、第三次启动进入安全模式"。因此 AppDelegate 在安全模式路径
/// 调用 `disarm()` 清零（进入安全模式即结束演示，避免 remaining 残留
/// 导致修复重启后再多崩一次）；行为与 arm 值、阈值解耦，任意阈值下一致。
///
/// 用法：首页开关开启 → `arm()` 置剩余自动崩溃次数为 3；AppDelegate 在
/// 正常启动路径（`ALLaunchGuard.start()` 返回 false）调用
/// `scheduleAutoCrashIfEnabled()`——剩余次数 > 0 时先递减持久化，再在
/// 约 1 秒后（5 秒存活窗口内）fatalError 崩溃。
final class BasicExampleCrashSimulator {

    /// 剩余自动崩溃次数的 UserDefaults key（冒烟可用 simctl spawn defaults 注入）
    private static let remainingKey = "BasicExample.autoCrashRemaining"

    /// 单例：首页与 AppDelegate 共享同一份持久化状态
    static let shared = BasicExampleCrashSimulator()

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: - 状态查询

    /// 剩余自动崩溃次数（持久化读取，无记录时为 0）
    var remainingAutoCrashes: Int {
        defaults.integer(forKey: Self.remainingKey)
    }

    /// 演示是否已开启（首页开关状态绑定：remaining > 0）
    var isArmed: Bool {
        remainingAutoCrashes > 0
    }

    // MARK: - 操作

    /// 开启演示：置剩余自动崩溃次数为 3（演示默认值；达到阈值即进入
    /// 安全模式并自动清零，见 AppDelegate 安全模式分支的 disarm()）
    func arm() {
        defaults.set(3, forKey: Self.remainingKey)
    }

    /// 关闭演示：清零剩余次数
    func disarm() {
        defaults.set(0, forKey: Self.remainingKey)
    }

    /// 演示自然结束后归零兜底（进入安全模式时 AppDelegate 已调 disarm()
    /// 清零，remaining 用尽的场景下本方法保证语义完整）
    func disarmIfFinished() {
        if remainingAutoCrashes <= 0 {
            defaults.set(0, forKey: Self.remainingKey)
        }
    }

    // MARK: - 启动调度（design D4：仅正常启动路径调用）

    /// 启动时调度自动崩溃：剩余 > 0 → 先递减持久化 → 约 1 秒后 fatalError。
    ///
    /// 注意：必须在 `ALLaunchGuard.start()` 返回 false（正常启动）后调用；
    /// 安全模式启动不打点不计时，调度崩溃无意义且会干扰修复流程。
    /// 递减必须先行持久化——fatalError 无 unwind，进程即刻终止。
    /// 1 秒延迟保证崩溃发生在 5 秒存活窗口内（计数保留）且首页 UI 可见。
    func scheduleAutoCrashIfEnabled() {
        let remaining = remainingAutoCrashes
        guard remaining > 0 else { return }

        let next = remaining - 1
        defaults.set(next, forKey: Self.remainingKey)

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            fatalError("💥 Simulated auto launch crash (remaining \(next) after this; BasicExample DEBUG demo)")
        }
    }
}
#endif
