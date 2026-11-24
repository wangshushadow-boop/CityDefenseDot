# CHR — 英雄、成长、装备与生命状态

> 版本 0.1（设计内容未变；目录版 0.2） | 状态：详细设计提案，待评审与实现 | 所属工程：recollection（古代中国风原创沙盒）
> 实现目录：`game/campaign/character/` | 总体基线：[§5.1、§5.3、§11、§17](../../../../game_design.md) | [系统索引](../../../README.md)

本文在总体规格书约束内补充实现级设计。接口为语言无关伪代码，字段及新增参数为拟定契约；未标明已冻结的数值需经 ADR/测试确认。公共语义见[公共契约](../../../../architecture/common_contracts.md)。测试均为待执行规格，不代表功能已实现。

## 1. 职责与边界

英雄身份、出生、外观、属性技能、天赋、生命/伤病、装备配置与成长事件。普通士兵定义在 DEF，名册在 PARTY；家族谱系在 CLAN；人物位置由 WORLD/APP 协调，不能有两个有效位置。

**协作边界：** DEF/CON/SHRULE、INV；通过 CLAN/PARTY/POL 查询与 APP 事务更新。跨模块写入经 application 或权威运行时编排；不直接访问其他模块私有仓库。

## 2. 数据所有权与生命周期

Hero 权威持久实例；Character 拥有 skills、perks、life_status、equipment_refs 和外观；家族和队伍持成员引用；健康与位置的战役变更只在合法事务。

## 3. 代码组织

以下为建议的文件职责（按选定语言补扩展名；不是已有源码）：

```text
hero / hero_factory / character_creation
attribute_set / skill_progress / perk_tree
loadout / equip_handler / effect_resolver
health / recovery / life_transition
character_queries
```

## 4. 数据模型与约束

`Hero{id,def_id,clan_id?,birth_time,traits,attributes,skills,perks,equipment_refs,location_ref,life_status}`；`SkillProgress{level,xp,focus}`；`PerkDef{prerequisites,exclusive_group,scope,effects}`；`Loadout{combat_slots,civil_slots}`；`LifeStatus=Healthy|Wounded|Captive|Dead|Retired`（囚禁与伤病正交字段，主状态为派生摘要）。死亡终态不可普通入队。

## 5. 公共接口

```text
CreateHero(background_choices, appearance) -> Result<HeroId>
GrantSkillXp(hero, source_event, skill, amount) -> ChangeSet
SelectPerk(hero, perk_id) -> Receipt
EquipHero(hero, slot, item_ref, profile) -> ChangeSet
ApplyHeroOutcome(hero, outcome, result_id) -> ChangeSet
step_recovery(day_id, context) -> Changes
GetCharacterEffects(hero, scope) -> EffectBreakdown
```

所有修改型接口须在所属权威阶段提交；查询不推进时间。命令失败遵循公共错误码；空结果与非法输入分开。非幂等的外部请求须使用稳定请求 ID 或事务回执。

## 6. 核心算法与运行流程

角色创建校验文化、年龄、背景选择→计算属性技能和起始装备→分配唯一 ID/账本。经验事件先去重，按行为量×学习系数×衰减计算，累积越阈值升级；天赋检查前置、互斥、点数、作用域。装备原子转移库存实例到槽位，旧装备退回，预览与提交一致。战斗结果经 ENC 映射伤病/俘虏/死亡，恢复由医术、休养与时间计算；死/退休触发 CLAN 合法继承用例。

## 7. 配置、异常与安全边界

`xp_curve`、`learning_rate`、`wound_recovery`、`death_policy` 从定义读取；同一来源事件不可重复发放 XP。年龄/亲缘限制在 CLAN；难度通过权威规则而非 UI 改生命。技能作用域明示来源与叠加顺序。

## 8. 表现及可观测性

角色创建/人物面板显示技能成长、天赋冲突、作用域、装备需求与伤病原因。

**性能与诊断：** 技能和效果按版本缓存；日恢复按活动英雄索引，不在每帧重复计算。

## 9. 验收用例

| 测试 ID | 需求 ID / 质量门禁 | Given（前置） | When（操作） | Then（判据） |
|---|---|---|---|---|
| T-CHR-01 | CHR-01 | 角色技能经验跨升级阈值 | 重复提交同来源 | 升级一次，互斥天赋不能同时选取 |
| T-CHR-02 | CHR-02 | 装备需双手或骑乘且库存不足 | 换装 | 拒绝或原子交换，无物品复制 |
| T-CHR-03 | CHR-03 | 英雄已被俘且受伤 | 恢复、入队、死亡 | 主状态和位置合法，死亡不可复活 |
| T-CHR-04 | CLN-03 | 玩家英雄退休 | 执行继承 | 新的玩家控制器绑定合法继承人，装备按归属迁移 |

## 10. 完成条件与实施约束

- 公开接口与本模块数据所有权已落地；所有配置通过内容编译或启动校验。
- 本章测试及受影响跨模块验收通过，保留实际运行报告；没有已知的状态一致性/权限阻断缺陷。
- 接口或存档结构变化同步契约、迁移与 ADR；性能目标需在指定基准上测量，不以空场或 mock 数据代替。
- 实现和测试变更限于本模块及获准契约；不得把尚未实现的部分伪装成已完成。

## 文档导航（镜像目录）

- 主要实现目录：`game/campaign/character/`；权威设计：本文件。
- 上级入口：[上级模块 / 分组](../README.md)；[全部模块索引](../../../README.md)。
