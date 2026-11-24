# 结构化数据规范

`development_task.schema.json` 定义研发执行任务的字段约束（与工作流一致）。它不是游戏数据 schema。游戏 Def/Save/Network schema 在 P0/P1 依据公共契约及技术选型建立，不先生成重复的业务类型。`development/check_project.py` 使用标准库做必要结构和引用校验；完整 JSON Schema 校验可在 P1 接入正式工具。
