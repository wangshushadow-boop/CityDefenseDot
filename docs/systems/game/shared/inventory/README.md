# INV — 库存、账户、账本与资源事务

> 版本 0.1（设计内容未变；目录版 0.2） | 状态：详细设计提案，待评审与实现 | 所属工程：recollection（古代中国风原创沙盒）
> 实现目录：`game/shared/inventory/` | 总体基线：[§6、§7.1、§17.5](../../../../game_design.md) | [系统索引](../../../README.md)

本文在总体规格书约束内补充实现级设计。接口为语言无关伪代码，字段及新增参数为拟定契约；未标明已冻结的数值需经 ADR/测试确认。公共语义见[公共契约](../../../../architecture/common_contracts.md)。测试均为待执行规格，不代表功能已实现。

## 1. 职责与边界

唯一负责物品数量、独立物品实例、货币、影响力等账户余额及流水。业务域决定何时发起交易/生产/奖励，INV 校验并准备资源写集，应用层原子提交；不得自行决定市场价格或战争奖励。战场弹药/临时装备归 Combat，不能直接操作长期库存。

**协作边界：** CON/DEF；APP 负责跨域事务装配。跨模块写入经 application 或权威运行时编排；不直接访问其他模块私有仓库。

## 2. 数据所有权与生命周期

Inventory、Account、LedgerEntry、ItemInstance、ResourceReservation 归本模块；Market.stock 与 Party.inventory_id 为引用/视图，禁止另建可写市场库存。

## 3. 代码组织

以下为建议的文件职责（按选定语言补扩展名；不是已有源码）：

```text
inventory / item_instance / stock_stack
account / ledger_entry / reservation
transfer / consume / mint / burn
transaction_plan / invariant_checker
```

## 4. 数据模型与约束

`StockKey{def_id,quality,modifier_id?}`；`Inventory{id,stacks,instance_ids,capacity_policy}`；`Account{id,currency,balance}`；`LedgerEntry{txn_id,line_id,resource,src?,dst?,amount,reason,source_ref}`；`ResourceReservation{id,inventory_or_account,quantity,owner,expiry}`。货币整数；每个独立物品仅有一个持有位置（库存或装备）。

## 5. 公共接口

```text
prepare_transfer(src,dst,resource,qty,reason) -> ChangeSet
prepare_exchange(lines, expected_versions) -> ChangeSet
reserve(resource_ref, qty, owner) -> Result<ReservationId>
release(reservation_id) -> ChangeSet
mint_or_burn(resource,qty,authorized_reason,source_id) -> ChangeSet
balance(account) -> Money
available(inventory,stock_key) -> Count
```

所有修改型接口须在所属权威阶段提交；查询不推进时间。命令失败遵循公共错误码；空结果与非法输入分开。非幂等的外部请求须使用稳定请求 ID 或事务回执。

## 6. 核心算法与运行流程

将交换、生产、消耗、税收等表示为有来源/去向的流水；先汇总同一资源净变动并锁定版本，检查可用量和容量，再生成写集。所有账户借贷成对；显式产生/回收需要授权 reason。唯一物品转移原子移除旧位置并插入新位置。临时预留不改变总余额，消费时释放对应预留。

## 7. 配置、异常与安全边界

禁止负数量/溢出、无来源铸币、同实例多持有者。事务 ID 重复不再写账；不同内容冲突。资金/货物必须同一事务完成，不能先扣款再靠事件补货。库存容量按业务注入规则。

## 8. 表现及可观测性

提供资金、容量、流水原因及提交失败反馈给各业务 UI。

**性能与诊断：** 账本按 ID 索引并支持安全归档；批量流水检查 O(变更项) 而非 O(全世界库存)。

## 9. 验收用例

| 测试 ID | 需求 ID / 质量门禁 | Given（前置） | When（操作） | Then（判据） |
|---|---|---|---|---|
| T-INV-01 | ARM-05 / ECO-03 | 一方货物或金钱不足 | 提交交换 | 双方余额、库存、流水不变 |
| T-INV-02 | CHR-02 | 同一装备被两个槽位引用 | 交换或校验 | 拒绝重复持有 |
| T-INV-03 | ECO-03 | 重复交易 ID、不同 payload | 提交 | 相同返回原回执，不同 Conflict |
| T-INV-04 | §22.3 | 随机资源流水 | 属性测试 | 总量等于初始+合法产生-合法消耗 |

## 10. 完成条件与实施约束

- 公开接口与本模块数据所有权已落地；所有配置通过内容编译或启动校验。
- 本章测试及受影响跨模块验收通过，保留实际运行报告；没有已知的状态一致性/权限阻断缺陷。
- 接口或存档结构变化同步契约、迁移与 ADR；性能目标需在指定基准上测量，不以空场或 mock 数据代替。
- 实现和测试变更限于本模块及获准契约；不得把尚未实现的部分伪装成已完成。

## 文档导航（镜像目录）

- 主要实现目录：`game/shared/inventory/`；权威设计：本文件。
- 上级入口：[上级模块 / 分组](../README.md)；[全部模块索引](../../../README.md)。
