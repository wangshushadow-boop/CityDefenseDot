# SET — 城镇、城堡、村庄与领地治理

> 版本 0.1（设计内容未变；目录版 0.2） | 状态：详细设计提案，待评审与实现 | 所属工程：recollection（古代中国风原创沙盒）
> 实现目录：`game/campaign/settlement/` | 总体基线：[§8、§9.1、§13、§17](../../../../game_design.md) | [系统索引](../../../README.md)

本文在总体规格书约束内补充实现级设计。接口为语言无关伪代码，字段及新增参数为拟定契约；未标明已冻结的数值需经 ADR/测试确认。公共语义见[公共契约](../../../../architecture/common_contracts.md)。测试均为待执行规格，不代表功能已实现。

## 1. 职责与边界

管理领地归属、治理参数、建设、粮仓、民兵、驻军引用、名人/访问权限、劫掠恢复、叛乱。王国决议由 POL 授权；真实兵力、市场和账户分别由 PARTY/ECO/INV 拥有。

**协作边界：** DEF/SHRULE；POL、PARTY、ECO、INV、WORLD、CHR 经门面/APP。跨模块写入经 application 或权威运行时编排；不直接访问其他模块私有仓库。

## 2. 数据所有权与生命周期

Settlement 持久实例 owner_clan_id、governor_id、prosperity、loyalty、security、buildings、garrison_ref、militia_ref、stock_ref、siege_id；物资和兵力只引用。

## 3. 代码组织

以下为建议的文件职责（按选定语言补扩展名；不是已有源码）：

```text
settlement / governance / governor
building_queue / daily_project / tax_plan
food_security / loyalty / militia_plan
ownership_transfer / rebellion / raid
access_policy / notable_schedule
```

## 4. 数据模型与约束

`BuildingState{def_id,level,progress,queue_order,paused}`；`GovernancePolicy{tax,wage_cap,recruit_policy,daily_project}`；`RaidState{attacker,progress,phase,recovery_until}`；`SettlementAccess{actor,allowed_actions,reason}`。所有者合法或明确过渡态；governor 必须可任职。

## 5. 公共接口

```text
SetGovernancePolicy(settlement,policy) -> ChangeSet
QueueBuilding / CancelBuilding(settlement,def_id) -> ChangeSet
plan_daily_governance(day_id,snapshot) -> GovernancePlan
TransferFief(settlement,new_clan,authorization) -> ChangeSet
StartRaid / StopRaid / CompleteRaid(...) -> ChangeSet
GetAccessPolicy(settlement,actor) -> SettlementAccess
```

所有修改型接口须在所属权威阶段提交；查询不推进时间。命令失败遵循公共错误码；空结果与非法输入分开。非幂等的外部请求须使用稳定请求 ID 或事务回执。

## 6. 核心算法与运行流程

日结从粮仓、商流、战争、驻军、总督和政策计算粮食、繁荣、治安、忠诚、民兵的限幅增量，建筑进度受资源和治理影响；维护成本走账本。低忠诚+弱驻军进入叛乱候选，由政治事务建立合法控制者。易主处理总督、税收归属、外交通行、任务和驻军；围城损坏及占领取 ENC 结算结果。劫掠有开始/进度/中断/完成/恢复，奖励仅完成事务发放一次。访问使用世界实时 NPC 资格和外交犯罪条件。

## 7. 配置、异常与安全边界

配置变量范围、建筑前置 DAG、治安/忠诚变化限幅、叛乱条件、劫掠冷却。取消建设退款按已消耗比例，不凭空增加材料。地方民兵增长通过合法人口/生成来源。城镇菜单和 3D 访问统一命令授权。

## 8. 表现及可观测性

城镇治理显示每日变化分项、建筑队列、驻军预算与访问/潜入/守卫检查结果。

**性能与诊断：** 日结按地点批处理，记录粮荒时长、忠诚分布、税收、建设与叛乱频率。

## 9. 验收用例

| 测试 ID | 需求 ID / 质量门禁 | Given（前置） | When（操作） | Then（判据） |
|---|---|---|---|---|
| T-SET-01 | SET-01 | 税收、工资、建筑和粮食不足 | 推进多日 | 资源不负、治理变量可解释 |
| T-SET-02 | SET-02 / POL-04 | 领地易主或叛乱 | 提交政治结果 | owner、税收、驻军、总督引用一致 |
| T-SET-03 | SET-03 | 围城与村庄劫掠中断 | 解除并等待恢复 | 资源与繁荣变化正确，无重复战利品 |
| T-SET-04 | SET-04 | NPC 死亡、敌城封锁、玩家犯罪 | 访问 | 名单/合法和非法路径按实际状态生成 |

## 10. 完成条件与实施约束

- 公开接口与本模块数据所有权已落地；所有配置通过内容编译或启动校验。
- 本章测试及受影响跨模块验收通过，保留实际运行报告；没有已知的状态一致性/权限阻断缺陷。
- 接口或存档结构变化同步契约、迁移与 ADR；性能目标需在指定基准上测量，不以空场或 mock 数据代替。
- 实现和测试变更限于本模块及获准契约；不得把尚未实现的部分伪装成已完成。

## 文档导航（镜像目录）

- 主要实现目录：`game/campaign/settlement/`；权威设计：本文件。
- 上级入口：[上级模块 / 分组](../README.md)；[全部模块索引](../../../README.md)。
