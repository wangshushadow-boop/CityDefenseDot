# TELEM — 日志、指标、诊断与崩溃报告

> 版本 0.1（设计内容未变；目录版 0.2） | 状态：详细设计提案，待评审与实现 | 所属工程：recollection（古代中国风原创沙盒）
> 实现目录：`game/infrastructure/telemetry/` | 总体基线：[§19.4、§20.2、§22、§16.3](../../../../game_design.md) | [系统索引](../../../README.md)

本文在总体规格书约束内补充实现级设计。接口为语言无关伪代码，字段及新增参数为拟定契约；未标明已冻结的数值需经 ADR/测试确认。公共语义见[公共契约](../../../../architecture/common_contracts.md)。测试均为待执行规格，不代表功能已实现。

## 1. 职责与边界

提供结构化日志、性能计数、跟踪、AI 决策诊断、异常状态和崩溃报告；不参与游戏真值或引入必须在线的单人依赖。

**协作边界：** CON/CORE；各领域通过注入 Logger/MetricsPort 上报。跨模块写入经 application 或权威运行时编排；不直接访问其他模块私有仓库。

## 2. 数据所有权与生命周期

LogSink、MetricRegistry、TraceSpan、崩溃上下文和报告缓冲；只持有必要摘要，不保存隐私或完整玩家凭证。

## 3. 代码组织

以下为建议的文件职责（按选定语言补扩展名；不是已有源码）：

```text
logger / context_fields / redaction
metrics / histogram / profiler_span
trace / ai_trace_sink / replay_metadata
crash_report / local_export / health_report
```

## 4. 数据模型与约束

`LogRecord{level,code,scope_id,revision,tick,entity_ref?,command_id?,result_id?,fields}`；`Metric{key,unit,tags,values}`；`CrashReport{build,content_hash,platform,stack,redacted_context}`。时间戳与仿真 tick 分离。

## 5. 公共接口

```text
log(record) -> Unit
measure_span(key,context) -> SpanToken
observe(metric,value,tags) -> Unit
export_report(session,filters) -> Report
capture_crash(context) -> LocalReport
```

所有修改型接口须在所属权威阶段提交；查询不推进时间。命令失败遵循公共错误码；空结果与非法输入分开。非幂等的外部请求须使用稳定请求 ID 或事务回执。

## 6. 核心算法与运行流程

每系统注册固定指标，tick/帧/路径/AI/网络/存档采样聚合分位数；低频命令事件按 ID 关联；高频采样有界缓存，丢弃只影响诊断。错误报告记录可复现实验的种子、内容哈希和配置。崩溃报告先本地落盘，外发需合规授权，隐私字段过滤。

## 7. 配置、异常与安全边界

日志等级、采样率、滚动大小、保留期配置化；禁止凭证、账号秘密、无必要聊天原文；Telemetry 失败不阻断游戏事务。

## 8. 表现及可观测性

无独立界面；通过公开查询、回执或已提交事件提供可观察结果。

**性能与诊断：** 采样和批量异步落盘，不在热路径逐兵格式化；监控诊断自身成本。

## 9. 验收用例

| 测试 ID | 需求 ID / 质量门禁 | Given（前置） | When（操作） | Then（判据） |
|---|---|---|---|---|
| T-TELEM-01 | §19.4 | 500/1000 战场基准 | 运行报告 | 包含 P50/P95/P99、实体数、CPU/GPU、队列和内存 |
| T-TELEM-02 | NET-06 | 多人连接含凭证 | 采集日志 | 敏感值脱敏，健康指标齐全 |
| T-TELEM-03 | §22.3 | 经济长期仿真 | 输出日报 | 可追溯异常库存和 AI 切换 |

## 10. 完成条件与实施约束

- 公开接口与本模块数据所有权已落地；所有配置通过内容编译或启动校验。
- 本章测试及受影响跨模块验收通过，保留实际运行报告；没有已知的状态一致性/权限阻断缺陷。
- 接口或存档结构变化同步契约、迁移与 ADR；性能目标需在指定基准上测量，不以空场或 mock 数据代替。
- 实现和测试变更限于本模块及获准契约；不得把尚未实现的部分伪装成已完成。

## 文档导航（镜像目录）

- 主要实现目录：`game/infrastructure/telemetry/`；权威设计：本文件。
- 上级入口：[上级模块 / 分组](../README.md)；[全部模块索引](../../../README.md)。
