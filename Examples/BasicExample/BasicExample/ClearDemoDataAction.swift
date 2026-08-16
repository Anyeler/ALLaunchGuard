import Foundation
import ALLaunchGuard

/// 自定义修复动作示例：清理沙盒 `Documents/DemoData` 目录。
///
/// 演示 `ALLaunchGuardFixAction` 协议的最小自定义实现——
/// 安全模式菜单页会以 `title` + `iconSystemName` 渲染菜单项，
/// 用户点击后由库统一编排执行（`ALLaunchGuard.perform(_:completion:)`）。
final class ClearDemoDataAction: ALLaunchGuardFixAction {

    let title: String = "清除示例数据"
    let iconSystemName: String? = "folder.badge.trash"

    func perform(completion: @escaping (Bool) -> Void) {
        // 耗时 IO 建议在后台队列执行；completion 可在任意线程回调，
        // 编排层会统一派发主队列（成功 → 自动 reset 并通知委托）。
        DispatchQueue.global(qos: .userInitiated).async {
            let fileManager = FileManager.default
            let demoDataURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("DemoData", isDirectory: true)

            do {
                if fileManager.fileExists(atPath: demoDataURL.path) {
                    try fileManager.removeItem(at: demoDataURL)
                }
                completion(true)
            } catch {
                completion(false)
            }
        }
    }
}
