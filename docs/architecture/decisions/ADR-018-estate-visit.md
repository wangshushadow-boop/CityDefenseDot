# ADR-018 · 柳溪庄总督会面与庄簿委托

2026-11-25，负责人选择「拜访柳溪庄总督并办委托：延续上次的庄邑，找到实际在任者、交谈、接事和回报」。仅 P5-VISIT 及其执行任务提前通过 GATE-P4 的排期限制，依赖已验收 P4-GOV 和 P3-CHR。引擎、主语言和外层会话/存档协议沿用原版。

从柳溪庄治理页进入庄署，在场名册以实际现任为准，选择该人物并会面。采用城镇菜单直达人物的做法，显示既有角色的姓名和三维外观。玩家可了解庄务、接「核对庄簿」、查看任务簿，再与同一位总督回报。参考[开发商的城镇人物访问说明](https://www.taleworlds.com/en/Games/Bannerlord/Blog/67)和[领地事务与任务设计](https://www.taleworlds.com/en/Games/Bannerlord/Blog/106)。庄邑、对白、委托、奖励及数值为本项目原创，范围为庄署会面。

## 权威行为

家主健康且在家可拜访。世界只有一份庄簿委托，完成后留档；逾期、人物死亡/退出家主职位、发布者离任等会留下明确终止理由，失败后隔日至少一天允许再接。接事当天 D，仅核对 D+1 的首份真实日结。游戏日 D+3 结束前可回报，D+4 开始逾期。核对问题为该日繁荣实际增加多少（含封顶，以十分之一点整数提交）。答错可重新查簿，没有奖励。正确回报生成完成记录；独立领取 60 单位管理技能使用经验，只给予原承办人。已经签结且尚未领取的奖励可在任务簿领取，不要求原发布者仍在任。已经换代或死亡且未领的承办人不能将个人经验转给别人。处于暂时伤病或囚禁时保留未到期任务，不能会面或领取。

## 跨模块端口

继续使用现有 character 命令封装、幂等修订和世界原子写盘。受权操作 visit_accept、visit_report 的参数分别为 {settlement_id,hero_id}、{settlement_id,hero_id,answer}；visit_claim 为 {}。每次提交重新核验。知会/退出属于只读会面。UI 不持有权威任务、经验、NPC 或日结。

QUEST 的 game/campaign/quest/ports/estate_commission.gd 提供 plan(state,op,args,facts) → Result（value 为新 state）、reconcile(state,facts) → 新 state、validate(state,facts) → Result、view(state,facts) → 人物读模型 visit。每份非空 state 必含 schema_version=1、status、actor_id、issuer_id、settlement_id、accepted_day、deadline_day、ledger、ended_day、reason、rewarded。状态 active、ready、completed、expired、failed；空表示从未承办。ledger 为空或为 D+1 原始完整日结的副本。completed 搭配 rewarded 区分签结和领取。临时失格不改写历史。终态日期和身份可验证；首次日结一旦锁定不被后天覆盖。

facts 包含 world_id、day、player_id（可空）、can_visit、members（英雄 ID 到 {name,appearance,life_status} 的字典）、settlement_id（未接管为 null）、governor_id（可空）、last_report。CHR 提供 visit_people(repo) → {player_id,can_visit,members}，SET 事实通过既有公开 view，CAMP 组合输入。CHR 提供 commission_reward(repo,actor_id,source,day) → Result（新人物仓库）与 validate_commission_reward(repo,actor_id,source,rewarded) → Result。QUEST.reward_source(state) 从有效承办人与接事日派生稳定保留标识，统一前缀 quest/liuxi/；空状态使用空字符串。CAMP 拒绝一般 outcome 占用该来源。CAMP 对领取调用两域，一次持久化任务、XP 和回执。可选世界字段 estate_commission，显式空、未知版、悬空身份、不一致的任务/经验收据拒载。P4 旧档缺字段即没有接过委托，无追算。

CHR 用人物仓库的可选 estate_reward={actor_id,source} 记录这一次亲办委托的经验来源。成长沿用原有学习曲线。该字段由 CAMP 冷恢复时与任务签结/领取标志相互核对。旧版本普通人物事件曾允许任意来源字符串，原有来源与经验完整保留。

visit 读模型含 settlement_id、can_visit、speaker（null 或 {id,name,appearance}）、status（未接时 none）、actor_id、issuer_id、accepted_day、deadline_day、ledger、reason、rewarded、can_accept、can_report、can_claim、answers（规范整数数组；有效回报时三个备选）。尚未接时以 null 表示日期和身份。交互入口从治理页「拜访庄署」，支持真实鼠标、键盘、查簿和返回。推进游戏日复用正式 rest。项目其他 P5 任务及完整城镇自由行走留在原有计划。

终审补充。首次记录时，QUEST 同时保存规范庄簿的 SHA-256（ledger_hash）。SET 开放其既有日报算式的只读核验，CAMP 向任务提供 opened_day 及原发布者有效管理/统御。接事日期必须不早于开庄；相邻日存在时核对前日结余和次日起账；真实领地能力限定历史贡献上界。
