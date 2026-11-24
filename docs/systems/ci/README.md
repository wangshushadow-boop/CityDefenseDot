# CI — 持续集成、架构门禁与发布构建

> 版本 0.1（设计内容未变；目录版 0.2） | 状态：详细设计提案，待评审与实现 | 所属工程：recollection（古代中国风原创沙盒）
> 实现目录：`ci/` | 总体基线：[§20.2–20.3、§21–23](../../game_design.md) | [系统索引](../README.md)

本文在总体规格书约束内补充实现级设计。接口为语言无关伪代码，字段及新增参数为拟定契约；未标明已冻结的数值需经 ADR/测试确认。公共语义见[公共契约](../../architecture/common_contracts.md)。测试均为待执行规格，不代表功能已实现。

## 1. 职责与边界

负责自动化静态/依赖检查、内容编译、单元集成测试、headless、网络故障、性能回归、客户端/专服构建和发布。Git 是正式版本来源；实际 CI 平台与主语言待冻结。

**协作边界：** BOOT/TOOLS/TEST/TELEM、SERVER-OPS、版本锁定与资产仓库。跨模块写入经 application 或权威运行时编排；不直接访问其他模块私有仓库。

## 2. 数据所有权与生命周期

BuildManifest、质量门禁配置、报告/签名、版本与内容哈希；不写游戏领域状态。

## 3. 代码组织

以下为建议的文件职责（按选定语言补扩展名；不是已有源码）：

```text
check_dependencies / lint / typecheck
compile_content / test_unit / test_integration
headless_mission / net_fault / long_simulation
benchmark / package_client / package_server
release / license_audit / artifact_manifest
```

## 4. 数据模型与约束

`Gate{id,required,command,inputs,expected_exit,report}`；`BuildManifest{git_commit,engine_version,language_version,dependencies,content_hash,protocol_version,targets}`；`ReleaseReceipt{build_id,artifacts,signatures,qa_report}`。

## 5. 公共接口

```text
run_gate(gate,workspace) -> GateReport
verify_dependency_graph(imports,allowed_edges) -> ValidationReport
build(target,locked_versions) -> BuildArtifact
publish_release(manifest,evidence,approval) -> ReleaseReceipt
```

所有修改型接口须在所属权威阶段提交；查询不推进时间。命令失败遵循公共错误码；空结果与非法输入分开。非幂等的外部请求须使用稳定请求 ID 或事务回执。

## 6. 核心算法与运行流程

提交检查：命名/类型/循环依赖→内容 schema/引用/许可证→快速单测属性/集成。主分支 headless Mission、战役长期、存档故障和网络故障；固定设备性能基准按配置运行并比较基线。发布生成 Windows/Linux 客户端、专服、内容包、符号与崩溃映射、安装升级/回滚记录。禁止提交缓存、构建产物、存档和密钥，大资产 Git LFS 或独立仓库。

## 7. 配置、异常与安全边界

没有技术冻结前不伪造可执行命令；锁定版本、依赖许可和构建输入。AI 修改公共契约需 ADR/人工评审与受影响测试。失败门禁不得随意关闭；例外有审批、截止和风险记录。

## 8. 表现及可观测性

无独立界面；通过公开查询、回执或已提交事件提供可观察结果。

**性能与诊断：** 记录构建、测试耗时、flaky 测试、失败门禁、制品哈希；分层运行避免每次小改全量长测。

## 9. 验收用例

| 测试 ID | 需求 ID / 质量门禁 | Given（前置） | When（操作） | Then（判据） |
|---|---|---|---|---|
| T-CI-01 | §20.2 | 领域 import presentation 或形成环 | 依赖检查 | 阻断并报告路径 |
| T-CI-02 | §23.3 | 任一 MUST 测试未通过或证据缺失 | 发布门禁 | 拒绝发布 |
| T-CI-03 | EXT-03 / NET-05 | 生成客户端/服务器/内容包 | 构建 | 版本、协议和哈希一致，可追踪 |
| T-CI-04 | §22.3 | 相同基准性能回退超过阈值 | 回归 | 报告并需评审，不隐藏问题 |

## 10. 完成条件与实施约束

- 公开接口与本模块数据所有权已落地；所有配置通过内容编译或启动校验。
- 本章测试及受影响跨模块验收通过，保留实际运行报告；没有已知的状态一致性/权限阻断缺陷。
- 接口或存档结构变化同步契约、迁移与 ADR；性能目标需在指定基准上测量，不以空场或 mock 数据代替。
- 实现和测试变更限于本模块及获准契约；不得把尚未实现的部分伪装成已完成。

## 文档导航（镜像目录）

- 主要实现目录：`ci/`；权威设计：本文件。
- 上级入口：[上级模块 / 分组](../README.md)；[全部模块索引](../README.md)。
