## Purpose

定义接入范例 App 的行为契约：提供通用示例与 MPLaunch 启动编排集成示例，可演示并验证安全模式的完整生命周期（正常启动、崩溃循环触发、界面接管、菜单修复、重启恢复），同时作为宿主接入范式的可运行参考。

## ADDED Requirements

### Requirement: 通用示例 App
仓库 SHALL 提供通用示例工程（git 追踪）：以本地 SPM 包方式引用本库；正常运行时首页 SHALL 展示"本次启动已执行的启动任务"清单；SHALL 提供"模拟启动闪退"操作（DEBUG 限定，进程立即崩溃）；SHALL 提供"直接进入安全模式"调试操作；SHALL 注册内置清缓存动作与至少一个自定义修复动作；连续三次模拟闪退后再次启动 SHALL 进入安全模式（正常任务清单不展示、菜单页窗口接管）。

#### Scenario: 正常启动
- **WHEN** 首次启动通用示例（无崩溃历史）
- **THEN** 首页展示启动任务清单，未出现安全模式界面

#### Scenario: 崩溃循环进入安全模式
- **WHEN** 连续三次点击"模拟启动闪退"（每次重启后再点），第四次启动
- **THEN** 安全模式菜单页以独立窗口接管展示，正常启动任务未执行，修复动作可点击执行并出现重启提示

### Requirement: MPLaunch 集成示例 App
仓库 SHALL 提供 MPLaunch 集成示例（不纳入 git 追踪，附本地生成/配置说明）：以真实 MPLaunch 编排启动任务（含多个示例 Launchable 模块），root 页面构建 SHALL 位于某启动模块的 sceneDelegate 中；AppDelegate/SceneDelegate SHALL 按门控范式在安全模式下跳过 onceUponAnApp/onceUponAScene；安全模式激活时 MPLaunch 全链路 SHALL 未执行（模块任务清单为空）。

#### Scenario: 门控生效
- **WHEN** MPLaunch 示例进入安全模式
- **THEN** 未调用启动编排入口，任何 Launchable 模块任务未执行，安全模式窗口为唯一界面

#### Scenario: 正常启动编排
- **WHEN** MPLaunch 示例正常运行
- **THEN** 各示例模块按依赖序执行，root 页面正常构建展示

### Requirement: 示例不进入库产物与 git 追踪
示例工程 SHALL 被排除在库分发产物之外（podspec source_files 与主 Package.swift 产物均不包含 Examples）；MPLaunch 示例目录 SHALL 被 .gitignore 整目录忽略（内部私有库相关，不入库），本地 SHALL 附简短说明（双本地包引用方式）；主 README SHALL 说明该示例为本地专属并给出从零搭建同类示例的指引。

#### Scenario: 分发产物纯净
- **WHEN** 检查 podspec 通配与 SPM 产物
- **THEN** 均不含 Examples 下任何文件

#### Scenario: MPLaunch 示例不入库
- **WHEN** 查看 git 追踪状态
- **THEN** Examples/MPLaunchExample/ 整目录被忽略，仓库不含任何 MPLaunch 私有内容

### Requirement: 文档与版本收口
README SHALL 重写以反映 2.0 行为：打点法判定语义、didFinishLaunching 首行门控接入范式、完整配置表、与启动编排器（MPLaunch 等）集成专节、废弃 API 迁移说明（fixButtonTitle → restartHint、旧安全模式页、presentSafeModeUIIfNeeded）；podspec 版本 SHALL 升至 2.0.0（不执行发布命令）。

#### Scenario: README 与实现一致
- **WHEN** 阅读 README 的接入示例代码
- **THEN** 与当前公共 API 完全一致（start() 返回值、fixActions、presentationStyle 等），无已废弃字段的用法残留
