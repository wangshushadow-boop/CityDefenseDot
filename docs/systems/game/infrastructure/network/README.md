# NET — 网络协议、传输、权威与状态复制

> 版本 0.1（设计内容未变；目录版 0.2） | 状态：详细设计提案，待评审与实现 | 所属工程：recollection（古代中国风原创沙盒）
> 实现目录：`game/infrastructure/network/` | 总体基线：[§16.2、§16.4、§17、§19](../../../../game_design.md) | [系统索引](../../../README.md)

本文在总体规格书约束内补充实现级设计。接口为语言无关伪代码，字段及新增参数为拟定契约；未标明已冻结的数值需经 ADR/测试确认。公共语义见[公共契约](../../../../architecture/common_contracts.md)。测试均为待执行规格，不代表功能已实现。

## 1. 职责与边界

实现鉴权会话消息、可靠/不可靠通道、输入序列、快照增量、兴趣管理、预测/纠正和受限延迟补偿适配；战斗规则由同一 Mission/Combat 执行，多人产品流程归 MP。

**协作边界：** CON/CORE、MIS-RT/COM/FORM/MOV 的网络端口，MP 身份会话，平台传输 SDK。跨模块写入经 application 或权威运行时编排；不直接访问其他模块私有仓库。

## 2. 数据所有权与生命周期

ConnectionState、SequenceWindow、SnapshotBaseline、PredictionBuffer、ReplicationView、HistoricalPoseBuffer；权威生命/伤害归专服 Mission。

## 3. 代码组织

以下为建议的文件职责（按选定语言补扩展名；不是已有源码）：

```text
protocol/header / message_codec / version_handshake
transport/control / input / orders / snapshots / events / cosmetic
validation/sequence / rate_limit / authorization
replication/interest / delta / baseline
prediction/reconciliation / interpolation / lag_compensation
fault_simulation / network_metrics
```

## 4. 数据模型与约束

`PacketHeader{protocol_version,session_id,sequence,tick,ack,baseline?,message_type,length}`；`InputMessage{actor,seq,tick,intents}`；`Snapshot{server_tick,baseline,entity_deltas,objective_deltas,acked_input}`。Control/Orders/ImportantEvent 可靠或显式确认；Input 高频带冗余；Snapshot 序列与基线确认；Cosmetic 可丢弃。

## 5. 公共接口

```text
handshake(identity,protocol,content_hash) -> Result<ConnectionId>
receive_input(connection,msg) -> IntentReceipt
receive_order(connection,order) -> OrderReceipt
build_snapshot(connection,interest,baseline) -> Snapshot
apply_authoritative_snapshot(snapshot) -> ReconciliationReport
query_history(server_validated_tick,limit) -> HistoricalPoseView
close_connection(id,reason) -> Unit
```

所有修改型接口须在所属权威阶段提交；查询不推进时间。命令失败遵循公共错误码；空结果与非法输入分开。非幂等的外部请求须使用稳定请求 ID 或事务回执。

## 6. 核心算法与运行流程

握手验证身份/内容/版本→按连接映射 actor/控制权→校验包长、数组、序列、速率、tick 与合法动作→投递权威 Mission。服务器以 30/60 Hz 模拟（待测），10–20 Hz 起始快照，兴趣区域和重要度生成量化增量。客户端预测自身移动/部分动作，收到 ack 后丢弃已确认输入并重放剩余，远端插值。延迟补偿从受限服务端历史取姿态，最大回溯窗/近战弹体格挡策略 P0/P6 验证冻结，不信任客户端自行指定任意过去。掉包/乱序时恢复基线或全量快照。

## 7. 配置、异常与安全边界

包长、序列回绕、历史窗口、速率、超时、带宽均配置且安全范围验证。加密鉴权/凭证不日志；客户端不发送已确认命中/生命/结果。观战视图受授权。拒绝不匹配内容和非法消息，不崩溃。

## 8. 表现及可观测性

客户端显示延迟、断线、重连、版本不符和同步状态。

**性能与诊断：** 以 §16.2 示例 54 KB/s 为估算而非保证；监控吞吐、P95 RTT、重传/纠正、快照大小、tick 积压。

## 9. 验收用例

| 测试 ID | 需求 ID / 质量门禁 | Given（前置） | When（操作） | Then（判据） |
|---|---|---|---|---|
| T-NET-01 | NET-03 | 150 ms RTT、30 ms 抖动、3% 丢包及乱序 | 运行战斗、重连 | 状态收敛，无持续漂移 |
| T-NET-02 | NET-04 / COM-06 | 客户端伪造伤害/他人编队和旧序号 | 发送 | 拒绝或去重，无权威变更 |
| T-NET-03 | NET-05 | 内容版本/基线错误 | 重连 | 拒绝不兼容或请求全量基线 |
| T-NET-04 | NET-06 | 64/128 真人和约定 AI 数 | 压测 | 记录带宽、tick、延迟，满足评审预算 |

## 10. 完成条件与实施约束

- 公开接口与本模块数据所有权已落地；所有配置通过内容编译或启动校验。
- 本章测试及受影响跨模块验收通过，保留实际运行报告；没有已知的状态一致性/权限阻断缺陷。
- 接口或存档结构变化同步契约、迁移与 ADR；性能目标需在指定基准上测量，不以空场或 mock 数据代替。
- 实现和测试变更限于本模块及获准契约；不得把尚未实现的部分伪装成已完成。

## 文档导航（镜像目录）

- 主要实现目录：`game/infrastructure/network/`；权威设计：本文件。
- 上级入口：[上级模块 / 分组](../README.md)；[全部模块索引](../../../README.md)。
