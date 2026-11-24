# ECO — 经济、市场、商队、工坊与锻造

> 版本 0.1（设计内容未变；目录版 0.2） | 状态：详细设计提案，待评审与实现 | 所属工程：recollection（古代中国风原创沙盒）
> 实现目录：`game/campaign/economy/` | 总体基线：[§7、§8、§9.3、§17.5](../../../../game_design.md) | [系统索引](../../../README.md)

本文在总体规格书约束内补充实现级设计。接口为语言无关伪代码，字段及新增参数为拟定契约；未标明已冻结的数值需经 ADR/测试确认。公共语义见[公共契约](../../../../architecture/common_contracts.md)。测试均为待执行规格，不代表功能已实现。

## 1. 职责与边界

管理生产/消费计划、报价、市场需求、工坊、商队经济目标、锻造配方和订单；库存、金钱唯一由 INV 写，商队队伍由 PARTY 写、路线由 WORLD 写。

**协作边界：** DEF/SHRULE/INV；WORLD/SET/PARTY/CHR 只读投影与 APP 事务。跨模块写入经 application 或权威运行时编排；不直接访问其他模块私有仓库。

## 2. 数据所有权与生命周期

Market 拥有需求模型、报价版本、市场库存/账户引用；Workshop、生产设施、订单、锻造进度归 ECO；动态定义由 DEF overlay 接受事务写。

## 3. 代码组织

以下为建议的文件职责（按选定语言补扩展名；不是已有源码）：

```text
market / demand / price_rule / quote_service
production / consumption / caravan_economics
workshop / recipe / capital_plan
smithing / component_assembly / crafting_order
trade_handler / economy_day_plan
```

## 4. 数据模型与约束

`Market{id,settlement_id,inventory_id,account_id,demand_model,quote_revision}`；`Quote{id,market_id,item_id,qty,side,total,revision,valid_until}`；`Workshop{id,owner,recipe,capital_account,stock_ref,capacity,status}`；`CraftOrder{id,requirements,deadline,reward,status}`。价格、库存引用与账本快照版本绑定。

## 5. 公共接口

```text
GetMarketQuote(market, item, qty, side, trader) -> Quote
BuyGoods / SellGoods(quote_id, trader, quantity) -> ChangeSet
plan_production(day_id, snapshot) -> ResourcePlan[]
SetWorkshopRecipe(workshop,recipe) -> ChangeSet
GetCaravanOpportunity(snapshot) -> TradeOpportunity[]
CraftWeapon(hero,parts,order?) -> ChangeSet
Smelt / Refine(hero,recipe,inputs) -> ChangeSet
```

所有修改型接口须在所属权威阶段提交；查询不推进时间。命令失败遵循公共错误码；空结果与非法输入分开。非幂等的外部请求须使用稳定请求 ID 或事务回执。

## 6. 核心算法与运行流程

报价按覆盖天数 coverage=(stock+smoothing)/(daily_demand+smoothing)，mid=clamp(base*(target_days/max(coverage,epsilon))^elasticity*regional*scarcity,min,max)；买 ceil(mid*(1+价差+税+惩罚-折扣))，卖 floor(mid*(1-价差-税-惩罚+折扣))；逐批模拟库存变化。提交重验版本、库存、支付能力。日结以冻结快照规划生产、消费和运输，账本原子落地；工坊缺原料/资本减产、暂停，产品入库或上市。商队比较净利润-风险-时间成本，策略交 SAI-PARTY。锻造验证连接点、部件白名单、长度/质量、体力和材料，计算动态定义，原子扣料产物、更新订单和 XP。

## 7. 配置、异常与安全边界

配置库存目标天数、弹性、价差、价格上下限、工坊容量、锻造效果；低库存不得除零；禁止无风险即时买卖/熔炼循环套利；贸易受围城和外交合法通行约束。市场 quote_revision 在影响价格的已提交变化后递增。

## 8. 表现及可观测性

交易显示买卖数量、分段价格、总价和库存；工坊报表提供收益与原因；锻造预览合法组合、材料、体力、属性。

**性能与诊断：** 价格计算按市场/商品分组；缓存版本；日报货流、现金流、供应覆盖、价格分布、破产率。

## 9. 验收用例

| 测试 ID | 需求 ID / 质量门禁 | Given（前置） | When（操作） | Then（判据） |
|---|---|---|---|---|
| T-ECO-01 | ECO-01 | 村产原料、工坊配方、城镇需求 | 逐日模拟 | 货物有来源去向，生产运输消费形成循环 |
| T-ECO-02 | ECO-02 | 围城切断商路 | 观察库存与恢复 | 供给下降、价格变化，解围后可恢复 |
| T-ECO-03 | ECO-03 | 报价之后他人买走库存 | 提交旧报价 | StaleVersion/重新报价，不扣款 |
| T-ECO-04 | ECO-04 | 工坊原料和现金不足 | 日结 | 减产/停产，商队与工坊账本不负 |
| T-ECO-05 | ECO-05 | 非法部件与合法订单 | 分别制造 | 非法零变更；合法唯一产物，材料和经验准确 |
| T-ECO-06 | ECO-06 | 多种子十年无玩家 | 跟踪库存与货币 | 硬不变量零失败，软趋势按评审基线 |

## 10. 完成条件与实施约束

- 公开接口与本模块数据所有权已落地；所有配置通过内容编译或启动校验。
- 本章测试及受影响跨模块验收通过，保留实际运行报告；没有已知的状态一致性/权限阻断缺陷。
- 接口或存档结构变化同步契约、迁移与 ADR；性能目标需在指定基准上测量，不以空场或 mock 数据代替。
- 实现和测试变更限于本模块及获准契约；不得把尚未实现的部分伪装成已完成。

## 文档导航（镜像目录）

- 主要实现目录：`game/campaign/economy/`；权威设计：本文件。
- 上级入口：[上级模块 / 分组](../README.md)；[全部模块索引](../../../README.md)。
