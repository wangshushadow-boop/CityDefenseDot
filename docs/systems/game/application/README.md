# APP — 应用层、GameSession 与事务

> 版本 0.1（设计内容未变；目录版 0.2） | 状态：详细设计提案，待评审与实现 | 所属工程：recollection（古代中国风原创沙盒）
> 实现目录：`game/application/` | 总体基线：[§2.3、§3、§10.2、§17.5、§20](../../../game_design.md) | [系统索引](../../README.md)

本文在总体规格书约束内补充实现级设计。接口为语言无关伪代码，字段及新增参数为拟定契约；未标明已冻结的数值需经 ADR/测试确认。公共语义见[公共契约](../../../architecture/common_contracts.md)。测试均为待执行规格，不代表功能已实现。

## 1. 职责与边界

负责游戏模式生命周期、用例编排、命令鉴权路由、跨域事务、EncounterSpec 到 MissionResult 的转换与 ResultRouter；UI/AI/网络共享同一合法业务入口。不得成为巨型业务逻辑类，具体伤害/价格/外交由领域规则计算。

**协作边界：** CORE/CON、Campaign/Mission 公共门面、Persistence/Content/Engine 端口、MP 会话。跨模块写入经 application 或权威运行时编排；不直接访问其他模块私有仓库。

## 2. 数据所有权与生命周期

Session 独占当前 CampaignRuntime（可空）、MissionRuntime（最多一个）、NetworkSession（按模式）；负责权限上下文、状态机、事务提交序号与回执缓存。

## 3. 代码组织

以下为建议的文件职责（按选定语言补扩展名；不是已有源码）：

```text
game_session / session_state_machine
use_cases/ (world, party, trade, politics, quest, encounter)
command_router / authority_context
transaction_coordinator / change_set / receipt_cache
mission_launcher / result_router / recovery
```

## 4. 数据模型与约束

`SessionState` 使用 §2.3 的 Boot/Frontend/NewWorld/LoadWorld/CustomSetup/MultiplayerLobby/CampaignMap/Encounter/LoadingMission/Mission/Results/Recovery；`ChangeSet{expected_versions, operations[], events[], invariant_checks}`；`TransactionReceipt{command_id,revision,outcome}`。战役事务单写序，提交前全量校验写集；写入 revision 与去重 ID 同一原子边界。

## 5. 公共接口

```text
start_session(mode, options) -> Result<SessionId>
dispatch(CommandEnvelope, AuthorityContext) -> CommandReceipt
query(Query, VisibilityContext) -> ReadModel
prepare_mission(encounter_or_mode_spec) -> Result<MissionId>
route_result(MissionResult) -> Result<SettlementReceipt>
request_pause(reason) -> Result<Unit>
close_session(reason) -> Result<Unit>
```

所有修改型接口须在所属权威阶段提交；查询不推进时间。命令失败遵循公共错误码；空结果与非法输入分开。非幂等的外部请求须使用稳定请求 ID 或事务回执。

## 6. 核心算法与运行流程

命令 → 权限/版本校验 → 领域处理器准备写集 → 验证资源和跨域不变量 → 统一提交 → 发布事件/回执。Mission 开始先预留和保存战前检查点；加载失败解除预留或恢复检查点。战役结果进入 Encounter；自定义结果只展示/本地统计，多人只进入赛局结果服务。加载/退出有取消令牌，状态跃迁用白名单拒绝。世界暂停不停止 UI；联网客户端不可暂停权威 tick。

## 7. 配置、异常与安全边界

同 command_id 与同 payload 重试返回原回执；同 ID 不同内容 Conflict。未完成结算必须保留待提交结果；跨域一致性不靠无序事件监听。安全点存档见 PERSIST；处理异常只回滚未提交事务，不撤销已持久结果。

## 8. 表现及可观测性

所有界面通过 Query/Command；禁用非法按钮并返回明确原因，不以 UI 预校验替代权威校验。

**性能与诊断：** 命令延迟、拒绝率、跨域写集大小、加载取消、结果重试及状态转换记录。

## 9. 验收用例

| 测试 ID | 需求 ID / 质量门禁 | Given（前置） | When（操作） | Then（判据） |
|---|---|---|---|---|
| T-APP-01 | BAT-03 | 结果已提交但回执丢失 | 重复提交同 result_id | 返回原回执，资产和 revision 不再变化 |
| T-APP-02 | BAT-04 / MOD-03 | 加载已有战役后进入自定义战斗 | 完成并退出 | 战役快照哈希不变 |
| T-APP-03 | BAT-05 | Mission 资源加载失败 | 返回地图 | 恢复旧状态、预留释放且无旧回调 |
| T-APP-04 | MOD-01 / MOD-02 | 创建剧情或沙盒 | 进入地图 | 正确注册模式规则，沙盒无强制主线 |

## 10. 完成条件与实施约束

- 公开接口与本模块数据所有权已落地；所有配置通过内容编译或启动校验。
- 本章测试及受影响跨模块验收通过，保留实际运行报告；没有已知的状态一致性/权限阻断缺陷。
- 接口或存档结构变化同步契约、迁移与 ADR；性能目标需在指定基准上测量，不以空场或 mock 数据代替。
- 实现和测试变更限于本模块及获准契约；不得把尚未实现的部分伪装成已完成。

## 文档导航（镜像目录）

- 主要实现目录：`game/application/`；权威设计：本文件。
- 上级入口：[上级模块 / 分组](../README.md)；[全部模块索引](../../README.md)。
