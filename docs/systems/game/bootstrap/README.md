# BOOT — 启动、装配与配置

> 版本 0.1（设计内容未变；目录版 0.2） | 状态：详细设计提案，待评审与实现 | 所属工程：recollection（古代中国风原创沙盒）
> 实现目录：`game/bootstrap/` | 总体基线：[§2.3、§3、§19、§20](../../../game_design.md) | [系统索引](../../README.md)

本文在总体规格书约束内补充实现级设计。接口为语言无关伪代码，字段及新增参数为拟定契约；未标明已冻结的数值需经 ADR/测试确认。公共语义见[公共契约](../../../architecture/common_contracts.md)。测试均为待执行规格，不代表功能已实现。

## 1. 职责与边界

建立进程唯一组合根，负责客户端、headless server、数据工具三种启动配置；选择适配器并注册模块、处理器、规则、退出钩子。不得持有世界真值、替代 GameSession 或在 Autoload 中保存可变英雄/战场实例。

**协作边界：** CORE、CON、APP、INF-CONTENT、INF-ENGINE、PERSIST；按运行 profile 选择 PRESENTATION 或 SERVER。跨模块写入经 application 或权威运行时编排；不直接访问其他模块私有仓库。

## 2. 数据所有权与生命周期

BootContext 只在进程生命周期有效；持有只读启动配置、服务注册表及关闭栈。会话作用域由 APP 创建。

## 3. 代码组织

以下为建议的文件职责（按选定语言补扩展名；不是已有源码）：

```text
main / headless_main
composition_root
module_registry
config_resolver
startup_validator
shutdown_coordinator
```

## 4. 数据模型与约束

`BootConfig{profile, config_sources[], content_paths[], log_level, platform, build_id}`；`ModuleDescriptor{id, version, requires[], factory, shutdown}`；`BootReport{resolved_config, missing_services, content_hash, errors}`。注册 ID 唯一；依赖图无环；工厂仅在其依赖可用后调用。

## 5. 公共接口

```text
boot(config: BootConfig) -> Result<BootContext>
register(descriptor: ModuleDescriptor) -> Result<Unit>
validate_graph() -> Result<ModuleOrder>
create_session(profile, dependencies) -> Result<GameSessionPort>
shutdown(context) -> ShutdownReport
```

所有修改型接口须在所属权威阶段提交；查询不推进时间。命令失败遵循公共错误码；空结果与非法输入分开。非幂等的外部请求须使用稳定请求 ID 或事务回执。

## 6. 核心算法与运行流程

解析命令行/环境/默认配置 → 检查 profile → 拓扑排序模块 → 装配端口及规则 → 加载并验证内容 → 启动 Session 或服务器。任一步失败逆序释放已创建对象，不打开半初始化游戏。退出时停止接收请求，等待权威提交/安全存档，取消工作任务，再逆序销毁。客户端依赖渲染适配，专服禁止创建 UI、音频或 GPU 资源。

## 7. 配置、异常与安全边界

配置优先级遵循 §18.2；环境变量只可覆盖白名单，凭证不得进入日志。注册冲突返回 Conflict，缺失依赖 Unavailable；错误报告含配置来源。引擎和主语言尚未冻结。

## 8. 表现及可观测性

启动失败显示可恢复提示；headless 使用退出码及结构化日志。

**性能与诊断：** 记录启动各阶段耗时、失败模块、释放计数；不重复初始化进程级服务。

## 9. 验收用例

| 测试 ID | 需求 ID / 质量门禁 | Given（前置） | When（操作） | Then（判据） |
|---|---|---|---|---|
| T-BOOT-01 | §20.2 | 两个模块互相 requires | 启动 | 拒绝并显示环路且未构造 Session |
| T-BOOT-02 | §19.1 / NET-01 | headless 配置、无显示设备 | 启动专服 | 不加载 UI/音频且 Mission 端口可运行 |
| T-BOOT-03 | §20.3 | 内容载入错误 | 启动 | 逆序释放已建服务，返回可诊断报告 |

## 10. 完成条件与实施约束

- 公开接口与本模块数据所有权已落地；所有配置通过内容编译或启动校验。
- 本章测试及受影响跨模块验收通过，保留实际运行报告；没有已知的状态一致性/权限阻断缺陷。
- 接口或存档结构变化同步契约、迁移与 ADR；性能目标需在指定基准上测量，不以空场或 mock 数据代替。
- 实现和测试变更限于本模块及获准契约；不得把尚未实现的部分伪装成已完成。

## 文档导航（镜像目录）

- 主要实现目录：`game/bootstrap/`；权威设计：本文件。
- 上级入口：[上级模块 / 分组](../README.md)；[全部模块索引](../../README.md)。
