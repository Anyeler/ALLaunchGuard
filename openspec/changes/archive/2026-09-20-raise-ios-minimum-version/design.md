## Context

当前 SPM 清单、CocoaPods podspec 与 README 将最低版本声明为 iOS 14.0；菜单展示路径因此在运行时分支选择 iOS 15 的 scene key window API 或 iOS 14 的窗口枚举回退。详见 proposal.md。

## Goals / Non-Goals

**Goals:**
- 使两个分发入口、公开文档和 UIKit 实现遵循同一 iOS 15.0 基线。
- 删除仅服务于 iOS 14 的运行时兼容分支及相应说明。
- 删除在本次确认范围内仅服务于历史 API 兼容的展示、存储和委托回退。

**Non-Goals:**
- 不改变 Swift 5.0 语言支持、非 UIKit 平台下的测试策略或安全模式行为。
- 不修改不涉及 deployment target 的无关项目文件。
- 不修改任何 MLaunch 相关 Example。

## Decisions

### 同时更新全部发布声明

SPM 和 CocoaPods 都升级到 15.0，并同步 README。只修改其中一个渠道会让使用者在不同安装方式下得到矛盾的兼容性契约；保留 14.0 声明则可能允许不受支持的集成。

### 直接采用 scene key window API

菜单展示路径将直接读取 `UIWindowScene.keyWindow`。替代方案是保留 `#available` 与 `scene.windows` 回退；该方案已不再提供受支持系统上的价值，且会持续增加维护与测试分支。

### 只保留独立窗口展示

自动展示和显式展示统一使用独立窗口。移除 `presentOnRoot` 配置、展示路由和菜单 present 入口，避免仍为旧宿主 window/rootVC 生命周期保留一套公开 API 与运行时路径。

### 强制完整实现扩展协议

移除存储与委托协议的默认实现，使协议声明成为完整契约。替代方案是保留 no-op 默认值；其会让自定义存储静默退化、并让委托遗漏动作完成回调，均与预发布阶段不保留历史兼容的决定冲突。

### 保留与系统行为有关的说明

README 中关于 iOS 15/16 预热问题的说明不属于库的低版本兼容逻辑，仍描述受支持系统上的已知风险，因此保留并只删除 iOS 14 对比表述。

## Risks / Trade-offs

- [升级是破坏性兼容变更，iOS 14 项目无法解析或使用该版本] → 在两个包管理器声明和 README 中明确 15.0 基线。
- [去除回退后无法在 iOS 14 运行] → 这是目标支持边界；deployment target 在集成时阻止该场景。
- [文档遗漏旧版本表述] → 实施时全文检索 iOS 14/14.0 并在验证中确认结果。
- [历史 API 移除导致宿主编译失败] → 这是已确认的破坏性改动；README 明确新的完整协议要求和仅独立窗口展示方式。

## Migration Plan

1. 更新分发清单、BasicExample 的 deployment target 与文档中的最低版本声明及移除 API 的迁移说明。
2. 移除 iOS 14 key-window 回退、历史展示路径与协议默认实现，并调整测试替身为完整实现。
3. 运行单元测试，并检查发布配置、源码和 README 中不再含有目标兼容路径。
4. 如需回滚，恢复 iOS 14 deployment target、展示回退和协议默认实现；由于项目尚未发布，无需用户数据迁移。
