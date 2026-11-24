# BASE — 本体原创内容包与资源制作

> 版本 0.1（设计内容未变；目录版 0.2） | 状态：详细设计提案，待评审与实现 | 所属工程：recollection（古代中国风原创沙盒）
> 实现目录：`game/content/base/` | 总体基线：[§1.1–1.3、§15.2、§18、§21](../../../../game_design.md) | [系统索引](../../../README.md)

本文在总体规格书约束内补充实现级设计。接口为语言无关伪代码，字段及新增参数为拟定契约；未标明已冻结的数值需经 ADR/测试确认。公共语义见[公共契约](../../../../architecture/common_contracts.md)。测试均为待执行规格，不代表功能已实现。

## 1. 职责与边界

提供原创古代中国风世界所需的定义、地图、场景、美术、动画、音频与本地化；不是新的业务代码模块。完整内容规模遵循总体 §1.3 的规划范围，具体文化、地理、剧情、装备数值尚需内容团队创作，不虚构已经完成的内容。

**协作边界：** DEF/INF-CONTENT/TOOLS 规范；各游戏系统消费编译定义。跨模块写入经 application 或权威运行时编排；不直接访问其他模块私有仓库。

## 2. 数据所有权与生命周期

源资产、manifest、稳定定义 ID、资源授权元数据；基础定义会话内不可变，动态物品和世界状态不写源包。

## 3. 代码组织

以下为建议的文件职责（按选定语言补扩展名；不是已有源码）：

```text
manifest.json
definitions/cultures / kingdoms / heroes / troops / items
 definitions/skills / perks / economy / policies / quests / rules
maps/strategic / regions / routes
scenes/field / town / castle / village / hideout / arena / interiors
assets/characters / mounts / weapons / architecture / terrain / audio
localization/zh_CN / other_locales
```

## 4. 数据模型与约束

`CultureDef{language_keys,visual_theme,troop_tree_ids,settlement_theme,economic_tags}`；`SceneDef{asset_ref,spawn_zones,nav_profiles,links,objectives,interactions,exit_zones}`；`AssetMeta{id,source,license,author,rig_id?,lods,scale,checksum}`。原创文化、地图、人物与文本不得依赖参考游戏私有资源。

## 5. 公共接口

```text
compile_base_package(source) -> CompiledContent
validate_scene(scene_def) -> ValidationReport
validate_asset(asset_meta,rig_spec) -> ValidationReport
get_localized_text(key,locale,args) -> Text
```

所有修改型接口须在所属权威阶段提交；查询不推进时间。命令失败遵循公共错误码；空结果与非法输入分开。非幂等的外部请求须使用稳定请求 ID 或事务回执。

## 6. 核心算法与运行流程

世界内容编写遵循古代中国风原创虚构文化设定，文化差异落实在建筑、装备、兵种树、生产、政治和人物关系。源数据→模型/动画/地图制作→导入→引用/骨骼/攻击窗/导航验证→试玩/性能/平衡→版本化内容包。兵种树、技能树、地图关系、任务分支均须可验证。总体规划 6–8 文化、8–10 初始王国、50–70 城镇、80–120 城堡、200–350 村庄、150–250 兵种节点、30–50 动态任务模板（均待资源/产量评审）。

## 7. 配置、异常与安全边界

统一米制、骨骼/挂点、材质、碰撞、LOD、命名、文本键和许可证；数量不代表质量。缺引用、不可达目标、超预算、缺授权、本地化键缺失阻断构建。发布内容不从原作抽取。

## 8. 表现及可观测性

文化风格和兵种差异须能通过游戏内百科、装备和场景辨识。

**性能与诊断：** 记录每地图导航/资产体积、材质、蒙皮/纹理预算和生产吞吐；实测内容规模后冻结。

## 9. 验收用例

| 测试 ID | 需求 ID / 质量门禁 | Given（前置） | When（操作） | Then（判据） |
|---|---|---|---|---|
| T-BASE-01 | EXT-01 / MIS-03 | 新原创文化、兵种、场景包 | 编译 | 合法引用、可达出生/目标和升级图 |
| T-BASE-02 | VIS-01 | 角色马匹与兵器不同组合 | 导入验证 | 骨骼、挂点、尺寸、动画窗口兼容 |
| T-BASE-03 | UX-03 | 主流程各语言资源 | 校验 | 无关键缺失文本 |
| T-BASE-04 | §1.3 / §23.3 | 正式内容清单 | 发布评审 | 数量、质量、授权、玩法标记符合冻结基线 |

## 10. 完成条件与实施约束

- 公开接口与本模块数据所有权已落地；所有配置通过内容编译或启动校验。
- 本章测试及受影响跨模块验收通过，保留实际运行报告；没有已知的状态一致性/权限阻断缺陷。
- 接口或存档结构变化同步契约、迁移与 ADR；性能目标需在指定基准上测量，不以空场或 mock 数据代替。
- 实现和测试变更限于本模块及获准契约；不得把尚未实现的部分伪装成已完成。

## 文档导航（镜像目录）

- 主要实现目录：`game/content/base/`；权威设计：本文件。
- 上级入口：[上级模块 / 分组](../README.md)；[全部模块索引](../../../README.md)。

| 对应实现目录 | 设计入口 | 类型 |
|---|---|---|
| `game/content/base/definitions/` | [本体定义数据](definitions/README.md) | 父规格子目录 |
| `game/content/base/maps/` | [战略地图数据](maps/README.md) | 父规格子目录 |
| `game/content/base/scenes/` | [任务场景](scenes/README.md) | 父规格子目录 |
| `game/content/base/assets/` | [原创资产](assets/README.md) | 父规格子目录 |
| `game/content/base/localization/` | [本地化内容](localization/README.md) | 父规格子目录 |
