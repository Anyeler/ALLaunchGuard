## REMOVED Requirements

### Requirement: 存储协议扩展向后兼容
**Reason**: 预发布阶段不保留仅实现旧字段的存储降级路径。
**Migration**: 自定义存储实现全部四个持久化字段。

## ADDED Requirements

### Requirement: 存储协议完整契约
自定义存储实现 MUST 持久化连续闪退计数、上次启动 uptime 打点、后台死亡标记和安全模式粘滞标记。库 SHALL 不为这些字段提供 no-op 协议默认实现；默认 UserDefaults 实现 SHALL 完整持久化全部字段。

#### Scenario: 注入自定义存储
- **WHEN** 宿主注入自定义存储实现
- **THEN** 该实现提供协议声明的全部持久化字段，库可完整执行后台死亡、设备重启和粘滞安全模式判定
