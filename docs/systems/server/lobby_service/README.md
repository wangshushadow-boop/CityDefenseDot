# SERVER-L — 大厅后端、身份、匹配与赛果

> 版本 0.1（设计内容未变；目录版 0.2） | 状态：详细设计提案，待评审与实现 | 所属工程：recollection（古代中国风原创沙盒）
> 实现目录：`server/lobby_service/` | 总体基线：[§16.1、§16.3、§16.4、§20](../../../game_design.md) | [系统索引](../../README.md)

本文在总体规格书约束内补充实现级设计。接口为语言无关伪代码，字段及新增参数为拟定契约；未标明已冻结的数值需经 ADR/测试确认。公共语义见[公共契约](../../../architecture/common_contracts.md)。测试均为待执行规格，不代表功能已实现。

## 1. 职责与边界

在线控制平面：账号或平台身份、会话、服务器目录、匹配分配、赛果、排名和处罚。可以先单后端服务模块化实现；不参与实时物理模拟、不持有单人世界。

**协作边界：** CON、MP/NET 服务端口、SERVER-D、平台身份 SDK 与持久化数据库适配。跨模块写入经 application 或权威运行时编排；不直接访问其他模块私有仓库。

## 2. 数据所有权与生命周期

AccountRef、Session、ServerRegistration、MatchTicket、Allocation、MatchResultReceipt、Penalty；外部身份只存必要引用。

## 3. 代码组织

以下为建议的文件职责（按选定语言补扩展名；不是已有源码）：

```text
identity / session_token / server_directory
lobby_service / party_group / matchmaking
allocation / ticket_signing / heartbeat
result_store / ranking / moderation / audit
storage_adapter / privacy_controls
```

## 4. 数据模型与约束

`ServerRegistration{id,region,version,content_hash,capacity,heartbeat}`；`Ticket{id,account_ref,match_id,server_id,expiry,nonce}`；`ResultRecord{match_id,server_id,integrity_hash,outcome,received_at}`；唯一键 match_id，认证服务器可重复查询回执。

## 5. 公共接口

```text
Authenticate(platform_proof) -> Result<Session>
RegisterServer(server_proof,health) -> Receipt
SearchServers(filters) -> ServerList
EnqueueMatch(ticket) -> Result<MatchTicketId>
AllocateMatch(compatible_tickets) -> MatchAssignment
SubmitResult(authenticated_server,result) -> MatchReceipt
Report / Moderate / Appeal(...) -> Receipt
```

所有修改型接口须在所属权威阶段提交；查询不推进时间。命令失败遵循公共错误码；空结果与非法输入分开。非幂等的外部请求须使用稳定请求 ID 或事务回执。

## 6. 核心算法与运行流程

认证→签发短期令牌→目录健康心跳/容量→按模式、地区、延迟、内容、组队和队伍平衡匹配→预留服务器座位→签发限时入场票据。赛果校验服务端身份、match_id 和完整性，原子保存结果与排名变化，重复返回原回执。私人服务器目录和官方排名隔离。处罚有证据、审计和申诉。

## 7. 配置、异常与安全边界

加密传输、令牌过期/撤销、权限分级、速率限制、个人数据最小化和保留策略；后端故障时本地/私人模式可独立运行。匹配策略及排名规则需产品评审。

## 8. 表现及可观测性

无独立界面；通过公开查询、回执或已提交事件提供可观察结果。

**性能与诊断：** 监测匹配 P95、服务器健康、认证失败、结果写入和分配超时；数据库索引唯一性。

## 9. 验收用例

| 测试 ID | 需求 ID / 质量门禁 | Given（前置） | When（操作） | Then（判据） |
|---|---|---|---|---|
| T-SERVER-L-01 | NET-02 | 跨地区、不同版本的匹配请求 | 分配 | 仅兼容且满足容量的玩家匹配 |
| T-SERVER-L-02 | NET-05 | 重复或不可信服务器结果 | 提交 | 去重或拒绝，无重复排名奖励 |
| T-SERVER-L-03 | NET-06 | 权限/隐私/处罚操作 | 测试 | 越权拒绝、审计和最小数据收集 |

## 10. 完成条件与实施约束

- 公开接口与本模块数据所有权已落地；所有配置通过内容编译或启动校验。
- 本章测试及受影响跨模块验收通过，保留实际运行报告；没有已知的状态一致性/权限阻断缺陷。
- 接口或存档结构变化同步契约、迁移与 ADR；性能目标需在指定基准上测量，不以空场或 mock 数据代替。
- 实现和测试变更限于本模块及获准契约；不得把尚未实现的部分伪装成已完成。

## 文档导航（镜像目录）

- 主要实现目录：`server/lobby_service/`；权威设计：本文件。
- 上级入口：[上级模块 / 分组](../README.md)；[全部模块索引](../../README.md)。
