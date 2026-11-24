# P0-CONTRACTS-002 · Godot 与 Python 的规范字节互操作

2026-11-24，架构师子 Agent contracts。工作树 `.worktrees/p0-contract-codec`，基线 `71ddfb6d2793f0565d6f3eeb423b40879a0366dc`，候选状态 CANDIDATE。实验 ID 为 CON-INTEROP。提交内容为实验工程三文件与本报告。审查、QA 与集成由主 Agent 记录。

## 运行与结果

在工作树根执行。Python 使用 3.12.14，Godot Standard 使用 4.7.2.stable.official.ed1daf0bf。运行器直接调用 P0-CONTRACTS-001 的 Python 规范编码器和解码器，启动独立 headless 引擎进程，逐个比较文件原始字节和双方计算的 SHA-256。[运行入口](../../../test_scenarios/p0/P0-CONTRACTS-002/run.py) · [引擎端](../../../test_scenarios/p0/P0-CONTRACTS-002/probe.gd)

```powershell
$python = 'C:/Users/10822/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe'
$godot = 'D:/Program/Godot/Standard/Godot_v4.7.2-stable_win64_console.exe'
& $python test_scenarios/p0/P0-CONTRACTS-002/run.py --godot $godot
```

最终命令退出 0，嵌套 Godot 进程退出 0。Python 构造 JSON 消息，按 ASCII 键序输出 delta、enabled、label 三字段。±(2⁵³−1)、零、布尔以及中文、预组字符 é、引号和反斜杠均参与正向样例。4 份 Python 来源数据经 Godot 解码、重编后，均逐字节一致。Godot 独立构造发给 Python 的一份消息也通过字节、哈希和各字段类型/值验证。两份固定向量的 SHA-256 分别为 `dd1908c7406d18b40ace6c22b59aaf18f45bed1981057a242a3b4c8c18019038` 和 `fec87a118f1e3755d33a1f166e0212b1c3e151ce15d4001dd6bd4c2f0f93e536`，运行器已固化预期值。

双方都拒绝 15 个样例，其中 14 个违反字段或规范编码要求，覆盖用 true 填整数、用 1 填布尔、1.0、指数、负零、上下越界、浮点取整碰撞、重复键、分解字符、BOM、未知字段、额外空格和键顺序。第 15 个使用合法预组字符 ñ，位于本实验支持的字符范围之外。

## 默认解析器实测

| 原始 UTF-8 JSON | Godot 的 Variant 值或重编结果 |
|---|---|
| `1`、`1.0` | 都为 float；保留完整浮点精度时都编回 `1.0`。 |
| `true` | 保留 bool。 |
| `9007199254740991` | float，对应 `9.007199254740991e+15`。 |
| `9007199254740992`、`9007199254740993` | 都得到 `9.007199254740992e+15`。 |
| `{"n":1,"n":2}` | 剩 1 个键，n 的值为 2。 |

## 提交给负责人评审

在要求发送端使用规范字节的小消息上，接收端可以先校验字段集合与类型，拒绝布尔冒充整数，检查数值有限、无小数且位于精确范围，再恢复整型并编回规范 JSON，与收到的 UTF-8 原始字节逐一比较。只看解析后的 Dictionary 会失去原数值词法和重复键证据。此接收政策应只用于已约定规范线格式的端口；对允许用户输入带空白及任意键序的编辑源文件，应在词法读取时验证重复键/数值词法，再做规范化。两种输入约定应写入最终 schema。

本实验的 label 只接受可打印 ASCII、U+4E00–U+9FFF 及 U+00E9。这组字符的序列保持 NFC，双方用相同规则拒绝超出集合的字符。完整 Unicode NFC、本体各消息、存档文件 IO 及高频消息吞吐均为 **NOT_RUN**。P1 若需支持任意合法文本，应采用完整 NFC 实现并加入跨语言 Unicode 测试。ADR-012 保持 PROPOSED，本任务没有更改公共契约。
