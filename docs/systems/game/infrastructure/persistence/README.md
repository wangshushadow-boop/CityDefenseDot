# PERSIST — 存档、原子提交、迁移与恢复

> 版本 0.1（设计内容未变；目录版 0.2） | 状态：详细设计提案，待评审与实现 | 所属工程：recollection（古代中国风原创沙盒）
> 实现目录：`game/infrastructure/persistence/` | 总体基线：[§10.2、§17、§18.1、§22](../../../../game_design.md) | [系统索引](../../../README.md)

本文在总体规格书约束内补充实现级设计。接口为语言无关伪代码，字段及新增参数为拟定契约；未标明已冻结的数值需经 ADR/测试确认。公共语义见[公共契约](../../../../architecture/common_contracts.md)。测试均为待执行规格，不代表功能已实现。

## 1. 职责与边界

实现世界快照编码、存档槽、临时写入、原子提交、备份、关键事务恢复及版本迁移。快照由 APP/CAMP 在安全点提供；不直接改业务真值，不支持任意战斗帧存档。

**协作边界：** CON、CORE 文件/时钟端口、APP/CAMP 快照端口、DEF/INF-CONTENT 兼容检查。跨模块写入经 application 或权威运行时编排；不直接访问其他模块私有仓库。

## 2. 数据所有权与生命周期

SaveManifest、序列化文件、commit marker、恢复日志、迁移链和备份归存档层；持久业务对象仍归各域。

## 3. 代码组织

以下为建议的文件职责（按选定语言补扩展名；不是已有源码）：

```text
save_service / snapshot_codec / manifest
atomic_writer / commit_marker / recovery_journal
backup_manager / slot_index
migrations/vN_to_vN1 / reference_validator
fault_injection / save_diagnostics
```

## 4. 数据模型与约束

目录保持 §18.1：manifest.json、world.bin、transactions.bin（必要时）、thumbnail.webp、backup/。`SaveManifest{schema_version,game_version,content_packages,content_hash,world_id,game_minute,commit_id,checksum,summary}`；`PendingCommit{txn_id,result_id,base_revision,target_revision,hash,state}`。保存随机流、AI 长计划、动态物品、任务、围城、去重 ID；不保存节点/RID/缓存。

## 5. 公共接口

```text
SaveGame(slot,immutable_snapshot,reason) -> Result<SaveReceipt>
LoadGame(slot,installed_content) -> Result<WorldSnapshot>
write_prebattle_checkpoint(encounter,snapshot) -> Receipt
commit_critical(snapshot,applied_result_id) -> Result<CommitReceipt>
recover(slot) -> Result<RecoveryReport>
migrate(data,from,to) -> Result<MigratedSnapshot>
```

所有修改型接口须在所属权威阶段提交；查询不推进时间。命令失败遵循公共错误码；空结果与非法输入分开。非幂等的外部请求须使用稳定请求 ID 或事务回执。

## 6. 核心算法与运行流程

在权威 tick 安全屏障捕获快照→后台编码/压缩→写同文件系统临时版本→校验长度/哈希→按平台持久化语义刷新文件与目录/提交标记→原子切换 manifest 指向完整版本→保留上一有效版。战斗结果与 applied_result_id 同一提交，恢复时读最后有效提交或待提交日志；不能先发放奖励再记录 ID。迁移按 vN→vN+1 纯数据逐级执行，保留原档，先装载动态定义再解析引用。铁人模式禁止普通手动回滚，但仍支持故障恢复。

## 7. 配置、异常与安全边界

磁盘满、权限、损坏、内容缺失返回可恢复原因；禁止静默跳过关键字段。战斗中退出使用战前检查点/结果日志；后台写线程只持有不可变快照。备份保留策略可配置，事务日志可安全压缩。

## 8. 表现及可观测性

存档列表、时间/内容版本、恢复备份和错误原因；铁人限制明确显示。

**性能与诊断：** 记录快照捕获时间、序列化大小、I/O P95、失败和恢复次数；主线程只持屏障最短时间。

## 9. 验收用例

| 测试 ID | 需求 ID / 质量门禁 | Given（前置） | When（操作） | Then（判据） |
|---|---|---|---|---|
| T-PERSIST-01 | SAV-01 | 多槽、世界多年状态和 RNG | 保存加载 | 规范化领域快照一致 |
| T-PERSIST-02 | SAV-02 / BAT-03 | 写前/中/提交标记后模拟断电或磁盘满 | 恢复重试 | 读有效前/后版本，结果恰好一次 |
| T-PERSIST-03 | SAV-03 | 旧 schema、动态锻造物品、缺 MOD | 加载 | 逐级迁移或明确拒绝，原档保留 |
| T-PERSIST-04 | §22.2 / AT-15 | 50 次 Mission 切换和存档 | 循环 | 无泄漏、存档可载入 |

## 10. 完成条件与实施约束

- 公开接口与本模块数据所有权已落地；所有配置通过内容编译或启动校验。
- 本章测试及受影响跨模块验收通过，保留实际运行报告；没有已知的状态一致性/权限阻断缺陷。
- 接口或存档结构变化同步契约、迁移与 ADR；性能目标需在指定基准上测量，不以空场或 mock 数据代替。
- 实现和测试变更限于本模块及获准契约；不得把尚未实现的部分伪装成已完成。

## 文档导航（镜像目录）

- 主要实现目录：`game/infrastructure/persistence/`；权威设计：本文件。
- 上级入口：[上级模块 / 分组](../README.md)；[全部模块索引](../../../README.md)。
