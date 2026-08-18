import UIKit
import ALLaunchGuard

/// 主 scene 委托（Info.plist UIApplicationSceneManifest 指定，iOS 26 scene 生命周期适配）。
///
/// 门控范式（与 MPLaunchExample 对齐）：start() 已在 AppDelegate.didFinishLaunching
/// 完成，isInSafeMode 即本次启动的最终裁决——安全模式下不构建 window/rootVC，
/// 安全模式独立窗口由库经 willConnect 观察者以 UIWindow(windowScene:) 接管，
/// 为该 scene 的唯一界面。
final class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        // 门控：安全模式路径不构建首页（库独立窗口接管）。
        if ALLaunchGuard.shared.isInSafeMode { return }

        guard let windowScene = scene as? UIWindowScene else { return }
        // 正常启动：构建 window 与首页（自 AppDelegate 迁移）。
        let window = UIWindow(windowScene: windowScene)
        // UINavigationController 承载导航栏（HomeViewController 的"直接进入
        // 安全模式"DEBUG 入口配置在 navigationItem 上）。
        window.rootViewController = UINavigationController(rootViewController: HomeViewController())
        window.makeKeyAndVisible()
        self.window = window

        #if DEBUG
        // 连续闪退演示（自 AppDelegate 迁移）：window 可见后调度，1 秒延迟
        // 保证崩溃发生在 5 秒存活窗口内且首页可见；安全模式路径上方已 return。
        BasicExampleCrashSimulator.shared.scheduleAutoCrashIfEnabled()
        #endif
    }
}
