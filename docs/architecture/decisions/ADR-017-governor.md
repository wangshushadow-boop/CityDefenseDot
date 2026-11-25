# ADR-017 · 沙盒家族总督与领地日结

2026-11-25，负责人选择「P4 总督治理：从已有家族成员中任命总督，让人物能力实际影响领地日结」，同时授权补齐此流程的必要前置。此前 P3 已交付人物与家户。此次只提前放行列在执行计划中的总督任务。GATE-P3、完整 P4-SET 和其余社会工作包维持原门禁。

## 玩家操作

在「人物 → 领地治理」主动接管一处原创的家族庄邑「柳溪庄」。旧档在接管前不追算，接管记录以当前战役日为起点。家族庄邑是本沙盒治理入口，接管不授予王国封臣身份、军队或金钱。当前有行动能力的家主可任免；可选人来自现有家户，须成年、非家主、在家、健康或负伤。不能兼任出征兵源，被俘、调往他处、死亡、继为家主或家族生涯结束时职位自动空缺。轻伤可任职。参考[开发商对总督职责的说明](https://www.taleworlds.com/en/Games/Bannerlord/Blog/89)。

## 权威与兼容

沿用 character 的已鉴权命令封装、幂等回执、战役时钟与原子存档。新增操作 governor_open（空参数）、governor_assign（settlement_id、hero_id）、governor_dismiss（settlement_id）。推进一日复用 rest。CHR 提供 governor_facts(repo,day)，结构为 clan_id、can_manage、members；每个成员含 id、name、eligible、reason、stewardship、leadership。数值取既有人物的 settlement 作用域有效管理与统御。SET 唯一持有领地、归属、总督及上次日结，人物不保存第二份任职。

SET 的纯端口位于 game/campaign/settlement/ports/governance.gd。plan(state,op,args,world,day,facts)、daily(state,day,facts)、validate(state,world,day,facts) 返回 Result；reconcile(state,facts) 与 view(state,world,day,facts) 返回字典。state 为空表示尚未接管。CAMP 在世界快照的可选 governance 字段保存非空 v1；显式空值、未知版本、错误家族、越界游标或悬空现任拒载。日结在原有事务与人物恢复一起公布，失败均回滚。

人物读模型新增 governance。字段 established、can_manage、settlement_id、name、owner_clan_id、governor_id、candidates、prosperity、loyalty、last_day、last_report。现任可空。候选行使用上述成员字段，原因使用中文。指标单位为十分之一点，范围 0–1000；last_report 为空或含 day、governor_id、prosperity_before/after、loyalty_before/after、prosperity_base、loyalty_base、prosperity_bonus、loyalty_bonus。基础变化与在任人物技能贡献分别展示，上下限使用实际结算。接管时两项均为 500；每日繁荣基础 +1、忠诚基础 −1；有人任职时繁荣加 1+有效管理、忠诚加 1+有效统御。跨任期的历史日结保留当日实际人物和分项。数值及名称为本项目原创默认，可经测试调整。

当前条件下的下一日预测 next_report 与 last_report 同形。未接管时两项均为空；预测与提交共享同一结算函数。
