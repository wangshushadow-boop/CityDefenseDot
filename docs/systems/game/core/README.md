# CORE — 核心运行时原语与调度

> 版本 0.1（设计内容未变；目录版 0.2） | 状态：详细设计提案，待评审与实现 | 所属工程：recollection（古代中国风原创沙盒）
> 实现目录：`game/core/` | 总体基线：[§2.3、§3.3、§4.2、§19.2](../../../game_design.md) | [系统索引](../../README.md)

本文在总体规格书约束内补充实现级设计。接口为语言无关伪代码，字段及新增参数为拟定契约；未标明已冻结的数值需经 ADR/测试确认。公共语义见[公共契约](../../../architecture/common_contracts.md)。测试均为待执行规格，不代表功能已实现。

## 1. 职责与边界

提供类型化标识、Result、随机流、取消令牌、生命周期、调度及受控事件投递；不包含业务规则、引擎 Node、战役仓库或战场实体。时钟机制为整数 tick，World 决定游戏分钟，Mission 决定物理 tick。

**协作边界：** CON；以 core 的端口适配平台任务池与单调时钟。跨模块写入经 application 或权威运行时编排；不直接访问其他模块私有仓库。

## 2. 数据所有权与生命周期

Core 不拥有领域数据；每个 runtime 拥有独立 Scheduler/RandomRegistry/EventScope；会话结束销毁，随机状态可序列化。

## 3. 代码组织

以下为建议的文件职责（按选定语言补扩展名；不是已有源码）：

```text
ids / result / error
lifecycle / cancellation
scheduler / work_queue / barrier
random_registry / clock_port
event_scope / stable_order
```

## 4. 数据模型与约束

`ScheduledJob{job_id, scope_id, phase, due_tick, priority, seq, budget_class}`；`RandomStream{stream_key, algorithm_version, state}`；`CancellationToken{scope_id,generation}`；`DomainError{code,message_key,field?,detail?}`。流派生按稳定键（世界种子+模块+实体+用途），禁止共享全局 RNG；跨线程结果携带快照版本。

## 5. 公共接口

```text
derive_rng(scope, stream_key) -> RandomStream
schedule(job) -> Result<JobId>
run_phase(phase, tick, budget) -> PhaseReport
submit_worker(snapshot, token, job) -> JobHandle
collect_ready(scope, revision) -> WorkerResult[]
publish_committed(events, revision) -> Unit
cancel_scope(scope) -> BarrierReport
```

所有修改型接口须在所属权威阶段提交；查询不推进时间。命令失败遵循公共错误码；空结果与非法输入分开。非幂等的外部请求须使用稳定请求 ID 或事务回执。

## 6. 核心算法与运行流程

调度按 due_tick、priority、稳定 ID 排序；每相位固定处理额度，未完成任务延期或按规则降级，高优先级紧急反应独立额度。工作线程只读快照，结果按 stable_key 合并，scope 或 generation 不一致直接丢弃；事件订阅生成的后续命令进入下一个合法相位。退出等待屏障，禁止回调访问已销毁 runtime。

## 7. 配置、异常与安全边界

配置 `max_followup_depth`、`max_jobs_per_phase`、`worker_count`，均为待测值。随机算法版本改变必须迁移。避免依赖系统时钟、遍历哈希表顺序或线程完成顺序影响纯逻辑。队列溢出记录背压，不丢弃权威结果；非关键表现可裁剪。

## 8. 表现及可观测性

无独立界面；通过公开查询、回执或已提交事件提供可观察结果。

**性能与诊断：** 记录每相位耗时、排队时长、过期任务和预算超限；单 Agent 不创建线程。

## 9. 验收用例

| 测试 ID | 需求 ID / 质量门禁 | Given（前置） | When（操作） | Then（判据） |
|---|---|---|---|---|
| T-CORE-01 | WLD-02 | 固定种子、相同事件和不同 worker 数 | 重复运行纯逻辑 | 相位顺序、随机状态与哈希一致 |
| T-CORE-02 | BAT-05 | 旧 Mission 作业延迟返回 | 销毁并新建 Mission | 旧结果被拒绝，无跨任务写入 |
| T-CORE-03 | §3.3 | 事件订阅不断生成后续命令 | 执行 | 达到预算，后续可诊断，不无限递归 |

## 10. 完成条件与实施约束

- 公开接口与本模块数据所有权已落地；所有配置通过内容编译或启动校验。
- 本章测试及受影响跨模块验收通过，保留实际运行报告；没有已知的状态一致性/权限阻断缺陷。
- 接口或存档结构变化同步契约、迁移与 ADR；性能目标需在指定基准上测量，不以空场或 mock 数据代替。
- 实现和测试变更限于本模块及获准契约；不得把尚未实现的部分伪装成已完成。

## 文档导航（镜像目录）

- 主要实现目录：`game/core/`；权威设计：本文件。
- 上级入口：[上级模块 / 分组](../README.md)；[全部模块索引](../../README.md)。
