# TEST — 领域、集成、场景与长期测试

> 版本 0.1（设计内容未变；目录版 0.2） | 状态：详细设计提案，待评审与实现 | 所属工程：recollection（古代中国风原创沙盒）
> 实现目录：`game/tests/；test_scenarios/` | 总体基线：[§22、§23.3](../../../game_design.md) | [系统索引](../../README.md)

本文在总体规格书约束内补充实现级设计。接口为语言无关伪代码，字段及新增参数为拟定契约；未标明已冻结的数值需经 ADR/测试确认。公共语义见[公共契约](../../../architecture/common_contracts.md)。测试均为待执行规格，不代表功能已实现。

## 1. 职责与边界

统一测试组织和执行契约，包含纯领域单元、属性、跨模块集成、场景、端到端、网络故障、存档恢复、性能和长期仿真。不把文档用例视为已实现测试。具体测试框架随引擎/语言 P0 冻结。

**协作边界：** 所有模块公开接口；TOOLS、TELEM、CI、INF-ENGINE；测试可使用独立 fixture，不改正式世界。跨模块写入经 application 或权威运行时编排；不直接访问其他模块私有仓库。

## 2. 数据所有权与生命周期

TestFixture、固定种子、ScenarioInput、Assertion、TestEvidence；每次运行独立 scope/临时目录，结果只保存报告。

## 3. 代码组织

以下为建议的文件职责（按选定语言补扩展名；不是已有源码）：

```text
game/tests/unit/ (按领域镜像)
game/tests/property/ / integration/ / mission/ / network/ / persistence/
test_scenarios/world_3650_days_seeded/
test_scenarios/trade_siege_shortage_recovery/ / hero_death_inheritance/
test_scenarios/battle_500_mixed_field/ / battle_1000_mixed_field/
test_scenarios/siege_multi_breach/ / encounter_commit_crash_recovery/
test_scenarios/multiplayer_latency_loss/ / save_migrate_mod_conflict/
```

## 4. 数据模型与约束

`TestCase{id,requirements[],fixture,seed,steps,assertions}`；`Scenario{scene_def,ruleset,rosters,input_trace,seed,expected_invariants}`；`Evidence{test_id,build,content_hash,environment,status,report_path}`。需求 ID→SDD 测试 ID→实际测试→证据。

## 5. 公共接口

```text
run_tests(selection,environment) -> TestReport
run_property_tests(generator,seeds) -> TestReport
run_scenario(scenario,config) -> ScenarioReport
inject_fault(kind,phase) -> FaultToken
run_long_simulation(seeds,years) -> SimulationReport
```

所有修改型接口须在所属权威阶段提交；查询不推进时间。命令失败遵循公共错误码；空结果与非法输入分开。非幂等的外部请求须使用稳定请求 ID 或事务回执。

## 6. 核心算法与运行流程

单测覆盖公式、FSM、错误码和权限；属性测试检查非负、资源守恒、身份唯一、兵力来源和幂等；集成连接真实模块测试交易、日结、围城、政治和结果；场景自动脚本玩家/AI 驱动部署、战斗、导航、器械；故障注入覆盖磁盘满/断电、网络延迟抖动丢包乱序；端到端使用原 AT-01–17。至少 20 固定种子跑 1/3/10 年，硬不变量零失败；软指标基线由评审。自动战斗与实时分布离线校准。

## 7. 配置、异常与安全边界

性能同硬件、内容、镜头、输入、种子多次测量；P95/P99、CPU/GPU、内存、网络完整记录。物理跨平台不强制位级一致。测试失败不得自动改期望以通过。所有新增测试 ID 初始 NOT_RUN。

## 8. 表现及可观测性

无独立界面；通过公开查询、回执或已提交事件提供可观察结果。

**性能与诊断：** 性能回归初始评审阈值 10%；记录证据，禁止跳过失败/用空场替代。

## 9. 验收用例

| 测试 ID | 需求 ID / 质量门禁 | Given（前置） | When（操作） | Then（判据） |
|---|---|---|---|---|
| T-TEST-01 | §22.2 / AT-01–AT-17 | 完整 fixture 与构建 | 执行端到端矩阵 | 所有 MUST 场景通过，EXT 独立 |
| T-TEST-02 | §22.3 | 20 固定种子及随机种子 | 1/3/10 年仿真 | 硬不变量零失败，软指标有报告 |
| T-TEST-03 | BAT-03 / SAV-02 | 结算提交前/中/后故障 | 恢复 | 恰好一次提交 |
| T-TEST-04 | BAI-06 / NET-06 | 战斗和多人容量基准 | 压力 | 真实动作/AI/导航，不丢权威状态 |

## 10. 完成条件与实施约束

- 公开接口与本模块数据所有权已落地；所有配置通过内容编译或启动校验。
- 本章测试及受影响跨模块验收通过，保留实际运行报告；没有已知的状态一致性/权限阻断缺陷。
- 接口或存档结构变化同步契约、迁移与 ADR；性能目标需在指定基准上测量，不以空场或 mock 数据代替。
- 实现和测试变更限于本模块及获准契约；不得把尚未实现的部分伪装成已完成。

## 文档导航（镜像目录）

- 主要实现目录：`game/tests/`；权威设计：本文件。
- 上级入口：[上级模块 / 分组](../README.md)；[全部模块索引](../../README.md)。
- 共享规格的另一实现目录：`test_scenarios/`；[对应入口](../../test_scenarios/README.md)。
