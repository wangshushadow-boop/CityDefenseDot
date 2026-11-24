# INF-CONTENT — 数据包编译、MOD 注册与配置合并

> 版本 0.1（设计内容未变；目录版 0.2） | 状态：详细设计提案，待评审与实现 | 所属工程：recollection（古代中国风原创沙盒）
> 实现目录：`game/infrastructure/content/` | 总体基线：[§17.3、§18.2、§21、§25](../../../../game_design.md) | [系统索引](../../../README.md)

本文在总体规格书约束内补充实现级设计。接口为语言无关伪代码，字段及新增参数为拟定契约；未标明已冻结的数值需经 ADR/测试确认。公共语义见[公共契约](../../../../architecture/common_contracts.md)。测试均为待执行规格，不代表功能已实现。

## 1. 职责与边界

扫描/解析/校验内容包、依赖与补丁、编译只读 DefinitionRegistry、资源索引、内容哈希和版本化扩展注册。运行时业务不得随意修改定义；代码 MOD 不是默认沙箱安全。

**协作边界：** CON/DEF/CORE、INF-ENGINE 资源端口；BOOT 装配注册点；ADDONS/TOOLS 共用验证器。跨模块写入经 application 或权威运行时编排；不直接访问其他模块私有仓库。

## 2. 数据所有权与生命周期

PackageManifest、ResolvedPackageSet、ValidationReport、CompiledContent、ResourceIndex 归本模块；内容快照会话内不可变。

## 3. 代码组织

以下为建议的文件职责（按选定语言补扩展名；不是已有源码）：

```text
package_scanner / manifest_parser / dependency_solver
patch_engine / config_merge / schema_validator
reference_validator / content_compiler / content_hash
resource_index / extension_registry / trust_policy
```

## 4. 数据模型与约束

`Manifest{id,version,requires,conflicts,load_after,game_api_version,license,entrypoints}`；`Patch{op:add|replace|remove,def_id,path,value,source}`；`CompiledContent{registry,resources,extension_points,hash,config_provenance}`。ID namespace:type/name；明确补丁顺序和冲突。

## 5. 公共接口

```text
scan_packages(paths) -> Manifest[]
resolve_packages(selection,game_api) -> Result<LoadOrder>
compile(order,overrides) -> Result<CompiledContent>
validate_package(package) -> ValidationReport
register_extension(key,implementation,trust) -> Result<Unit>
check_save_or_network_compatibility(manifest,compiled) -> Result<Unit>
```

所有修改型接口须在所属权威阶段提交；查询不推进时间。命令失败遵循公共错误码；空结果与非法输入分开。非幂等的外部请求须使用稳定请求 ID 或事务回执。

## 6. 核心算法与运行流程

扫描→路径/大小检查→manifest 解析→依赖拓扑排序→版本冲突验证→稳定 ID 合并和补丁→schema/引用/DAG/场景/动画/文本/授权验证→编译运行时快照→规范化序列化计算哈希→注册规则、任务、战术和 UI 扩展。配置覆盖基础→资料片→MOD 顺序→开局→合法单人设置，记录来源。多人内容由服务器固定且匹配哈希，外观包白名单。

## 7. 配置、异常与安全边界

拒绝路径穿越、重复 ID 未声明补丁、循环、缺引用、超限资源和未知关键 schema。可信代码 MOD 需明确用户信任；不可信禁用，不宣称脚本安全隔离。热重载只开发模式重开测试场景；生产存档按包清单加载。

## 8. 表现及可观测性

MOD 管理界面展示依赖、冲突、版本和信任提示；载入失败解释缺包。

**性能与诊断：** 缓存增量编译但发布全量验证；记录扫描/编译时间、资源数量、哈希和来源。

## 9. 验收用例

| 测试 ID | 需求 ID / 质量门禁 | Given（前置） | When（操作） | Then（判据） |
|---|---|---|---|---|
| T-INF-CONTENT-01 | EXT-01 / MOD-05 | 新增文化/兵种/装备/规则/任务/场景/AI MOD | 编译加载 | 通过公开扩展点不改核心 |
| T-INF-CONTENT-02 | EXT-02 | 循环依赖、补丁冲突、危险路径、多人哈希不符 | 验证 | 拒绝并定位包 |
| T-INF-CONTENT-03 | EXT-03 | 发布包 API 版本和许可证齐全 | 编译发布 | 输出可复现哈希和报告 |
| T-INF-CONTENT-04 | MIS-03 | 场景缺出生/目标引用 | 校验 | 构建阻断 |

## 10. 完成条件与实施约束

- 公开接口与本模块数据所有权已落地；所有配置通过内容编译或启动校验。
- 本章测试及受影响跨模块验收通过，保留实际运行报告；没有已知的状态一致性/权限阻断缺陷。
- 接口或存档结构变化同步契约、迁移与 ADR；性能目标需在指定基准上测量，不以空场或 mock 数据代替。
- 实现和测试变更限于本模块及获准契约；不得把尚未实现的部分伪装成已完成。

## 文档导航（镜像目录）

- 主要实现目录：`game/infrastructure/content/`；权威设计：本文件。
- 上级入口：[上级模块 / 分组](../README.md)；[全部模块索引](../../../README.md)。
