# CLAN — 家族、婚育、同伴、职责与继承

> 版本 0.1（设计内容未变；目录版 0.2） | 状态：详细设计提案，待评审与实现 | 所属工程：recollection（古代中国风原创沙盒）
> 实现目录：`game/campaign/clan/` | 总体基线：[§5.2、§9.1、§17](../../../../game_design.md) | [系统索引](../../../README.md)

本文在总体规格书约束内补充实现级设计。接口为语言无关伪代码，字段及新增参数为拟定契约；未标明已冻结的数值需经 ADR/测试确认。公共语义见[公共契约](../../../../architecture/common_contracts.md)。测试均为待执行规格，不代表功能已实现。

## 1. 职责与边界

维护家族成员、领导、名望等级、谱系、关系与职责；建立家族资产归属引用。政治资格由 POL 计算，实际金钱/库存归 INV，领地 owner 归 SET，英雄生命归 CHR。

**协作边界：** CHR/DEF 公开查询、INV/PARTY/SET/POL 通过 APP 协作。跨模块写入经 application 或权威运行时编排；不直接访问其他模块私有仓库。

## 2. 数据所有权与生命周期

Clan 拥有成员集合、谱系边、家族职责与名望；Hero.clan_id、Clan.party_ids/fief_ids 是同事务维护的引用/投影。角色关系图由 Clan 领域提供统一索引，Character 不再建第二写库。

## 3. 代码组织

以下为建议的文件职责（按选定语言补扩展名；不是已有源码）：

```text
clan / membership / genealogy
relationship_graph / marriage
companion_recruit / role_assignment
renown / clan_tier / succession
family_lifecycle / clan_queries
```

## 4. 数据模型与约束

`Clan{id,culture_id,leader_id?,kingdom_id?,members,renown,tier,asset_refs,party_ids,fief_ids}`；`KinshipEdge{parent,child,kind}`；`Relation{from,to,kind,value,expires?}`；`RoleAssignment{hero,scope_ref,role}`；`SuccessionCase{clan_id,reason,candidates,status}`。谱系 DAG，婚配双方成年且无禁止亲缘；同英雄角色并存矩阵配置。

## 5. 公共接口

```text
RecruitCompanion(clan,hero,offer) -> ChangeSet
AssignRole(hero, role, scope) -> ChangeSet
ProposeMarriage(actor,target,terms) -> Result<Proposal>
ResolveMarriage(proposal,choice) -> ChangeSet
GrantRenown(clan, amount, source_id) -> ChangeSet
ResolveSuccession(case_id, successor) -> ChangeSet
step_family_lifecycle(day_id, snapshot) -> Commands[]
```

所有修改型接口须在所属权威阶段提交；查询不推进时间。命令失败遵循公共错误码；空结果与非法输入分开。非幂等的外部请求须使用稳定请求 ID 或事务回执。

## 6. 核心算法与运行流程

名望从已提交事件累计并刷新等级/容量；任职检查在世、可达、资格、同时间互斥，替换时解除旧职位。婚育根据成年、配偶、政策、时间与随机流产生候选，提交前检查谱系；出生新 Hero 由 CHR 创建，成年后按教育规则成长。领袖死亡→冻结需领袖授权操作→列合法候选→玩家选/AI 评分→原子更新家族与政治引用、控制权/封地/队伍/任务。无继承人进入消亡/明确结束规则。

## 7. 配置、异常与安全边界

配置家族等级阈值、同伴上限、成年年龄、角色互斥矩阵、继承规则；关系方向/对称定义明确。不能因配偶加入复制其物品/军队；取消提议释放预留。

## 8. 表现及可观测性

家族树、职责效果、伴侣提议、继承选择显示资格与失败原因。

**性能与诊断：** 维护按家族、角色和亲属反向索引；年度统计人口、继承耗时和无主资产。

## 9. 验收用例

| 测试 ID | 需求 ID / 质量门禁 | Given（前置） | When（操作） | Then（判据） |
|---|---|---|---|---|
| T-CLAN-01 | CLN-01 | 同伴名额已满或人物在另一队伍任互斥角色 | 招募/任命 | 拒绝且原职责不变 |
| T-CLAN-02 | CLN-02 | 多年婚育、衰老与死亡 | 逐日推进 | 谱系无环，成年和继承引用有效 |
| T-CLAN-03 | CLN-03 / AT-09 | 玩家领袖死亡且有两候选 | 选择继承人 | 玩家可继续，所有资产/任务有合法归属 |

## 10. 完成条件与实施约束

- 公开接口与本模块数据所有权已落地；所有配置通过内容编译或启动校验。
- 本章测试及受影响跨模块验收通过，保留实际运行报告；没有已知的状态一致性/权限阻断缺陷。
- 接口或存档结构变化同步契约、迁移与 ADR；性能目标需在指定基准上测量，不以空场或 mock 数据代替。
- 实现和测试变更限于本模块及获准契约；不得把尚未实现的部分伪装成已完成。

## 文档导航（镜像目录）

- 主要实现目录：`game/campaign/clan/`；权威设计：本文件。
- 上级入口：[上级模块 / 分组](../README.md)；[全部模块索引](../../../README.md)。
