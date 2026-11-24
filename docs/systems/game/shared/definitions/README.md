# DEF — 定义数据与引用注册

> 版本 0.1（设计内容未变；目录版 0.2） | 状态：详细设计提案，待评审与实现 | 所属工程：recollection（古代中国风原创沙盒）
> 实现目录：`game/shared/definitions/` | 总体基线：[§5–7、§17.1、§17.3、§18.2](../../../../game_design.md) | [系统索引](../../../README.md)

本文在总体规格书约束内补充实现级设计。接口为语言无关伪代码，字段及新增参数为拟定契约；未标明已冻结的数值需经 ADR/测试确认。公共语义见[公共契约](../../../../architecture/common_contracts.md)。测试均为待执行规格，不代表功能已实现。

## 1. 职责与边界

定义会话不可变的 HeroDef、CultureDef、TroopDef、ItemDef、EquipmentSetDef、ActionDef、SceneDef、RuleDef 等数据结构及查询；内容扫描与编译归 INF-CONTENT。定义层不含持久实例、市场价格或 Agent 状态。

**协作边界：** CON；由 INF-CONTENT 注入经编译数据。跨模块写入经 application 或权威运行时编排；不直接访问其他模块私有仓库。

## 2. 数据所有权与生命周期

DefinitionRegistry 在一个内容快照内不可变；稳定字符串 ID 映射为紧凑索引，索引仅会话有效；动态锻造物品定义采用单独版本化世界 overlay。

## 3. 代码组织

以下为建议的文件职责（按选定语言补扩展名；不是已有源码）：

```text
definition_id / typed_registry
culture / hero / troop / equipment / item
action / skill / perk / scene / ruleset
reference_index / dynamic_definition_overlay
```

## 4. 数据模型与约束

`DefHeader{id,schema_version,source_package}`；`TroopDef{culture_id,tier,role,equipment_set_ids,skills,wage_per_day,recruit_cost,upgrade_edges,tags}`；`ItemDef{category,base_value,weight,quality_policy,slot_tags,asset_ref}`；`ActionDef{duration_ticks,active_windows,cancel_rules,trajectory_ref}`。原始数据引用全使用稳定 ID。

## 5. 公共接口

```text
get<T>(DefId) -> Result<ReadOnlyDef<T>>
resolve_index<T>(id) -> Result<DefIndex>
list_by_tag(type, tags) -> ReadOnlyDef[]
validate_references(registry) -> ValidationReport
validate_dynamic_definition(definition, world_overlay) -> Result<Unit>
```

所有修改型接口须在所属权威阶段提交；查询不推进时间。命令失败遵循公共错误码；空结果与非法输入分开。非幂等的外部请求须使用稳定请求 ID 或事务回执。

## 6. 核心算法与运行流程

内容编译完成后构建 ID→索引、按类型/标签的查询；检查兵种升级图和天赋前置 DAG、动作时间窗、装备槽位、地图/任务引用。世界动态物品先验证合法部件和数值，再由 Economy+Inventory 事务写 overlay；存档保留动态定义，读取器先装载 overlay 后解析物品。

## 7. 配置、异常与安全边界

未找到 ID 明确报错，不回退成随机定义；运行时禁止修改基础定义；同一内容包补丁冲突由加载器解决。所有数值边界、单位及可选字段遵守 schema。

## 8. 表现及可观测性

无独立界面；通过公开查询、回执或已提交事件提供可观察结果。

**性能与诊断：** 不可变注册表共享；启动时解析引用，热路径使用会话内索引，不每帧字符串查找。

## 9. 验收用例

| 测试 ID | 需求 ID / 质量门禁 | Given（前置） | When（操作） | Then（判据） |
|---|---|---|---|---|
| T-DEF-01 | ARM-01 | 兵种升级形成环 | 编译 | 拒绝并显示路径 |
| T-DEF-02 | EXT-01 | 新增原创兵种、装备、文化 | 编译加载 | 不改核心代码即可查询 |
| T-DEF-03 | SAV-03 / ECO-05 | 锻造动态物品写入存档 | 重载 | ID、部件、规则快照可解析 |

## 10. 完成条件与实施约束

- 公开接口与本模块数据所有权已落地；所有配置通过内容编译或启动校验。
- 本章测试及受影响跨模块验收通过，保留实际运行报告；没有已知的状态一致性/权限阻断缺陷。
- 接口或存档结构变化同步契约、迁移与 ADR；性能目标需在指定基准上测量，不以空场或 mock 数据代替。
- 实现和测试变更限于本模块及获准契约；不得把尚未实现的部分伪装成已完成。

## 文档导航（镜像目录）

- 主要实现目录：`game/shared/definitions/`；权威设计：本文件。
- 上级入口：[上级模块 / 分组](../README.md)；[全部模块索引](../../../README.md)。
