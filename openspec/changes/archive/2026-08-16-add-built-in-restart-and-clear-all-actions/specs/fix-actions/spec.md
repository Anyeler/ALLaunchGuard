## ADDED Requirements

### Requirement: 内置重启动作
系统 SHALL 提供内置"重启应用"修复动作（破坏性样式）：执行时 SHALL 先回调成功（使编排层的安全模式重置先入主队列），随后在主队列晚一拍终止进程（exit(0)）——依赖主队列 FIFO 保证粘滞标记清除先于进程终止，避免重启后再次进入安全模式。动作的进程终止行为 SHALL 可注入替换（供测试）。菜单位置 SHALL 由宿主注册顺序决定（文档约定置于末位），库 MUST NOT 自动排序或自动注入。

#### Scenario: 重启先于粘滞残留
- **WHEN** 用户在安全模式菜单触发重启动作
- **THEN** 安全模式重置（粘滞标记清除）先于进程终止完成，用户下次打开 App 恢复正常启动流程

#### Scenario: 末位注册约定
- **WHEN** 宿主将重启动作注册在 fixActions 末位
- **THEN** 菜单最后一项为"重启应用"，库不改变其位置

### Requirement: 内置白名单缓存全清动作
系统 SHALL 提供内置"缓存全清"修复动作：清理沙盒中的临时与非重要目录——tmp 内容、.Trash、保护名单之外的游离顶层项、Library/Caches 内容；默认保护顶层目录 Documents、Library（Caches 除外部分）、SystemData，保护名单 SHALL 可由宿主扩展。白名单判定 SHALL 在删除执行时刻逐条评估（而非枚举快照），条目在枚举后消失 SHALL 按成功处理（幂等）；单项删除失败 SHALL 继续清理其余项并在最终聚合为失败结果（可重试）。清理 SHALL 在后台低优先级队列执行。动作 SHALL 支持注入沙盒根目录（供测试）。

#### Scenario: 默认白名单保护
- **WHEN** 沙盒含 Documents/Library/Caches/Preferences/tmp/SystemData/.Trash 与游离文件，执行全清
- **THEN** Documents、SystemData 与 Library 中 Caches 之外的内容保留；tmp 内容、.Trash、游离顶层项与 Library/Caches 内容被清空

#### Scenario: 自定义保护目录
- **WHEN** 宿主将自建顶层目录加入 protectedTopLevelItems 后执行全清
- **THEN** 该目录被保留

#### Scenario: 枚举后新建条目不误删
- **WHEN** 枚举完成后、删除执行前业务在受清理目录新建条目
- **THEN** 判定以删除时刻为准（白名单内保留、名单外清理），不因快照陈旧误删

#### Scenario: 部分失败聚合
- **WHEN** 某一项删除失败
- **THEN** 其余项继续清理，最终回调失败（用户可重试），不中断整体清理
