# Codex 配置入口

项目级 `config.toml` 开启子 Agent，限制最多 4 个已创建并行子线程（不含主 Agent）。`agents/` 是可选的角色配置；职责正文在 [研发角色](../development/agents/README.md)。配置生效依赖客户端版本及项目受信任状态；见 [使用指南](../development/codex_setup.md)。这些文件不自动启动开发、不运行额外调度服务。
