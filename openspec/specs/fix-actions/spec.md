# fix-actions Specification

## Purpose

定义安全模式下可扩展的修复动作能力：动作以协议化菜单项形式由宿主或库注册，用户主动点击才执行，库统一编排执行结果与安全模式退出时机，为菜单式修复页提供可测试的非 UI 契约。

## Requirements
### Requirement: 修复动作协议契约
修复动作 SHALL 以协议形式定义，包含：菜单标题（String）、SF Symbol 图标名（可选 String，nil 时 UI 使用默认图标）、破坏性样式标记（Bool，默认 false，UI 呈现警示样式），以及执行方法（用户点击后调用，MUST 恰好回调一次 completion，参数 true 表示成功、false 表示失败）。动作 SHALL 仅在用户显式触发时执行，库 MUST NOT 在进入安全模式时自动执行任何修复动作。

#### Scenario: 动作元数据
- **WHEN** 宿主注册一个自定义修复动作（提供标题、图标名、破坏性标记）
- **THEN** 库可读取该动作的完整元数据用于菜单展示，未提供图标名时 UI 侧使用默认图标

#### Scenario: 点击才执行
- **WHEN** 安全模式激活但用户未点击任何菜单项
- **THEN** 没有任何修复动作被执行，安全模式状态保持不变

### Requirement: 修复动作注册
系统 SHALL 提供修复动作注册属性（`fixActions`，数组，默认为空数组），宿主可在启动早期注册一个或多个动作（内置动作与自定义动作混排）；注册顺序 SHALL 保持为菜单展示顺序。

#### Scenario: 注册多个动作
- **WHEN** 宿主注册内置清缓存动作与两个自定义动作
- **THEN** 注册属性中按注册顺序包含三个动作，可供 UI 以列表呈现

### Requirement: 执行编排与安全模式退出
系统 SHALL 提供动作执行编排：执行指定动作并等待其 completion——成功时 SHALL 触发一次安全模式重置（清零计数、清除粘滞标记、触发退出回调）并通知委托该动作成功；失败时 MUST NOT 重置安全模式、MUST NOT 触发退出回调，仅通知委托该动作失败（允许用户重试）。同一会话内多次成功动作 SHALL 只触发一次重置语义的最终状态（重复调用重置为幂等）。

#### Scenario: 首个成功动作退出安全模式
- **WHEN** 安全模式下用户触发动作 A 且其 completion(true)
- **THEN** 安全模式退出（计数清零、粘滞标记清除）、退出回调触发一次、动作成功回调触发

#### Scenario: 失败动作不退出安全模式
- **WHEN** 用户触发动作 B 且其 completion(false)
- **THEN** 安全模式保持激活（计数与粘滞标记不变）、无退出回调、动作失败回调触发，用户可再次触发改动作或其他动作

### Requirement: 内置清缓存动作
系统 SHALL 提供开箱即用的清缓存动作：清理应用沙盒 Caches 目录内容（含子目录）；目录为空或不存在时 SHALL 视为成功；清理失败（抛出错误）SHALL 以 completion(false) 结束。动作元数据 SHALL 提供默认中文标题与图标名。

#### Scenario: 清理含内容的 Caches 目录
- **WHEN** Caches 目录含文件与子目录，用户触发内置清缓存动作
- **THEN** 目录内容被清空，completion(true)

#### Scenario: Caches 目录不存在
- **WHEN** Caches 目录不存在，用户触发内置清缓存动作
- **THEN** completion(true)，不报错

### Requirement: 闭包包装动作
系统 SHALL 提供便捷闭包包装类型：以标题/图标/破坏性标记/执行闭包构造一个符合修复动作协议的实例，便于宿主一行注册轻量修复逻辑。

#### Scenario: 闭包包装执行
- **WHEN** 宿主用闭包包装注册动作并触发执行，闭包内回调 true
- **THEN** 该动作表现与自定义类实现完全一致（completion(true) 传递到编排层）

### Requirement: 委托完成回调
委托协议 SHALL 追加可选回调（动作执行完成，携带动作与成功标志），带默认空实现——既有委托实现者零改动。

#### Scenario: 既有委托实现者不受影响
- **WHEN** 宿主的委托对象只实现进入/退出安全模式两个回调
- **THEN** 代码无需修改即可编译，动作完成回调使用默认空实现



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
