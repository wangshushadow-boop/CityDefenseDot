# SERVER-D — 专用权威战斗服务器

> 版本 0.1（设计内容未变；目录版 0.2） | 状态：详细设计提案，待评审与实现 | 所属工程：recollection（古代中国风原创沙盒）
> 实现目录：`server/dedicated/` | 总体基线：[§16.1、§16.2、§19、§20](../../../game_design.md) | [系统索引](../../README.md)

本文在总体规格书约束内补充实现级设计。接口为语言无关伪代码，字段及新增参数为拟定契约；未标明已冻结的数值需经 ADR/测试确认。公共语义见[公共契约](../../../architecture/common_contracts.md)。测试均为待执行规格，不代表功能已实现。

## 1. 职责与边界

独立 headless 进程，启动专服配置，管理 Mission 赛局、连接/玩家席位、权威 tick、地图轮换与服务器状态。共用 game 的 Mission/Combat/Formation/Rule，不复制服务端战斗逻辑。

**协作边界：** BOOT/MP/NET/MIS-RT/RULES、SERVER-L 服务 API、TELEM。跨模块写入经 application 或权威运行时编排；不直接访问其他模块私有仓库。

## 2. 数据所有权与生命周期

ServerInstance、MatchRuntime、AdmissionState、健康/赛果提交队列；赛局内真值归 Mission。

## 3. 代码组织

以下为建议的文件职责（按选定语言补扩展名；不是已有源码）：

```text
dedicated_main / server_config
match_host / admission / tick_loop
map_rotation / admin_console
result_submitter / health_probe / shutdown_drain
```

## 4. 数据模型与约束

`ServerConfig{region,capacity,ai_limit,tick_rate,content_hash,modes,admin_roles,ranking_policy}`；`MatchAssignment{match_id,ruleset,scene,seed,seat_tokens,expires}`；`ServerHealth{active_match,players,tick_p95,queue,version}`。

## 5. 公共接口

```text
StartDedicated(config) -> Result<ServerId>
AcceptAssignment(assignment) -> Receipt
AdmitPlayer(ticket,identity) -> Result<Seat>
RunMatchTick() -> TickReport
FinalizeMatch() -> Result<ServerMatchResult>
DrainAndShutdown(reason) -> ShutdownReport
```

所有修改型接口须在所属权威阶段提交；查询不推进时间。命令失败遵循公共错误码；空结果与非法输入分开。非幂等的外部请求须使用稳定请求 ID 或事务回执。

## 6. 核心算法与运行流程

启动 headless 装配与内容校验→注册服务器健康/容量→接受匹配分配或自托管房间→验证票据→加载 Mission→固定 tick 权威执行→结束生成签名/认证结果→可靠重试提交→释放资源/下一地图。停机先停止新连接，允许当前赛局按配置完成或明确终止；崩溃记录结果是否已提交，避免重发奖励。

## 7. 配置、异常与安全边界

管理员权限、地图轮换、玩家容量、友伤/重生规则和官方/私服排名隔离；官方赛果只接受可信服务端。服务端不创建 GPU/音频。凭证不入日志。

## 8. 表现及可观测性

管理员控制台/健康查询；玩家连接和赛局状态由 MP/UI 展示。

**性能与诊断：** 监测 tick、CPU、内存、掉线率、输入队列；按实例独立扩容。

## 9. 验收用例

| 测试 ID | 需求 ID / 质量门禁 | Given（前置） | When（操作） | Then（判据） |
|---|---|---|---|---|
| T-SERVER-D-01 | NET-01 | 无显示/GPU 设备 | 运行专服 Mission | 与单人同规则，真实权威模拟 |
| T-SERVER-D-02 | NET-05 | 专服崩溃或赛果重复提交 | 重启/重试 | 状态明确，奖励不重复 |
| T-SERVER-D-03 | NET-06 | 64/128 真人和约定 AI | 压测 | tick、带宽、内存符合冻结容量目标 |

## 10. 完成条件与实施约束

- 公开接口与本模块数据所有权已落地；所有配置通过内容编译或启动校验。
- 本章测试及受影响跨模块验收通过，保留实际运行报告；没有已知的状态一致性/权限阻断缺陷。
- 接口或存档结构变化同步契约、迁移与 ADR；性能目标需在指定基准上测量，不以空场或 mock 数据代替。
- 实现和测试变更限于本模块及获准契约；不得把尚未实现的部分伪装成已完成。

## 文档导航（镜像目录）

- 主要实现目录：`server/dedicated/`；权威设计：本文件。
- 上级入口：[上级模块 / 分组](../README.md)；[全部模块索引](../../README.md)。
