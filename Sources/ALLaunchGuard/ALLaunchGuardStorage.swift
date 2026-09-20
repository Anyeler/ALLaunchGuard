import Foundation

/// Protocol for persisting the consecutive-crash counter.
public protocol ALLaunchGuardStorage: AnyObject {
    /// The number of consecutive launches that ended in a crash.
    var consecutiveCrashCount: Int { get set }

    /// 上次启动写入的单调时钟打点（systemUptime）。
    /// 用于下次启动时检测设备重启（打点值大于本次 uptime 说明发生过重启）。
    var lastLaunchMarkUptime: TimeInterval? { get set }

    /// 上次会话是否已进入后台（系统回收 / 上滑强杀后台 / 后台 OOM 等不计为闪退）。
    var lastLaunchDiedInBackground: Bool { get set }

    /// 安全模式粘滞标记：激活后跨启动保留，仅 `reset()` 可清除。
    var safeModeActive: Bool { get set }
}

/// Default `UserDefaults`-backed implementation of `ALLaunchGuardStorage`.
public final class UserDefaultsLaunchGuardStorage: ALLaunchGuardStorage {

    private let countKey = "ALLaunchGuard.consecutiveCrashCount"
    private let markUptimeKey = "ALLaunchGuard.lastLaunchMarkUptime"
    private let diedInBackgroundKey = "ALLaunchGuard.lastLaunchDiedInBackground"
    private let safeModeActiveKey = "ALLaunchGuard.safeModeActive"
    private let defaults: UserDefaults

    /// Creates a storage instance.
    /// - Parameter defaults: The `UserDefaults` suite to use. Defaults to `.standard`.
    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var consecutiveCrashCount: Int {
        get { defaults.integer(forKey: countKey) }
        set { defaults.set(newValue, forKey: countKey) }
    }

    public var lastLaunchMarkUptime: TimeInterval? {
        // 用 object(forKey:) 判断 key 存在性：
        // double(forKey:) 对缺失 key 会返回 0，无法区分“无记录”与“打点为 0”。
        get {
            guard defaults.object(forKey: markUptimeKey) != nil else { return nil }
            return defaults.double(forKey: markUptimeKey)
        }
        set {
            if let value = newValue {
                defaults.set(value, forKey: markUptimeKey)
            } else {
                defaults.removeObject(forKey: markUptimeKey)
            }
        }
    }

    public var lastLaunchDiedInBackground: Bool {
        get { defaults.bool(forKey: diedInBackgroundKey) }
        set { defaults.set(newValue, forKey: diedInBackgroundKey) }
    }

    public var safeModeActive: Bool {
        get { defaults.bool(forKey: safeModeActiveKey) }
        set { defaults.set(newValue, forKey: safeModeActiveKey) }
    }
}
