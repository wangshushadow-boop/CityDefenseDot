# P1-CORE-001 核心运行时原语与调度

状态为 CANDIDATE。开发者 p1core 使用独立工作树 `.worktrees/p1-core`，基线 `042d1dd17741e6b7bf9ad5330c4f2d215b70dfb2`。需求 WLD-02、BAT-05 对应 CORE SDD 与 T-CORE-01/02/03。本任务由主 Agent 收集候选、检查提交白名单并集成。

实现变更为 `game/core/{runtime,worker_queue,random_stream}.gd`、模块导航、`game/tests/p1/core/run.gd` 和本报告。签核的公共契约未更改。调度器按 due_tick、数值优先级、scope 和稳定 ID 选取工作。已提交事件只产生下一次相位调用能看到的工作。固定相位额度、紧急配额、容量与跟进深度控制负载，超限返回可诊断错误。scope 令牌绑定发放实例，取消会等待已启动的 worker 并丢弃该作用域的写集。线程只收到纯数据的独立只读快照，按完整提交组和当前版本戳在稳定键屏障合并。带有 tick、nav_revision、control_revision 或 generation 的候选须在当前戳中匹配，因此调用者能区分旧快照与当前计划。域时钟由调用者传入整数 tick，纯逻辑和排序均不读取墙钟。

随机流由世界种子、scope、stream_key 派生。v1 实现为 xorshift64, 返回高 32 位。全部 64 位按 ADR-012 的 16 位小写十六进制字符往返。整组恢复先完整校验，已有流就地恢复，未出现在快照中的旧流及已取消作用域的流永久关闭，`next_u32()` 返回有效 uint32 范围外的 -1。真实 worker 数由运行时参数控制，0 在宿主线程执行非并发路径。

## 实测

Windows，Godot Standard `4.7.2.stable.official.ed1daf0bf`。由工作树根运行下列入口。`--log-file` 只改变日志位置。

```powershell
& 'D:/Program/Godot/Standard/Godot_v4.7.2-stable_win64_console.exe' --headless --log-file "$env:TEMP/p1-core-agent.log" --path game --script res://tests/p1/core/run.gd
```

| 测试 | 观测 | 结果 |
|---|---|---|
| T-CORE-01 | 固定种子 aabbccdd00001111，1 和 3 个真实并发额度得到相同相位、排序写集、随机状态与 SHA-256。高位为 1 的独立参考状态、缓存流恢复和无效恢复的原子性均通过。 | PASS，进程退出 0 |
| T-CORE-02 | 真实 worker 启动后延迟返回。重用 scope 名不复活旧令牌，跨 Runtime 同值令牌被拒，不提交缺失或过期导航、控制版本的候选。 | PASS，进程退出 0 |
| T-CORE-03 | 订阅产生下一事件，自重入被拒。每相位只执行 1 项，深度与队列上限各产生一次可诊断背压。 | PASS，进程退出 0 |

正式入口输出 `CORE failures=0`，最终重放摘要为 `ef175296753b220567b00855d3cf0cfffe3e0308de4b842d37c9184442705f15`。独立审查发现过跨 Runtime 令牌、缺失当前戳和缓存随机流恢复问题，均已修复并回归。完整战役、多年经济仿真与正式战场负载不属于本任务，本次未运行。
