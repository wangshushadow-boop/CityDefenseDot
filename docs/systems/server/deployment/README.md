# SERVER-OPS — 部署、扩容、运维与发布

> 版本 0.1（设计内容未变；目录版 0.2） | 状态：详细设计提案，待评审与实现 | 所属工程：recollection（古代中国风原创沙盒）
> 实现目录：`server/deployment/` | 总体基线：[§16、§19.4、§20.3、§23](../../../game_design.md) | [系统索引](../../README.md)

本文在总体规格书约束内补充实现级设计。接口为语言无关伪代码，字段及新增参数为拟定契约；未标明已冻结的数值需经 ADR/测试确认。公共语义见[公共契约](../../../architecture/common_contracts.md)。测试均为待执行规格，不代表功能已实现。

## 1. 职责与边界

定义专服和大厅服务的构建、版本、环境配置、健康探针、容量、滚动发布、回滚、监控、密钥管理与自托管交付。具体云/容器选型 P0/P6 ADR 决策；不要求从第一天微服务化。

**协作边界：** SERVER-D/SERVER-L、CI、TELEM、INF-CONTENT。跨模块写入经 application 或权威运行时编排；不直接访问其他模块私有仓库。

## 2. 数据所有权与生命周期

部署清单、版本化镜像/包、服务配置、环境密钥引用、发布记录；密钥不存 Git。

## 3. 代码组织

以下为建议的文件职责（按选定语言补扩展名；不是已有源码）：

```text
profiles/local / staging / production
 dedicated_config / lobby_config
 health_checks / capacity_policy
 release_manifest / rollout / rollback
 monitoring / alerts / self_hosting_guide
```

## 4. 数据模型与约束

`DeploymentManifest{build_id,protocol_version,content_hash,service_versions,config_ref}`；`HealthPolicy{readiness,liveness,drain_timeout}`；`CapacityProfile{players,ai,tick_budget,region}`。配置与版本分离，内容哈希必须兼容。

## 5. 公共接口

```text
Deploy(manifest,environment) -> DeploymentReport
CheckHealth(instance) -> HealthStatus
Drain(instance) -> Receipt
ScaleDedicated(profile,count) -> Receipt
Rollback(release_id) -> DeploymentReport
```

所有修改型接口须在所属权威阶段提交；查询不推进时间。命令失败遵循公共错误码；空结果与非法输入分开。非幂等的外部请求须使用稳定请求 ID 或事务回执。

## 6. 核心算法与运行流程

CI 生成签名客户端/服务器与内容包→部署 staging→健康、协议、回归和压力门禁→注册可用实例→滚动发布先停止分配旧实例、排空后下线。大厅数据库迁移先兼容旧版本并备份；失败回滚至兼容版本，已提交赛果不撤销。自托管提供配置/地图轮换/管理员权限和日志说明。

## 7. 配置、异常与安全边界

配置密钥注入、访问控制、限流、监控与备份；禁止将日志/凭证写镜像。容量 64/128 真人初始设计，200+ 为压力/扩展目标；不得标记为已支持。

## 8. 表现及可观测性

无独立界面；通过公开查询、回执或已提交事件提供可观察结果。

**性能与诊断：** 容量与健康仪表板；记录部署时长、可用实例、断线尖峰、资源与版本。

## 9. 验收用例

| 测试 ID | 需求 ID / 质量门禁 | Given（前置） | When（操作） | Then（判据） |
|---|---|---|---|---|
| T-SERVER-OPS-01 | NET-05 | 新版本协议不兼容或实例失败 | 滚动发布/回滚 | 匹配正确隔离，已提交结果保持 |
| T-SERVER-OPS-02 | NET-06 | 实例满载及故障 | 健康与扩容测试 | 容量、延迟和报警可测 |
| T-SERVER-OPS-03 | §20.3 | 自托管构建包 | 安装升级 | 版本/哈希可验证，配置可回滚 |

## 10. 完成条件与实施约束

- 公开接口与本模块数据所有权已落地；所有配置通过内容编译或启动校验。
- 本章测试及受影响跨模块验收通过，保留实际运行报告；没有已知的状态一致性/权限阻断缺陷。
- 接口或存档结构变化同步契约、迁移与 ADR；性能目标需在指定基准上测量，不以空场或 mock 数据代替。
- 实现和测试变更限于本模块及获准契约；不得把尚未实现的部分伪装成已完成。

## 文档导航（镜像目录）

- 主要实现目录：`server/deployment/`；权威设计：本文件。
- 上级入口：[上级模块 / 分组](../README.md)；[全部模块索引](../../README.md)。
