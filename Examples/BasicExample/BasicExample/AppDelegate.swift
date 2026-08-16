import UIKit
import ALLaunchGuard

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?

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

        // 2. 安全模式门控：返回 true 表示本次启动处于安全模式，
        //    跳过全部正常启动任务（不构建 window / 首页）。
        //    安全模式页面由库以独立 UIWindow 自动接管展示
        //    （uiConfig.presentationStyle 默认 .dedicatedWindow）。
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

        // 3. 正常启动：构建 window 与首页。
        //    安全模式启动时，以下代码不会执行——
        //    这正是首页"启动任务清单"在安全模式下为空/不展示的原因。
        let window = UIWindow(frame: UIScreen.main.bounds)
        // 包一层 UINavigationController：HomeViewController 的“直接进入
        // 安全模式”DEBUG 入口配置在 navigationItem 上，需导航栏承载才可见。
        window.rootViewController = UINavigationController(rootViewController: HomeViewController())
        window.makeKeyAndVisible()
        self.window = window

        #if DEBUG
        // 4. 连续闪退演示（spec: example-apps MODIFIED / design D4）：
        //    仅正常启动路径调度（安全模式路径上方已 return，不会到达）——
        //    安全模式启动不打点不计时，自动崩溃无意义且干扰修复流程。
        //    放在 window 可见后调度，保证崩溃前用户能看到首页闪现。
        BasicExampleCrashSimulator.shared.scheduleAutoCrashIfEnabled()
        #endif

        return true
    }
}
