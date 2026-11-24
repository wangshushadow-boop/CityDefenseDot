# 目录镜像迁移检查报告（历史：SDD 0.2）

本页记录上一版迁移；当前项目更名与研发包验证另见 [交付核查](../../development/reports/bootstrap_verification.md)。

- 迁移来源：上一版 `project_medieval_sdd.zip`（SDD 0.1）；文件内容与解压目录一致。
- 迁移方式：按 `module_registry.json` 原实现路径确定各 SDD 的唯一权威位置，修改相对链接和追踪路径。
- 对比结果：57 份 SDD 第 1–10 节正文与旧版完全一致；原始 `game_design.md` 字节级一致；93 条需求追踪与 208 条测试规格的原有非路径字段全部一致；17 个原 AT 场景及判据保留。
- 96 个计划目录映射：57 个独立 SDD，39 个分组/父规格导航/共享入口（不含 systems 根索引）。
- 原有设计提案状态、技术选型未冻结状态及测试 NOT_RUN 状态均不变。

## 结构检查结果

```text
PASS: 57 canonical SDDs, 96 directory mappings, 39 navigation/alias entries
PASS: 93 requirement rows, 208 test rows, 600 local Markdown link occurrences
PASS: source baseline SHA-256 and registry/trace consistency
Documentation checks only; no game implementation or test execution verified.
```

检查脚本：[check_mirror.py](check_mirror.py)。本报告不表示游戏已实现或验收测试已运行。
