import XCTest
@testable import ALLaunchGuard

// MARK: - 挂载决策纯函数表驱动（tasks 1.1，spec: safe-mode-window / design D3-D4）

/// install 挂载策略的决策判定（attach / immediateFrameFallback /
/// waitSceneWithTimeout）抽为无 UIKit 依赖的 internal 纯函数，macOS/Linux
/// 可直接单测；`Bundle.main` 读取仅存在于协调器的 `sceneManifestDetector`
/// 默认闭包，纯函数只接收 Bool 参数（design 风险：测试环境 Bundle.main
/// 为 xctest runner，检测结果须经注入传入）。
final class ALLaunchGuardSafeModeWindowMountTests: XCTestCase {

    /// 决策表：hasWindowScene × sceneManifestConfigured → 期望决策
    func testMountDecisionTableDriven() {
        let cases: [
            (hasWindowScene: Bool,
             sceneManifestConfigured: Bool,
             expected: ALLaunchGuardWindowMountDecision)
        ] = [
            // 有可用 scene（两级候选：foregroundActive 优先 → 任意
            // UIWindowScene）：直接 attach，与 manifest 配置无关
            (true,  true,  .attach),
            (true,  false, .attach),
            // 无 scene + 无 scene manifest（经典 AppDelegate 生命周期）：
            // 立即全屏 frame 降级，不等超时（消除 5 秒黑屏）
            (false, false, .immediateFrameFallback),
            // 无 scene + 有 scene manifest（SceneDelegate 生命周期，
            // scene 尚未连接）：注册 willConnect 观察 + 超时降级兜底
            (false, true,  .waitSceneWithTimeout),
        ]
        for testCase in cases {
            XCTAssertEqual(
                ALLaunchGuardWindowMountDecision.decide(
                    hasWindowScene: testCase.hasWindowScene,
                    sceneManifestConfigured: testCase.sceneManifestConfigured
                ),
                testCase.expected,
                "hasWindowScene=\(testCase.hasWindowScene), "
                    + "sceneManifestConfigured=\(testCase.sceneManifestConfigured)"
            )
        }
    }
}
