# ADDONS — 编辑器插件与可信扩展 SDK

> 版本 0.1（设计内容未变；目录版 0.2） | 状态：详细设计提案，待评审与实现 | 所属工程：recollection（古代中国风原创沙盒）
> 实现目录：`game/addons/` | 总体基线：[§18.2、§20.1、§21](../../../game_design.md) | [系统索引](../../README.md)

本文在总体规格书约束内补充实现级设计。接口为语言无关伪代码，字段及新增参数为拟定契约；未标明已冻结的数值需经 ADR/测试确认。公共语义见[公共契约](../../../architecture/common_contracts.md)。测试均为待执行规格，不代表功能已实现。

## 1. 职责与边界

提供面向内容作者的编辑器面板、扩展 SDK 示例、公开注册接口与验证反馈。编辑器仅生成源内容或注册合法扩展，不修改运行中正式世界。实际包加载和验证归 INF-CONTENT；CLI 工具归 TOOLS。

**协作边界：** INF-CONTENT/DEF、INF-ENGINE 编辑器端口、CON、TOOLS。跨模块写入经 application 或权威运行时编排；不直接访问其他模块私有仓库。

## 2. 数据所有权与生命周期

编辑器临时文档、预览场景、撤销栈、扩展注册描述；运行时扩展只按可信 manifest 装配。

## 3. 代码组织

以下为建议的文件职责（按选定语言补扩展名；不是已有源码）：

```text
editor_plugins/world_editor / scene_editor / troop_editor
economy_editor / quest_graph / action_editor
validation_panel / preview_runtime
sdk/extension_registry_api / examples / compatibility
trusted_extensions/
```

## 4. 数据模型与约束

`EditorDocument{source_path,dirty,revision,selection}`；`ExtensionDescriptor{id,api_version,registration_keys,requires,trust}`；`ValidationFinding{severity,source_path,field,message_key}`。编辑器写入源 JSON/CSV/Resource，发布运行时读编译产物。

## 5. 公共接口

```text
OpenContentDocument(path) -> EditorDocument
ValidateDraft(document) -> ValidationReport
PreviewScene(scene_def,seed) -> PreviewSession
ExportPackage(selection) -> Result<PackageArtifact>
RegisterExtension(descriptor,trust) -> Result<Unit>
```

所有修改型接口须在所属权威阶段提交；查询不推进时间。命令失败遵循公共错误码；空结果与非法输入分开。非幂等的外部请求须使用稳定请求 ID 或事务回执。

## 6. 核心算法与运行流程

编辑→局部验证→预览隔离会话→保存源资产→全量编译。世界编辑器可改道路、领地关系和路径；场景编辑器标注出生区、目标、导航链接、器械槽、撤离边界；兵种/经济/任务/动作编辑器显示 DAG、配方、分支、攻击窗口；战斗和战役调试工具消费只读跟踪。SDK 注册规则、行为、对话目标和 UI 扩展，禁止私有反射写入。

## 7. 配置、异常与安全边界

可信代码扩展明确风险，默认数据型包；预览不能污染正式存档。编辑器与运行时版本分别记录，撤销不依赖游戏事务。构建阻断错误不得以编辑器警告忽略。

## 8. 表现及可观测性

编辑器提供图形化场景/数据编辑、错误定位、预览和撤销。

**性能与诊断：** 大资产预览按需加载；增量验证+发布全量检查；记录插件错误和资源释放。

## 9. 验收用例

| 测试 ID | 需求 ID / 质量门禁 | Given（前置） | When（操作） | Then（判据） |
|---|---|---|---|---|
| T-ADDONS-01 | EXT-03 | 内容作者创建兵种及任务模板 | 验证、导出 | 生成版本化包及 API/授权说明 |
| T-ADDONS-02 | MIS-03 | 场景目标不可达、动画窗口不合法 | 验证 | 定位错误并阻断发布 |
| T-ADDONS-03 | EXT-01 | 通过 SDK 注册新战术 | 加载 | 不修改既有 AI 内部类 |

## 10. 完成条件与实施约束

- 公开接口与本模块数据所有权已落地；所有配置通过内容编译或启动校验。
- 本章测试及受影响跨模块验收通过，保留实际运行报告；没有已知的状态一致性/权限阻断缺陷。
- 接口或存档结构变化同步契约、迁移与 ADR；性能目标需在指定基准上测量，不以空场或 mock 数据代替。
- 实现和测试变更限于本模块及获准契约；不得把尚未实现的部分伪装成已完成。

## 文档导航（镜像目录）

- 主要实现目录：`game/addons/`；权威设计：本文件。
- 上级入口：[上级模块 / 分组](../README.md)；[全部模块索引](../../README.md)。

| 对应实现目录 | 设计入口 | 类型 |
|---|---|---|
| `game/addons/naval/` | [海战扩展代码（EXT）](naval/README.md) | 共享 SDD 入口 |
