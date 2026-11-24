# NAVAL-C — 海战扩展：战略水域、港口、舰队

> 版本 0.1（设计内容未变；目录版 0.2） | 状态：详细设计提案，待评审与实现 | 所属工程：recollection（古代中国风原创沙盒）
> 实现目录：`game/addons/naval/campaign/（新增建议，ADR-010 评审）` | 总体基线：[§24.1、§24.3–24.4，MOD-06](../../../../../game_design.md) | [系统索引](../../../../README.md)

本文在总体规格书约束内补充实现级设计。接口为语言无关伪代码，字段及新增参数为拟定契约；未标明已冻结的数值需经 ADR/测试确认。公共语义见[公共契约](../../../../../architecture/common_contracts.md)。测试均为待执行规格，不代表功能已实现。

## 1. 职责与边界

EXT 独立扩展。新增陆海交通、港口、舰船、舰队、船坞、航海补给与海运商队/海盗。基础世界不启用时无需海战模块；复用 WORLD、PARTY、ECO、ENC、INV 与战略 AI 端口，不修改陆战核心真值。

**协作边界：** DEF/CON、WORLD/PARTY/ECO/INV/ENC/SAI 的版本化扩展点。跨模块写入经 application 或权威运行时编排；不直接访问其他模块私有仓库。

## 2. 数据所有权与生命周期

ShipInstance、Fleet、PortState、ShipyardOrder、海上路线和舰船所有权；乘员源 Party、货物账本仍由现有领域拥有。

## 3. 代码组织

以下为建议的文件职责（按选定语言补扩展名；不是已有源码）：

```text
water_region / sea_route / port
ship_instance / shipyard / repair / fleet
embark_disembark / cargo_capacity
sea_trade / blockade / naval_strategic_policy
naval_encounter_extension
```

## 4. 数据模型与约束

`ShipInstance{id,def_id,owner_ref,damage,parts,crew_refs,cargo_inventory}`；`Fleet{id,ships,commander,party_ids,route,supply}`；`PortState{id,open,blockade,shipyard_capacity}`；`SeaEdge{depth,wind,current,weather,risk}`。陆/舰队位置互斥；船员与货物只在一个合法来源。

## 5. 公共接口

```text
Build / Buy / Repair / SellShip(...) -> ChangeSet
CreateFleet / AssignShip(...) -> ChangeSet
Embark / Disembark(party,fleet,port) -> ChangeSet
PlanSeaRoute(fleet,destination,conditions) -> Result<Route>
StartNavalEncounter(fleet,target) -> EncounterSpecExtension
ApplyNavalResult(extension) -> ChangeSet
```

所有修改型接口须在所属权威阶段提交；查询不推进时间。命令失败遵循公共错误码；空结果与非法输入分开。非幂等的外部请求须使用稳定请求 ID 或事务回执。

## 6. 核心算法与运行流程

海图将道路、河流、近岸、远海边按吃水与通行权限扩展；航速考虑风/流、桨/帆、天气、舰船损伤。登船/登陆验证港口或合法岸点、载量、船员、货仓和目标可达，原子更新位置/库存引用。船坞真实材料、时间和资金造修舰，海上贸易/封锁影响陆地供给。海盗/舰队战略候选经 SAI 注册；海上遭遇复用 ENC 预留并扩展船舶 allocation。

## 7. 配置、异常与安全边界

不启用扩展不注册水路和船舶；扩展移除有显式迁移或拒绝。舰船捕获检查容量和回港能力；无合法登陆不允许复制队伍。海战联机与多人战役不属于既定承诺。

## 8. 表现及可观测性

港口、船坞、舰队/航线、容量、补给、风浪和海战遭遇界面。

**性能与诊断：** 海路共享交通缓存；记录舰队移动、港口封锁及经济影响。

## 9. 验收用例

| 测试 ID | 需求 ID / 质量门禁 | Given（前置） | When（操作） | Then（判据） |
|---|---|---|---|---|
| T-NAVAL-C-01 | NAVAL-01 | 舰船建造、维修、买卖、编队和港口 | 执行登船航行登陆 | 船、队伍、货物唯一归属 |
| T-NAVAL-C-02 | NAVAL-02 | 港口封锁、海运商队、沿岸袭击 | 逐日推进 | 供应与后勤变化可解释 |
| T-NAVAL-C-03 | NAVAL-05 | 海战后捕获船只 | 结算 | 船舶货物和人员与来源一致 |
| T-NAVAL-C-04 | NAVAL-07 | 未安装海战扩展的本体 | 创建/加载/陆战 | 无海战依赖或行为变化 |

## 10. 完成条件与实施约束

- 公开接口与本模块数据所有权已落地；所有配置通过内容编译或启动校验。
- 本章测试及受影响跨模块验收通过，保留实际运行报告；没有已知的状态一致性/权限阻断缺陷。
- 接口或存档结构变化同步契约、迁移与 ADR；性能目标需在指定基准上测量，不以空场或 mock 数据代替。
- 实现和测试变更限于本模块及获准契约；不得把尚未实现的部分伪装成已完成。

## 文档导航（镜像目录）

- 主要实现目录：`game/addons/naval/campaign/`；权威设计：本文件。
- 上级入口：[上级模块 / 分组](../README.md)；[全部模块索引](../../../../README.md)。
