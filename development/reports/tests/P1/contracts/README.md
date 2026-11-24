# P1-CON-001、P1-CON-002 独立 QA

从仓库根目录运行。脚本从当前 `game/` 复制待测契约和项目测试入口到临时目录，生成 Python 参照字节，依次运行两个独立 QA 探针、两个项目测试入口和项目提供的跨实现校验程序。需要 Python 3.12 和已批准的 Godot Standard 控制台程序。

```powershell
python -X utf8 development/reports/tests/P1/contracts/run.py --godot 'D:/Program/Godot/Standard/Godot_v4.7.2-stable_win64_console.exe'
```

分支候选尚未集成时可在同一命令末尾加 `--overlay .worktrees/p1-con/game --overlay .worktrees/p1-ports/game`。选项 `--suite` 可单独指定 `QA-CANONICAL`、`QA-SHAPES`、`CON`、`PORTS` 或 `ORACLE`。缺少测试入口、子进程返回非零、脚本报错或缺少通过标记均将使外层返回非零。

## 2026-11-24 候选复测

环境为 Windows、Godot `4.7.2.stable.official.ed1daf0bf`、Python 3.12.14 和 Unicode 数据库 15.0.0。随机种子为 241124。CON-001 使用 `f72d1cb` 上开发中的候选，`schema.gd` 的 SHA-256 为 `de27bfa21f99790e8718f21c6489641c364a11e9b6c9610df4acc7c4da6e430f`。端口候选提交为 `33f36b878b0bad8013d62e9b9c933c769298b8d2`。

| 入口 | 实际输出 | 子进程退出码 |
|---|---|---:|
| QA-CANONICAL | `QA_CANONICAL 13390 candidates, mismatches=0` | 0 |
| QA-SHAPES | `P1-QA-CON-SHAPES 46 passed / 0 failed` | 0 |
| CON | `T-CON-01 PASS`、`T-CON-02 PASS`、`T-CON-03 PASS`、`P1-CON-BOUNDARY PASS`、`CON_CHECKS errors=0` | 0 |
| PORTS | `PASS T-CON-02`、`PASS P1-PORTS-V1` | 0 |
| ORACLE | `CON_ORACLE nfc=34155 wire=14 errors=0`，逆向字节 SHA-256 `1447f704cfcd725189cf1fb2154fb64faba7377f5fa1e59ee66c4d7e02131bcf` | 0 |

Python 总退出码为 0。参照程序按 Unicode 属性生成单字符、规范分解和组合序列，补充 Hangul 抽样、整数边界、代理字符、控制字符、畸形 UTF-8、非规范来源与重复键。Godot 对有效来源重新编码并计算摘要，分别与 Python 的字节及 hashlib SHA-256 比对。输入畸形字节时，预期看到 Godot 的 `Unicode parsing error` 诊断，所有对应输入均按判据拒绝。

形状探针覆盖 v0 合成存档头、类型混淆、版本/内容哈希拒绝、未知关键字段、保留槽与结算集合、结果哈希、陈旧句柄，以及候选的 MoveIntent 半速往返与速度超限。审查发现的 NUL 文本/数组混淆已用四个独立 wire 输入回测，分别验证合法文本往返、合法数组含 NUL 文本、文本不能作为数组、数组不能作为文本。T-CON-02 通过真实契约兼容性入口，测试替身记录兼容性拒绝后是否还能走到身份验证。完整网络传输、实际战役写库与发行版本存档迁移不在本轮测量内。

## 首轮失败

修复前两项结果保留如下。T-CON-01 四条失败的候选数据使用 GDScript 属性语法新增摘要键，产生 StringName 键。作者修正测试输入后，原有断言全部通过。半速用例独立复现了运行时与规范编码的处理冲突，修复后已加入本目录形状探针。百万分整数的线格式按 ADR-013 候选检验，批准情况由 ADR 记录。

```text
res://tests/p1/contracts/run.gd exit_code 1
T-CON-01 FAIL
T-CON-02 PASS
T-CON-03 PASS
P1-CON-BOUNDARY PASS
CON_CHECKS errors=4
FAIL all source slots accounted
FAIL duplicate source location
FAIL stale reservation
FAIL input unchanged

OBSERVE MoveIntent half speed = { "ok": false, "error": { "code": "InvalidArgument", "field": "canonical", "detail": <null>, "message_key": "error.invalid_argument", "retryable": false } }
```
