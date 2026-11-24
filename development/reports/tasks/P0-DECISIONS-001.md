# P0-DECISIONS-001 · 提交负责人决策

各技术实验已通过独立审查、QA 和串行集成。当前可评审的实测集成点为 `47d3a40`。主 Agent 建议批准本次隔离实验的性能基线与 [ADR-011](../../../docs/architecture/decisions/ADR-011-technology-stack.md)，并批准 [ADR-012](../../../docs/architecture/decisions/ADR-012-contract-freeze.md) 的数据表示、权威写入及版本边界。

技术基线提议为 Godot Standard 4.7.2、类型化 GDScript、Windows 首个验证平台、Forward+/Vulkan、ENet 权威专服、30 Hz 服务器与 15 Hz 快照。候选回溯上限为 200 ms。契约提议为带类型 UUID、规范 UTF-8 JSON + SHA-256、独立版本和按副本迁移。指定安装的可执行散列、采样配置和原始文件可复查。

批准范围为 P0 验证。真实游戏中画质素材及 8 GiB 参考设备、完整 Unicode、完整战斗及公网容量均另有验证边界，见阶段报告。当前负责人批准记录为待签。没有批准的条目不进入已冻结技术栈。
