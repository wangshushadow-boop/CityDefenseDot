# P1-TELEM-001 · 结构化诊断与本地报告

生产脚本 `game/infrastructure/telemetry/diagnostics.gd` 在每个会话内维护有界的记录和指标，按 scope、tick、命令及结果 ID 关联。白名单字段在持有数据前过滤，计时采用单调时钟；报告留在本地，复制后交给调用方。

在 Windows 上使用 Godot 4.7.2 Standard 执行 `--headless --path game --script res://tests/p1/telemetry/run.gd`，退出 0。五次采样在容量 4 下得到正确的 P50/P99，日志与指标各丢弃最老的一条。测试实际写盘后读取，核对禁止字段缺失、报告不泄漏内部数组；采样了真实耗时。T-TELEM-01/02/03 的基础切片通过。完整 500/1000 战场、多人数连接及多年经济报告仍待对应阶段。

QA 与 reviewer 同时发现非字符串的 code 字典会因隐式字符串化泄露内容。修订为仅接受 ASCII 标识符字符串；其余回退为 event，嵌套凭证回归通过。
