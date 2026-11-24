# MP — 多人会话、大厅、匹配与模式组装

> 版本 0.1（设计内容未变；目录版 0.2） | 状态：详细设计提案，待评审与实现 | 所属工程：recollection（古代中国风原创沙盒）
> 实现目录：`game/multiplayer/` | 总体基线：[§1.2、§16.1–16.4、§20](../../../game_design.md) | [系统索引](../../README.md)

本文在总体规格书约束内补充实现级设计。接口为语言无关伪代码，字段及新增参数为拟定契约；未标明已冻结的数值需经 ADR/测试确认。公共语义见[公共契约](../../../architecture/common_contracts.md)。测试均为待执行规格，不代表功能已实现。

## 1. 职责与边界

负责多人用户会话、账号/平台身份端口、房间、服务器目录、匹配、选队/装备、加入/重连、模式装配、赛果路由和管理功能；联网协议由 NET，战斗规则由 RULES，服务器部署由 SERVER。明确不承诺多人共用持久战役。

**协作边界：** CON/CORE、NET、APP/MIS-RT/RULES/FORM 公共接口、SERVER 服务 API。跨模块写入经 application 或权威运行时编排；不直接访问其他模块私有仓库。

## 2. 数据所有权与生命周期

`NetworkSession`、LobbyState、MatchTicket、PlayerSeat、MatchState、ModerationState；排名/赛季由后端保存，非战役资产。

## 3. 代码组织

以下为建议的文件职责（按选定语言补扩展名；不是已有源码）：

```text
session/network_session / identity_port
lobby / party_group / matchmaking / server_browser
match_setup / seat_assignment / team_balance / reconnect
mode_factory / match_result_router
moderation / report / chat_voice_policy
```

## 4. 数据模型与约束

`LobbyState{id,region,mode,players,ready,content_hash}`；`MatchTicket{id,party,region,mode,latency,expires}`；`PlayerSeat{account_ref,team,role,formation_grant?,reconnect_token}`；`MatchState=Lobby|Allocating|Joining|Running|Ending|Completed|Cancelled`。

## 5. 公共接口

```text
Authenticate(provider_token) -> Result<IdentitySession>
CreateLobby / JoinLobby / Ready(...) -> Receipt
FindMatch(ticket) -> Result<MatchAssignment>
JoinMatch(server_ticket,role) -> Result<PlayerSeat>
Reconnect(match,token) -> Result<PlayerSeat>
SubmitMatchResult(server_result) -> Result<MatchReceipt>
ReportPlayer / Mute / Block(...) -> Receipt
```

所有修改型接口须在所属权威阶段提交；查询不推进时间。命令失败遵循公共错误码；空结果与非法输入分开。非幂等的外部请求须使用稳定请求 ID 或事务回执。

## 6. 核心算法与运行流程

认证→组队/选择地区模式→匹配/服务器列表→分配专服→握手内容和协议→选队/角色预算→运行 Mission；队长模式分配编队授权，死亡后重生/观战按规则。中途加入/重连恢复合法 seat，不重复队伍或奖励；比赛结束服务端提交唯一 match_id，排名仅官方可信服务器。私人服务器可自托管规则和日志，与官方排名隔离。聊天/语音提供静音屏蔽举报，权限审计和处罚申诉。

## 7. 配置、异常与安全边界

地区/延迟/容量/超时配置；令牌加密传输、短时效、不可日志；内容哈希不一致拒绝。服务故障允许私人服务器正常本地模式，官方排名明确不可用；作弊判定与处罚保留审计，不将客户端完整文件扫描设默认。

## 8. 表现及可观测性

大厅、服务器列表、地图投票、选队装备、比分、观战、举报和连接状态。

**性能与诊断：** 跟踪匹配等待、重连率、赛果重试、队列与专服健康；容量以真实压测。

## 9. 验收用例

| 测试 ID | 需求 ID / 质量门禁 | Given（前置） | When（操作） | Then（判据） |
|---|---|---|---|---|
| T-MP-01 | MOD-04 / NET-02 | 各多人模式、匹配和目录 | 加入/完成 | 规则组装、阵营和结果正确 |
| T-MP-02 | NET-03 | 中途断线 | 重连 | 原 seat 恢复或按规则超时，无重复角色 |
| T-MP-03 | NET-05 | 服务不可用、重复赛果 | 处理 | 私人服务器继续；官方重复结果不发奖 |
| T-MP-04 | NET-06 | 举报/静音与账号隐私 | 测试 | 权限审计和隐私符合约束 |

## 10. 完成条件与实施约束

- 公开接口与本模块数据所有权已落地；所有配置通过内容编译或启动校验。
- 本章测试及受影响跨模块验收通过，保留实际运行报告；没有已知的状态一致性/权限阻断缺陷。
- 接口或存档结构变化同步契约、迁移与 ADR；性能目标需在指定基准上测量，不以空场或 mock 数据代替。
- 实现和测试变更限于本模块及获准契约；不得把尚未实现的部分伪装成已完成。

## 文档导航（镜像目录）

- 主要实现目录：`game/multiplayer/`；权威设计：本文件。
- 上级入口：[上级模块 / 分组](../README.md)；[全部模块索引](../../README.md)。
