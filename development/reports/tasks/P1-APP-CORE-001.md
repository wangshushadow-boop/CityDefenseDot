# P1-APP-CORE-001 应用层会话与跨域提交

**CANDIDATE**。p1con 开发，独立 worktree `.worktrees/p1-application`，detached HEAD 基线 `98a64dd017cca657992c2680dad7e4f2dd45f6b3`。适用 APP SDD v0.1、公共契约、ADR-012/013、GDD §2.3、§10.2、§17.5。关联 BAT-03/04/05、MOD-01/02/03。候选 diff 交由主 Agent 集成。

## 实现

`game/application/game_session.gd` 是模式、状态、持有的运行时、命令与赛果回执的唯一应用写入方。装配根注入存储实例、CAMP/Mission 工厂、可信身份与业务权限解析器、战役结算规则、联网赛果接收端。创建、加载、保存、只读查询、合法命令、战前检查点、固定步、结束、路由、释放、暂停和关闭均经同一会话。源码只静态引用 CON 与 APP 内部代码。

命令先由注入的可信上下文验证 actor 与所请求的具体操作，再按当前 world scope 和 actor、command_id 查找规范请求摘要，最后对新写入检查 expected_revision。CAMP.exchange 在 INV 发布前将候选世界和 APP 回执交给 PERSIST，commit marker 与业务快照通过同一个提交发布。相同 ID 改包返回 Conflict。PERSIST 回执丢失时 APP 重读槽，只有实际可见的快照等于候选值时才承认已发布。调用方可以重发并得到先前的 CommandReceipt。

战役准备时冻结 CAMP，写入战前检查点后调用真实 Mission.prepare。资源失败会释放运行时资源、恢复安全点和地图状态。Mission.finalize 验证后的权威结果先进入持久待结算记录。磁盘失败时保留同一个待写结果，拒绝关闭/释放导致的丢弃，恢复 I/O 后可重试。冷加载会恢复 Results 或撤销未完成的战前预留。战役使用注入的规则生成可信奖励行，再用真实 INV 和原子提交同时关闭预留、转账、保存回执。自定义战斗回执留在当前会话，多人提交至注入的赛局接收端。两者不写战役存档。

`receipt_book.gd` 支持已保存的小型平铺账簿。大型账簿按稳定摘要顺序写入最多 4,096 项的页，目录支持分层，加载时恢复去重索引并拒绝重复键。针对 scope/actor/命令身份分别建键，应用快照的存储 revision 与 CAMP revision 分开维护。

## 实际验证

Windows、Godot 4.7.2 Standard `ed1daf0bf`，真实 CAMP、INV、MIS-RT、引擎适配器与磁盘 PERSIST。确定性种子为 `1234567890abcdef`。专属 fixture 只提供起始资源、测试内容、身份、规则与最小结果生产器。测试用 `G` 为 `D:/Program/Godot/Standard/Godot_v4.7.2-stable_win64_console.exe`，各运行隔离用户目录。

| ID | 实际命令 | 退出 | 结果 |
|---|---|---:|---|
| T-APP-01 / AT-10 基础切片 | `G --headless --path game --script res://tests/p1/application/run.gd` | 0 | PASS。实际兑换后钱包 98、奖励池 1,000。真实战前冻结、检查点、场景准备、固定一步、Mission 权威结果与持久待结算完成后，在写前、提交标记前及标记后分别注入故障。冷启动前两者仍待结算，后者已到账。重发后钱包 105、奖励池 993，命令及结果回执各一条，相同赛果返回原回执，改包拒绝。 |
| T-APP-02 | 同上 | 0 | PASS。加载已结算战役后进入自定义和多人最小战场，各经实际结束、路由与释放回到地图。战役快照 SHA-256 不变，多人接收端仅调用一次。 |
| T-APP-03 | 同上 | 0 | PASS。真实资源路径加载失败，返回原地图 revision 和视图，预约及引擎 scopes、requests、leases 都归零。另实测空 CAMP factory 创建/加载失败后，同一会话可重试。实际 Mission 已完成而待结算结果首次持久化失败时，close/dispose 被拒，恢复 I/O 后可由原会话记录并冷启动完成。另实际构造无 result_builder 的 MIS，确认 finalize 未产生候选时可分别 dispose/close 并释放所有范围与租约，冷加载回地图。 |
| T-APP-04 基础切片 | 同上 | 0 | PASS。剧情和沙盒均可创建、进入 CampaignMap，实际会话策略选择中仅剧情启用主线标记。完整剧情内容、角色成长及沙盒长期游玩 NOT_RUN。 |
| APP-ARCHIVE | `G --headless --path game --script res://tests/p1/application/archive.gd` | 0 | 65,537 条应用记录分为 17 页，完整规范编码、恢复首末回执和重复页拒绝。 |
| 编译 | `G --headless --path game --script res://application/game_session.gd --check-only` | 0 | 公开会话脚本实际编译成功。 |

主要入口最终输出 `APP_CHECKS errors=0`。独立 QA 另报告 33 项身份与命令边界通过，65,537 条记录在其测试中编码为 16,515,388 字节；其审查与阶段证据由主线程归档。

## 范围与交付

AT-10 的实际结算证据针对 P1 可运行切片。完整 ENC 兵源、RESULTS 战斗统计、正式多人认证及后续玩法未执行。测试中的奖励额度由可信测试规则配置。故障模拟使用 PERSIST 实际文件路径和提交阶段，开发自测冷启动指新会话重新读取磁盘。实机断电及跨进程阶段复验由对应独立门禁记录。

授权差异为 `game/application/{game_session.gd,receipt_book.gd}`、`game/tests/p1/application/{fixture.gd,run.gd,archive.gd}` 及本报告。未改共享状态、架构文档或其他模块。独立审查、跨模块最终验收和任务状态由主 Agent 记录。
