import UIKit
import ALLaunchGuard

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        // ── ALLaunchGuard 门控范式（didFinishLaunching 首行）──
        //
        // 1. 注册修复动作：必须在 start() 之前完成（安全模式菜单的数据源）。
        //    内置动作与自定义动作可混排，注册顺序即菜单展示顺序。
        //    约定：重启动作（RestartAction）注册在末位——破坏性退出路径
        //    置底呈现（红色警示样式），库不自动排序（见 README 末位约定）。
        ALLaunchGuard.shared.fixActions = [
            ALLaunchGuardClearCacheAction(),      // 内置：清理沙盒 Caches 目录（轻档位）
            ALLaunchGuardClearAllCacheAction(),   // 内置：白名单式沙盒深度清理（深档位）
            ClearDemoDataAction(),                // 自定义：清理沙盒 Documents/DemoData 目录
            ALLaunchGuardRestartAction()          // 内置：重启应用（末位约定）
        ]

        // 2. 注册安全模式最小启动任务（必须先于 start()，供安全模式激活时执行）。
        //    与 MPLaunchExample 对照：那里的任务闭包经 MainActor.assumeIsolated
        //    桥接编排器 runSafeModeTasks；本通用示例无编排器依赖，纯 Foundation
        //    直调（DemoSafeModeLogger，见 SafeModeLogBuffer.swift）。两个任务按
        //    注册顺序同步执行，展示注册顺序与任务依赖语义（先初始化缓冲、
        //    再记录事件）。任务约束见 SafeModeLogBuffer.swift 类注释。
        ALLaunchGuard.shared.safeModeLaunchTasks = [
            { DemoSafeModeLogger.bootstrap() },
            {
                DemoSafeModeLogger.log("安全模式启动：最小任务链已就绪")
                // 演示豁免：写一次性标记驱动首页横幅闭环（spec: example-apps
                // MODIFIED）；生产最小任务须遵守无磁盘 IO 约束（见 README）。
                UserDefaults.standard.set(true, forKey: "BasicExample.safeModeMinimalTaskRan")
            },
        ]

        // 3. 安全模式门控：返回 true 表示本次启动处于安全模式。
        //    Scene 生命周期下 didFinishLaunching 返回后 scene 仍会连接，
        //    SceneDelegate.willConnectTo 以 isInSafeMode 短路（不构建
        //    window/首页）；安全模式页面由库以独立 UIWindow 自动接管展示
        //    （uiConfig.presentationStyle 默认 .dedicatedWindow，库经
        //    willConnect 观察者以 UIWindow(windowScene:) 挂载）。
        //    正常启动路径的 window 构建与首页展示已迁入 SceneDelegate。
        if ALLaunchGuard.shared.start() {
            #if DEBUG
            // 收尾决策：进入安全模式即结束连续闪退演示——清零剩余自动崩溃
            // 次数（remaining = 0 持久化）。库为预支递增计数：达到阈值的
            // 那次启动已直接进入安全模式，不再消耗 remaining；若不在此
            // 清零，remaining 会残留（默认阈值 3 下卡在 1），导致修复重启
            // 后再多崩一次。清零与 arm 值/阈值解耦，适配任意 crashThreshold。
            BasicExampleCrashSimulator.shared.disarm()
            #endif
            return true
        }

        return true
    }
}
