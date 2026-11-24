# 海战扩展代码（EXT）

> 对应计划实现目录：`game/addons/naval/`
> 文档类型：共享规格入口（非新增独立 SDD）

插件注册及兼容性入口，战略与实时海战由下级模块分别实现。

权威规格：[NAVAL-P — 海战扩展：内容包、工具与兼容](../../content/expansions/naval/README.md)。 此目录与上述 SDD 共用同一模块 ID、需求与测试用例，不维护第二份规格。

[上级入口](../README.md) · [全部模块索引](../../../README.md)

## 下级目录

| 对应实现目录 | 设计入口 | 类型 |
|---|---|---|
| `game/addons/naval/campaign/` | [海战扩展：战略水域、港口、舰队](campaign/README.md) | 独立 SDD |
| `game/addons/naval/mission/` | [海战扩展：船舶运动、接舷、战斗 AI](mission/README.md) | 独立 SDD |
