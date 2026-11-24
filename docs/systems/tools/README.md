# TOOLS — 内容 CLI、验证器与开发调试工具

> 版本 0.1（设计内容未变；目录版 0.2） | 状态：详细设计提案，待评审与实现 | 所属工程：recollection（古代中国风原创沙盒）
> 实现目录：`tools/` | 总体基线：[§20.1、§21、§22](../../game_design.md) | [系统索引](../README.md)

本文在总体规格书约束内补充实现级设计。接口为语言无关伪代码，字段及新增参数为拟定契约；未标明已冻结的数值需经 ADR/测试确认。公共语义见[公共契约](../../architecture/common_contracts.md)。测试均为待执行规格，不代表功能已实现。

## 1. 职责与边界

提供可在 CI/headless 执行的内容编译、地图/任务/兵种/动画/资产校验、长期仿真、战斗调试、性能采集、包管理和发布工具；编辑器插件复用同一核心验证规则。工具不修改正式运行中世界。

**协作边界：** INF-CONTENT/DEF、INF-ENGINE、ADDONS、CAMP/MIS-RT 公开仿真端口、TELEM。跨模块写入经 application 或权威运行时编排；不直接访问其他模块私有仓库。

## 2. 数据所有权与生命周期

工具输入源内容与固定种子，输出只读编译包、报告、基准数据；临时工作区隔离。

## 3. 代码组织

以下为建议的文件职责（按选定语言补扩展名；不是已有源码）：

```text
content_compile / package_check / package_build
world_map_check / scene_nav_check / troop_tree_check
quest_graph_check / economy_simulator / action_window_check
asset_license_check / localization_check
battle_debug / campaign_inspect / benchmark_runner
```

## 4. 数据模型与约束

`ToolInvocation{command,input_paths,seed?,config,output_dir}`；`ValidationReport{errors,warnings,source_refs,tool_version}`；`BenchmarkReport{build,content_hash,seed,hardware,scenario,metrics}`。退出码 0 通过、非 0 阻断，机器可读 JSON 报告。

## 5. 公共接口

```text
compile_content(input,output) -> ValidationReport
validate_world / validate_scene / validate_action / validate_quest(...) -> ValidationReport
simulate_world(seed,days) -> SimulationReport
run_benchmark(scenario,config) -> BenchmarkReport
build_package(manifest) -> PackageArtifact
```

所有修改型接口须在所属权威阶段提交；查询不推进时间。命令失败遵循公共错误码；空结果与非法输入分开。非幂等的外部请求须使用稳定请求 ID 或事务回执。

## 6. 核心算法与运行流程

统一验证：ID/引用/升级 DAG、地图交通与场景出生/目标可达、动作窗口/骨骼/挂点、任务图和本地化、授权及资产预算。长期仿真固定种子、日报/异常断言；战场基准固定内容/镜头/人数/输入，记录 CPU/GPU/tick/路径/AI；将报告写到输出目录供 CI 和编辑器共享。MOD 包拓扑、冲突和 API 版本检查复用 INF-CONTENT。

## 7. 配置、异常与安全边界

工具失败不覆盖上一次正式产物；报告带版本和输入哈希。禁止通过工具自动跳过不变量错误；性能回归不能降低单位数伪装通过。具体命令行名称、运行语言待 P0 决策。

## 8. 表现及可观测性

无独立界面；通过公开查询、回执或已提交事件提供可观察结果。

**性能与诊断：** 支持增量开发检查、发布全量校验；报告记录验证耗时、资源和基准重复次数。

## 9. 验收用例

| 测试 ID | 需求 ID / 质量门禁 | Given（前置） | When（操作） | Then（判据） |
|---|---|---|---|---|
| T-TOOLS-01 | MIS-03 / EXT-03 | 场景缺出生、引用、任务不可达或未授权资产 | 运行 CLI | 非零退出码与准确错误定位 |
| T-TOOLS-02 | ECO-06 / SAI-03 | 20 固定种子多年仿真 | 运行 | 报告硬不变量与软指标 |
| T-TOOLS-03 | BAI-06 / §19.4 | 500/1000 真战斗基准 | 运行 | 完整硬件、帧/tick、内存报告 |

## 10. 完成条件与实施约束

- 公开接口与本模块数据所有权已落地；所有配置通过内容编译或启动校验。
- 本章测试及受影响跨模块验收通过，保留实际运行报告；没有已知的状态一致性/权限阻断缺陷。
- 接口或存档结构变化同步契约、迁移与 ADR；性能目标需在指定基准上测量，不以空场或 mock 数据代替。
- 实现和测试变更限于本模块及获准契约；不得把尚未实现的部分伪装成已完成。

## 文档导航（镜像目录）

- 主要实现目录：`tools/`；权威设计：本文件。
- 上级入口：[上级模块 / 分组](../README.md)；[全部模块索引](../README.md)。
