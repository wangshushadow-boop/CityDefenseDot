# QUEST — 动态任务、剧情导演、对话与事件

> 版本 0.1（设计内容未变；目录版 0.2） | 状态：详细设计提案，待评审与实现 | 所属工程：recollection（古代中国风原创沙盒）
> 实现目录：`game/campaign/quest/` | 总体基线：[§14、§2、§8.3、§13、§17](../../../../game_design.md) | [系统索引](../../../README.md)

本文在总体规格书约束内补充实现级设计。接口为语言无关伪代码，字段及新增参数为拟定契约；未标明已冻结的数值需经 ADR/测试确认。公共语义见[公共契约](../../../../architecture/common_contracts.md)。测试均为待执行规格，不代表功能已实现。

## 1. 职责与边界

负责数据驱动任务/对话/剧情阶段、动态事件生成及奖励领取去重；人物、库存、领地、战斗状态由对应领域掌握。剧情与沙盒共享任务引擎，沙盒不注册强制主线。

**协作边界：** CON/DEF/CORE；各域可见投影、APP 命令端口和 MissionResult。跨模块写入经 application 或权威运行时编排；不直接访问其他模块私有仓库。

## 2. 数据所有权与生命周期

QuestInstance、DialogueSession、StoryProgress、EventOpportunity、RewardClaim 归 QUEST；定义不可变，事件消费游标可持久化。

## 3. 代码组织

以下为建议的文件职责（按选定语言补扩展名；不是已有源码）：

```text
quest_definition / quest_instance / stage_machine
condition_evaluator / objective_handlers / deadline
reward_claim / event_deduplicator
story_director / tutorial_progress
dialogue_graph / persuasion / opportunity_generator
```

## 4. 数据模型与约束

`QuestDef{id,version,issuer_filter,prerequisites,stages,deadline,reward,invalidations}`；`QuestInstance{id,def_id,def_version,actor_refs,stage,deadline,counters,status,rewarded,last_event_cursor}`；`DialogueNode{speaker,text_key,conditions,choices[],next}`；任务 Available→Accepted→Active→Completed/Failed/Expired/Cancelled，rewarded 独立。

## 5. 公共接口

```text
AcceptQuest(actor,quest_id) -> ChangeSet
on_committed(event,quest_view) -> Commands[]
CompleteDialogueChoice(session,node,choice,revision) -> ChangeSet
ClaimReward(quest,reward_id) -> ChangeSet
step_deadlines(minute) -> Commands[]
GenerateOpportunity(world_view,rng) -> QuestOffer[]
GetQuestJournal(actor) -> QuestReadModel
```

所有修改型接口须在所属权威阶段提交；查询不推进时间。命令失败遵循公共错误码；空结果与非法输入分开。非幂等的外部请求须使用稳定请求 ID 或事务回执。

## 6. 核心算法与运行流程

任务模板先验证目标引用和可达路径；生成按真实短缺、冲突、地区冷却和容量采样。接受后冻结必要参与者和版本；已提交事件按 event_id 去重匹配条件，推进阶段；期限和实体失效触发替代分支或失败，完成领取独立事务。对话显示前读取可见状态，选择时重验角色在场和条件，调用授权用例；说服判定注入随机流并设冷却。主线导演管理序章、家族危机、势力选择、战争政治、沙盒继续；教程可跳过且有检查点。

## 7. 配置、异常与安全边界

奖励不能由场景脚本直接发；重复读档不得重复已领取奖励。任务不可达时明确替代/失效；禁止一般角色因任务永久免死。模板最大阶段深度、并发数量和重复冷却配置化。对话/文本使用本地化键。

## 8. 表现及可观测性

任务日志显示阶段、期限、失败原因、奖励状态；对话可见条件与失败提示一致。

**性能与诊断：** 按事件类型与 actor ID 索引活跃任务；日结扫描到期队列而非全历史。

## 9. 验收用例

| 测试 ID | 需求 ID / 质量门禁 | Given（前置） | When（操作） | Then（判据） |
|---|---|---|---|---|
| T-QUEST-01 | QST-01 | 多阶段交付/护送有时限 | 事件和期限触发 | 合法分支、完成或过期 |
| T-QUEST-02 | QST-02 | 发布者死亡、同一事件重复重放 | 推进 | 替代或失败，奖励仅一次 |
| T-QUEST-03 | QST-03 / MOD-01 / MOD-02 | 分别创建剧情和沙盒 | 完整主线、失败恢复、继续 | 剧情可继续，沙盒无强制任务 |
| T-QUEST-04 | QST-04 | 对话显示后角色或价格变化 | 选择 | 重新校验，失败不扣资源 |
| T-QUEST-05 | QST-05 | 多年仿真、地区资源枯竭 | 生成任务 | 不产生不可达任务或无限积累 |

## 10. 完成条件与实施约束

- 公开接口与本模块数据所有权已落地；所有配置通过内容编译或启动校验。
- 本章测试及受影响跨模块验收通过，保留实际运行报告；没有已知的状态一致性/权限阻断缺陷。
- 接口或存档结构变化同步契约、迁移与 ADR；性能目标需在指定基准上测量，不以空场或 mock 数据代替。
- 实现和测试变更限于本模块及获准契约；不得把尚未实现的部分伪装成已完成。

## 文档导航（镜像目录）

- 主要实现目录：`game/campaign/quest/`；权威设计：本文件。
- 上级入口：[上级模块 / 分组](../README.md)；[全部模块索引](../../../README.md)。
