# NAVAL-P — 海战扩展：内容包、工具与兼容

> 版本 0.1（设计内容未变；目录版 0.2） | 状态：详细设计提案，待评审与实现 | 所属工程：recollection（古代中国风原创沙盒）
> 实现目录：`game/content/expansions/naval/；game/addons/naval/（代码路径建议）` | 总体基线：[§24、§18.2、§21，MOD-06](../../../../../game_design.md) | [系统索引](../../../../README.md)

本文在总体规格书约束内补充实现级设计。接口为语言无关伪代码，字段及新增参数为拟定契约；未标明已冻结的数值需经 ADR/测试确认。公共语义见[公共契约](../../../../../architecture/common_contracts.md)。测试均为待执行规格，不代表功能已实现。

## 1. 职责与边界

EXT。定义海战独立内容包、舰船/港口/海员/水域场景、海战剧情、自定义海战及编辑器。只在启用扩展时注册战略和 Mission 插件；不是本体 MUST 的替代。

**协作边界：** NAVAL-C/NAVAL-M、INF-CONTENT/DEF、PERSIST、ADDONS/TOOLS。跨模块写入经 application 或权威运行时编排；不直接访问其他模块私有仓库。

## 2. 数据所有权与生命周期

海战 manifest、扩展定义、迁移版本与海图/舰船资产；代码注册归可信插件。

## 3. 代码组织

以下为建议的文件职责（按选定语言补扩展名；不是已有源码）：

```text
manifest.json
definitions/ships / parts / ports / water_regions / crew
maps/sea_routes / coast / rivers
scenes/open_water / river / coastal / boarding
assets/ships / deck / sea / audio
localization/
(editor) ship_editor / sea_map_validator
```

## 4. 数据模型与约束

`NavalEncounterExtension{fleet_ids,ship_allocations,sea_region_id,weather_seed,wind,current,port_or_coast_context?,boarding_ruleset_id}`；`ShipAllocation{ship_instance_id,source_fleet_id,team_key,damage_snapshot,equipment_snapshot,crew_source_slots,cargo_manifest}`；`NavalResultExtension{ship_outcomes,cargo_transfers,crew_slot_outcomes,port_changes?,naval_xp}`。挂载于版本化基础跨域契约。

## 5. 公共接口

```text
register_naval_package(content,extension_registry) -> Result<Unit>
validate_ship_definition(ship) -> ValidationReport
validate_sea_map(map) -> ValidationReport
migrate_naval_save(world,package_change) -> Result<WorldSnapshot>
CreateCustomNavalBattle(spec) -> Result<MissionId>
```

所有修改型接口须在所属权威阶段提交；查询不推进时间。命令失败遵循公共错误码；空结果与非法输入分开。非幂等的外部请求须使用稳定请求 ID 或事务回执。

## 6. 核心算法与运行流程

舰船编辑器验证甲板局部导航、碰撞、武器挂点、岗位、上下船点、船体和沉没状态；水域地图验证陆海连通、吃水、港口和航线。注册海战任务、航海技能、原创地区/文化、海员兵种和自定义海战规则；存档先校验扩展版本，新增扩展可初始化海域/港口状态，移除含船舶的扩展须明确迁移或拒绝。

## 7. 配置、异常与安全边界

保留原本体包版本及内容 hash；扩展字段仅由已注册读者处理，未知关键扩展拒绝。不得悄悄丢弃船只、人员或货物；本体兼容回归必测。

## 8. 表现及可观测性

无独立界面；通过公开查询、回执或已提交事件提供可观察结果。

**性能与诊断：** 海战内容单独容量和资源预算，记录舰船局部导航/碰撞与海图验证结果。

## 9. 验收用例

| 测试 ID | 需求 ID / 质量门禁 | Given（前置） | When（操作） | Then（判据） |
|---|---|---|---|---|
| T-NAVAL-P-01 | NAVAL-06 / MOD-06 | 海战剧情、海员、船型与自定义海战 | 编译试玩 | 完整模式和工具可使用 |
| T-NAVAL-P-02 | NAVAL-05 | 扩展世界存档含舰船动态状态 | 迁移 | 数据完整或明确拒绝 |
| T-NAVAL-P-03 | NAVAL-07 | 本体和启用扩展的世界分别加载 | 回归 | 未启用本体不受影响 |

## 10. 完成条件与实施约束

- 公开接口与本模块数据所有权已落地；所有配置通过内容编译或启动校验。
- 本章测试及受影响跨模块验收通过，保留实际运行报告；没有已知的状态一致性/权限阻断缺陷。
- 接口或存档结构变化同步契约、迁移与 ADR；性能目标需在指定基准上测量，不以空场或 mock 数据代替。
- 实现和测试变更限于本模块及获准契约；不得把尚未实现的部分伪装成已完成。

## 文档导航（镜像目录）

- 主要实现目录：`game/content/expansions/naval/`；权威设计：本文件。
- 上级入口：[上级模块 / 分组](../README.md)；[全部模块索引](../../../../README.md)。
- 共享规格的另一实现目录：`game/addons/naval/`；[对应入口](../../../addons/naval/README.md)。
