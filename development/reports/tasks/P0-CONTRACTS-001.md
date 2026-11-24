# P0-CONTRACTS-001 · 公共契约候选与可执行向量

2026-11-24，架构师子 Agent contracts。基线 `675aa6217117acebfbaf3ec3d463d5f07faa2fd8`，独立工作树 `.worktrees/p0-contracts`，detached HEAD。实验 ID 为 **CON-VECTORS**，候选状态 CANDIDATE。负责人批准记录和集成提交由主 Agent 单独登记。

| 交付 | 内容 |
|---|---|
| [ADR-012](../../../docs/architecture/decisions/ADR-012-contract-freeze.md) | 在总体规格 §3/10/16–19 和公共契约 §1–7 的基础上提出持久 ID、整数精度、空间量化、规范编码与摘要；说明命令/查询/快照/事件时序、三类跨域消息、所有权和版本迁移。记录 CORE/CON 类型归属、FORMATION 扩展字段位置、战场观测与战役提交的裁决建议。状态 PROPOSED。 |
| [向量脚本](../../../test_scenarios/p0/P0-CONTRACTS-001/vectors.py) | 无外部依赖的 Python unittest。对跨域消息选取字段切片并运行编解码及语义校验，权威数据由各测试独立提供。 |

## 实际执行

在该工作树根目录执行以下命令。脚本输入和预期摘要固化在仓库中，无外部服务或随机时钟依赖。

```powershell
$python = 'C:/Users/10822/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe'
& $python test_scenarios/p0/P0-CONTRACTS-001/vectors.py
```

Python 3.12.14，退出码 **0**。unittest 输出 `Ran 8 tests`、`OK`，失败 0、跳过 0。八组分别检查：

- 规范 JSON 往返、固定 SHA-256、重复键/浮点/NFC/越界拒绝。PowerShell SHA256 对 UTF-8 字节 `{"game_minute":12,"schema_version":1}` 独立算得 `bafa46fb93c768558e0945e9e95d714e0a4626a5e64bd66c31262526ed96b2f6`，退出码 0。
- 类型化 ID、毫米量化的正负半单位、越界、null/零和布尔/整数区分。
- 句柄的合法 scope/generation，拒绝已回收下标的旧 generation 及其他 Mission。
- EncounterSpec 预留与 MissionResult 源槽覆盖、终态、未生成兵员、过期 revision 和损坏摘要。
- FormationOrder 的 issuer/scope/编队权限、未来 tick 拒绝。
- 已提交命令的原回执重放、同 ID 不同内容冲突、无权主体拒绝、新命令未命中。
- 合成旧头逐级迁移，原始输入不变，拒绝未知关键字段、未知版本与负数。
- 协议版本、内容 API 和内容摘要分别不匹配时拒绝。

独立 QA 在候选 `e22c560` 发现布尔值可充当握手版本或编队 ID。开发侧复现两个错误接受结果后，在值比较、查询、去重前校验整数类型及上下界。协议版本、内容 API、句柄、命令版本、编队索引、tick、结果版本、经验及伤情均加入相应用例；类型化 ID 增测非字符串及畸形 UUID。实验中的编队索引取 uint32。重跑同一命令得到 8 组通过，退出 0。修复后脚本 SHA-256 为 `5153af2145dbe9b03e67c740a2d30330699194a3cacac19855d04260b457645e`。`git diff --check` 退出 0。独立复核和最终提交号见本批集成记录。

## 验收边界

本报告支持评审候选契约。P1/P3 真实持久化/崩溃恢复、跨语言编解码、P6 服务端身份签名及正式 T-CON-01–03、T-APP、T-PERSIST、AT 均为 NOT_RUN。完整游戏接口与已有公共契约源文件保持原登记状态。负责人需确认 UUID/规范化/坐标与兼容政策，时钟与回溯参数结合 ADR-011 的实际网络和性能证据再冻结。
