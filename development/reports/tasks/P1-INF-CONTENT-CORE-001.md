# P1-INF-CONTENT-CORE-001 内容编译 · 候选交付

开发者 p1def，隔离工作树 `.worktrees/p1-content`，基线 `a41de0689eabbf5793ceb3de4051c1321e0f07ca`。状态 CANDIDATE。关联 EXT-01/02/03、MIS-03、MOD-05。[模块 SDD](../../../docs/systems/game/infrastructure/content/README.md)

## 交付

[内容编译器](../../../game/infrastructure/content/compiler.gd) 实现 ContentPort v1，把选定的磁盘包按依赖和稳定包 ID 排序，应用声明的补丁与覆盖，检查定义图、资产摘要和场景出生/目标引用，再一次发布只读注册表与配置。补丁冲突回报双方包名，配置保留最终写入来源。可信的注册回调经过类别、有效性和重复检查，数据包本身不执行代码。

[基础包](../../../game/infrastructure/content/base/manifest.json) 随工程提供河原文化、常规演练规则、河滩练兵场及原创建模前的场景标记数据。`Compiler.new().compile(compiler.resolve_packages(compiler.scan_packages([Compiler.BASE_PACKAGE]),1).value,{})` 成功时，调用方取得 `registry`、`content_hash`、`resources`、`config_provenance`。正常业务逐步检查各次返回的 Result。

## 实测

Windows，Godot Standard 4.7.2.stable.official.ed1daf0bf，Python 3.12.14。以下命令从任务工作树执行。测试生成临时磁盘包，并在正常退出时清理。

```powershell
& $godot --headless --log-file $log --path game --script res://tests/p1/content/run.gd
python -X utf8 game/tests/p1/content/pck.py --godot $godot
```

| 用例 | 结果 | 实际判据 |
|---|---|---|
| T-INF-CONTENT-01-SLICE | PASS | 原创文化及明确补丁从磁盘编译，可信规则回调由公开端口注册和执行，未信任、无效或重复类别被拒绝。完整任务、AI 和 MOD SDK 未执行。 |
| T-INF-CONTENT-02 | PASS | 缺少依赖、版本不符、依赖环、互斥声明、补丁写入冲突、危险路径、未知配置、兼容性哈希不符均拒绝。 |
| T-INF-CONTENT-03-SLICE | PASS | API、许可证、反序扫描下的稳定内容摘要及实际独立 PCK 重载。面向用户的发布工具、分发及完整 SDK 未执行。 |
| T-INF-CONTENT-04 | PASS | 实际场景数据缺目标对应标记、缺出生区域时阻断；补齐正确类型、坐标和引用后成功。 |
| P1-CONTENT-PCK | PASS | 编辑器导入、PCK 导出、临时源工程移除后通过 `--main-pack` 运行内容 suite，三步均退出 0。源工程与 PCK 的基础内容摘要相同。 |

基础内容 SHA-256 为 `fe76080c6789c8173d3b9010b8ebcb41b0757b806f443b827c4417af5b65a579`。首轮编译因 Variant 的局部类型推断失败退出 1，显式标注 String 后 Godot 回归退出 0。首次空 export options 节导致编辑器返回 0 同时报告错误，验证器据此失败。填写 x86_64 选项后成功。[Godot 测试](../../../game/tests/p1/content/run.gd) · [PCK 复现入口](../../../game/tests/p1/content/pck.py)

变更范围为本报告、`game/infrastructure/content/` 和 `game/tests/p1/content/`。没有写入共享引擎入口、状态或其他模块。独立审查、QA、集成提交及阶段结论由主 Agent 汇总。

复审复现 NUL 文本以可写 PackedStringArray 进入已发布配置，元素变化后摘要仍指向旧值。修正为用 CON 的不可变 NUL 文本表示重建所有发布容器。回归覆盖顶层和嵌套字段只读、改原输入后已发布字节一致、同一文本两种主机表示摘要一致、文本变更时摘要变化，以及拒绝用普通数组替代文本。基础包摘要保持上述值。

QA 发现负数 battle_limit 可进入编译快照。现在校验配置从包注入和会话覆盖的两个入口，与 EncounterSpec 的正整数约束一致。负数、零和布尔值均返回 InvalidArgument 并定位来源和字段，1 通过。
