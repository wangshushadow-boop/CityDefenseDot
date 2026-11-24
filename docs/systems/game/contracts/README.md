# CON — 公共契约与版本管理

> 版本 0.1（设计内容未变；目录版 0.2） | 状态：详细设计提案，待评审与实现 | 所属工程：recollection（古代中国风原创沙盒）
> 实现目录：`game/contracts/` | 总体基线：[§3.3、§17、§20.2](../../../game_design.md) | [系统索引](../../README.md)

本文在总体规格书约束内补充实现级设计。接口为语言无关伪代码，字段及新增参数为拟定契约；未标明已冻结的数值需经 ADR/测试确认。公共语义见[公共契约](../../../architecture/common_contracts.md)。测试均为待执行规格，不代表功能已实现。

## 1. 职责与边界

定义公开 ID、值对象、命令、查询、回执、事件、跨域快照、意图、协议与版本元信息。保持纯数据且无引擎依赖；不得容纳具体领域业务、可变仓库、全局服务定位或万能管理器。

**协作边界：** 无业务模块依赖；CORE 可以使用契约基础类型，禁止相互 import（基础 Result/Id 定义仅在 core 或 contracts 中择一，本提案按公共类型在 contracts、调度在 core）。跨模块写入经 application 或权威运行时编排；不直接访问其他模块私有仓库。

## 2. 数据所有权与生命周期

契约对象不可变，创建者负责校验基础结构，处理器负责状态和授权；SchemaVersion 单调演进；运行时对象由各自领域拥有。

## 3. 代码组织

以下为建议的文件职责（按选定语言补扩展名；不是已有源码）：

```text
ids / units / errors
commands / queries / receipts
encounter_spec / mission_result / formation_order
simulation_intents / events
ports / version / compatibility
```

## 4. 数据模型与约束

以 §17.2、17.4 原字段为最低规范；补充 `CommandEnvelope{command_id,actor_ref,expected_revision?,issued_tick?,sequence?,payload}`、`EventEnvelope{event_id,scope_id,revision,tick?,type,payload}`、`SnapshotStamp{scope_id,revision,tick?,nav_revision?}`。AgentHandle 为 `(index,generation)` 且配套 mission_id；DefId 为 namespace:type/name；持久 ID 类型不互换。完整字段和公共错误语义见 architecture/common_contracts.md。

## 5. 公共接口

```text
validate_shape(type, value, version) -> Result<Value>
encode_value(type, value) -> Bytes
decode_value(type, bytes, version) -> Result<Value>
check_compatible(producer, consumer, content_hash) -> Result<Unit>
map_error(code, args) -> LocalizedMessageKey
```

所有修改型接口须在所属权威阶段提交；查询不推进时间。命令失败遵循公共错误码；空结果与非法输入分开。非幂等的外部请求须使用稳定请求 ID 或事务回执。

## 6. 核心算法与运行流程

命令数据结构校验先于处理器；快照输出复制或只读视图，消费者不可持有写引用。结果验证包括每个源槽唯一终态、英雄 count=1、版本和来源一致；数据扩展用版本化命名空间，不把动态脚本藏入参数。兼容性检查区分存档格式、内容 API、网络协议和运行时消息。

## 7. 配置、异常与安全边界

枚举不得复用旧语义；字段增删需迁移或提升协议主版本；未知关键字段拒绝，允许可忽略的扩展按清单处理。金钱整数、战略分钟整数、战场米/秒、角度约定在边界转换。禁止 Node/RID/线程指针。

## 8. 表现及可观测性

无独立界面；通过公开查询、回执或已提交事件提供可观察结果。

**性能与诊断：** 编码批量数组，限制长度和嵌套深度；契约检查覆盖边界而非每帧反复序列化。

## 9. 验收用例

| 测试 ID | 需求 ID / 质量门禁 | Given（前置） | When（操作） | Then（判据） |
|---|---|---|---|---|
| T-CON-01 | BAT-03 | 结果中的 source_slot 重复或版本错误 | 验证 | 拒绝并定位字段，世界无写入 |
| T-CON-02 | NET-05 | 客户端协议主版本或内容哈希不符 | 握手 | 拒绝并说明兼容版本 |
| T-CON-03 | SAV-03 | 旧字段版本及未知关键字段 | 解码 | 迁移受支持版本，否则明确拒绝 |

## 10. 完成条件与实施约束

- 公开接口与本模块数据所有权已落地；所有配置通过内容编译或启动校验。
- 本章测试及受影响跨模块验收通过，保留实际运行报告；没有已知的状态一致性/权限阻断缺陷。
- 接口或存档结构变化同步契约、迁移与 ADR；性能目标需在指定基准上测量，不以空场或 mock 数据代替。
- 实现和测试变更限于本模块及获准契约；不得把尚未实现的部分伪装成已完成。

## 文档导航（镜像目录）

- 主要实现目录：`game/contracts/`；权威设计：本文件。
- 上级入口：[上级模块 / 分组](../README.md)；[全部模块索引](../../README.md)。
