# 全局开发规范入口

本页仅汇总原有规则，不新增设计约束。

| 主题 | 权威来源 |
|---|---|
| AI 开发约束 | [AGENTS.md](../../AGENTS.md) |
| 工程目录、编码与构建 | [总体设计第20章](../game_design.md)、[目录映射](../architecture/directory_map.md) |
| 依赖白名单、任务模板 | [依赖策略](../architecture/dependency_policy.md) |
| 公共接口、数据所有权 | [公共契约](../architecture/common_contracts.md) |
| 内容、资产、授权 | [内容生产入口](../content/README.md) |
| 性能与测试 | [总体设计第19/22章](../game_design.md)、[TEST](../systems/game/tests/README.md)、[验收矩阵](../testing/acceptance_matrix.md) |
| 构建、质量门禁、发布 | [CI](../systems/ci/README.md) |

## 研发执行标准（本次补充）

- [编码与架构纪律](coding.md)：落实既有架构白名单和代码审查。
- [测试、构建和性能门禁](testing.md)：定义执行证据、状态和阶段验收。
- [内容与资源制作标准](assets.md)：资产接口冻结与制作校验。
- [文档与变更规范](documentation.md)：镜像、追踪、ADR。
- [Codex 多 Agent 工作流](../../development/workflow.md)：任务分批、隔离、验收。
