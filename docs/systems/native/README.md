# NATIVE — 可选原生热路径与 GDExtension

> 版本 0.1（设计内容未变；目录版 0.2） | 状态：详细设计提案，待评审与实现 | 所属工程：recollection（古代中国风原创沙盒）
> 实现目录：`native/` | 总体基线：[§19.1–19.4、§20.1、§23](../../game_design.md) | [系统索引](../README.md)

本文在总体规格书约束内补充实现级设计。接口为语言无关伪代码，字段及新增参数为拟定契约；未标明已冻结的数值需经 ADR/测试确认。公共语义见[公共契约](../../architecture/common_contracts.md)。测试均为待执行规格，不代表功能已实现。

## 1. 职责与边界

仅在 P0/Profiler 证明需要时实现 C++ GDExtension 或其他原生批量计算：感知、近邻、阵型槽位、碰撞候选、批量模拟。业务语义、权威顺序、规则契约不变；不另实现一套 Combat 或 AI 真值。

**协作边界：** CON 版本化批量接口、CORE 调度、INF-ENGINE 适配；不从 native 反向调用可变场景树。跨模块写入经 application 或权威运行时编排；不直接访问其他模块私有仓库。

## 2. 数据所有权与生命周期

NativeBuffer、批量输入输出、ABI 版本与性能计数；数据所有权仍归调用域，原生模块只持有有界临时缓存。

## 3. 代码组织

以下为建议的文件职责（按选定语言补扩展名；不是已有源码）：

```text
include/abi / batch_types / version
src/spatial_index / slot_assignment / candidate_generation
src/batch_math / extension_binding
benchmarks/reference_compare / stress
build/ (构建产物不提交)
```

## 4. 数据模型与约束

`BatchHeader{abi_version,scope,tick,count,stride,capacity}`；输入只读 SoA 数组，输出固定容量结果/错误码；所有句柄带 generation。跨语言禁止传裸领域对象或持有 GC 指针。

## 5. 公共接口

```text
native_version() -> AbiVersion
build_spatial_index(batch) -> Result<IndexHandle>
query_neighbors_batch(index,requests,output_capacity) -> BatchResult
assign_slots_batch(input) -> BatchResult
release_scope(scope) -> Unit
```

所有修改型接口须在所属权威阶段提交；查询不推进时间。命令失败遵循公共错误码；空结果与非法输入分开。非幂等的外部请求须使用稳定请求 ID 或事务回执。

## 6. 核心算法与运行流程

先用脚本/托管参考实现跑真实基准；定位热点后定义同语义批量接口、记录基准，原生实现与参考实现做固定种子差分测试。跨语言按批次调用，预分配缓冲；输入校验长度、stride、容量和版本；多线程仅计算，提交仍由权威线程。若原生不可用或版本不符，选择明确 fallback 或拒绝启动相关 profile。

## 7. 配置、异常与安全边界

不从第一天强制 C++/ECS；ABI 升级重新验证平台兼容与行为；内存越界、异常、释放及线程安全测试。原生性能收益须大于复制和绑定开销。

## 8. 表现及可观测性

无独立界面；通过公开查询、回执或已提交事件提供可观察结果。

**性能与诊断：** 记录批处理规模、跨语言调用成本、CPU/缓存/内存、P95；版本和平台构建可复现。

## 9. 验收用例

| 测试 ID | 需求 ID / 质量门禁 | Given（前置） | When（操作） | Then（判据） |
|---|---|---|---|---|
| T-NATIVE-01 | BAI-06 / §19.4 | 相同混合战场及脚本/原生实现 | 差分、压测 | 结果语义一致，记录实际性能变化 |
| T-NATIVE-02 | §20.2 | 错误 ABI、数组长度或已释放 scope | 调用 | 安全拒绝，不访问越界 |
| T-NATIVE-03 | BAT-05 | 50 次场景切换 | 释放 native buffers | 无内存泄漏 |

## 10. 完成条件与实施约束

- 公开接口与本模块数据所有权已落地；所有配置通过内容编译或启动校验。
- 本章测试及受影响跨模块验收通过，保留实际运行报告；没有已知的状态一致性/权限阻断缺陷。
- 接口或存档结构变化同步契约、迁移与 ADR；性能目标需在指定基准上测量，不以空场或 mock 数据代替。
- 实现和测试变更限于本模块及获准契约；不得把尚未实现的部分伪装成已完成。

## 文档导航（镜像目录）

- 主要实现目录：`native/`；权威设计：本文件。
- 上级入口：[上级模块 / 分组](../README.md)；[全部模块索引](../README.md)。

| 对应实现目录 | 设计入口 | 类型 |
|---|---|---|
| `native/include/` | [原生扩展接口](include/README.md) | 父规格子目录 |
| `native/src/` | [原生计算实现](src/README.md) | 父规格子目录 |
| `native/benchmarks/` | [原生基准](benchmarks/README.md) | 父规格子目录 |
