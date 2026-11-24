# SHRULE — 公共规则、数值与效果计算

> 版本 0.1（设计内容未变；目录版 0.2） | 状态：详细设计提案，待评审与实现 | 所属工程：recollection（古代中国风原创沙盒）
> 实现目录：`game/shared/rules/` | 总体基线：[§3.3、§5、§6、§7、§11、§17](../../../../game_design.md) | [系统索引](../../../README.md)

本文在总体规格书约束内补充实现级设计。接口为语言无关伪代码，字段及新增参数为拟定契约；未标明已冻结的数值需经 ADR/测试确认。公共语义见[公共契约](../../../../architecture/common_contracts.md)。测试均为待执行规格，不代表功能已实现。

## 1. 职责与边界

提供稳定 IRule/Policy 接口、数值限幅、取整、效果叠加、分项解释、规则注册键和确实跨域共享的计算原语。特定价格、近战伤害、家族政治等实现留在其领域，不建立全局巨型 RuleManager。

**协作边界：** CON/DEF。跨模块写入经 application 或权威运行时编排；不直接访问其他模块私有仓库。

## 2. 数据所有权与生命周期

规则配置在会话内只读；规则计算无副作用，状态由调用者所属领域保存。

## 3. 代码组织

以下为建议的文件职责（按选定语言补扩展名；不是已有源码）：

```text
rule_interface / rule_key
numeric_policy / rounding / clamping
effect_stack / modifier_scope
explanation / validation
```

## 4. 数据模型与约束

`RuleInput{context_stamp,def_ids,values}`；`Modifier{source_id,scope,group,operation,value,priority}`；`Breakdown{base,steps[],final,rounding,config_version}`。默认建议顺序：基础→固定加减→分组倍率→限幅→取整，领域可注册明确不同的顺序。

## 5. 公共接口

```text
evaluate<I,O>(rule_key,input,config,rng?) -> O
apply_effects(base, modifiers, scope) -> Breakdown
round_money(value, direction) -> Money
validate_config(rule_key, values) -> ValidationReport
```

所有修改型接口须在所属权威阶段提交；查询不推进时间。命令失败遵循公共错误码；空结果与非法输入分开。非幂等的外部请求须使用稳定请求 ID 或事务回执。

## 6. 核心算法与运行流程

过滤作用域和互斥组，按 priority/source_id 稳定排序，先应用固定加减再倍率（乘区由配置定义），最后范围和取整。概率类规则显式注入 RNG；不允许通过计算函数写世界。保留分项方便 UI 和调试；同版本相同输入可重复。

## 7. 配置、异常与安全边界

拒绝 NaN/Inf、非法区间、除零、溢出；货币使用确定取整；配置项具有单位、范围和默认值来源，具体数值由领域确认。不同伤害类型不能误用经济规则。

## 8. 表现及可观测性

无独立界面；通过公开查询、回执或已提交事件提供可观察结果。

**性能与诊断：** 高频规则预编译配置；分项解释按需生成，避免每帧为所有 Agent 分配字符串。

## 9. 验收用例

| 测试 ID | 需求 ID / 质量门禁 | Given（前置） | When（操作） | Then（判据） |
|---|---|---|---|---|
| T-SHRULE-01 | CHR-01 | 互斥或不同作用域天赋 | 计算效果 | 仅合法组生效，分项可解释 |
| T-SHRULE-02 | ECO-03 | 买卖价格为小数 | 计算报价 | 买向上卖向下，金额整数 |
| T-SHRULE-03 | COM-03 | 护甲值与输入越界 | 计算规则 | 显式拒绝或限幅，无 NaN |

## 10. 完成条件与实施约束

- 公开接口与本模块数据所有权已落地；所有配置通过内容编译或启动校验。
- 本章测试及受影响跨模块验收通过，保留实际运行报告；没有已知的状态一致性/权限阻断缺陷。
- 接口或存档结构变化同步契约、迁移与 ADR；性能目标需在指定基准上测量，不以空场或 mock 数据代替。
- 实现和测试变更限于本模块及获准契约；不得把尚未实现的部分伪装成已完成。

## 文档导航（镜像目录）

- 主要实现目录：`game/shared/rules/`；权威设计：本文件。
- 上级入口：[上级模块 / 分组](../README.md)；[全部模块索引](../../../README.md)。
