# WORLD — 世界地图、时钟、交通、情报

> 版本 0.1（设计内容未变；目录版 0.2） | 状态：详细设计提案，待评审与实现 | 所属工程：recollection（古代中国风原创沙盒）
> 实现目录：`game/campaign/world/` | 总体基线：[§4、§17.5、§19](../../../../game_design.md) | [系统索引](../../../README.md)

本文在总体规格书约束内补充实现级设计。接口为语言无关伪代码，字段及新增参数为拟定契约；未标明已冻结的数值需经 ADR/测试确认。公共语义见[公共契约](../../../../architecture/common_contracts.md)。测试均为待执行规格，不代表功能已实现。

## 1. 职责与边界

管理地图位置、日历、天气、交通图、地图移动、可见情报与潜在遭遇；队伍名册属于 PARTY，实际遭遇预留属于 ENC。世界地图表现不构成真实地理或战场导航。

**协作边界：** CORE/CON/DEF；读取 PARTY、POL、SET 的授权投影；将接触候选传 APP。跨模块写入经 application 或权威运行时编排；不直接访问其他模块私有仓库。

## 2. 数据所有权与生命周期

World 拥有战略坐标、位置索引、路线进度、时钟/天气状态、情报记录；Party.pos 是 World 的写入视图，不维护第二份可写位置。路线缓存和索引可重建。

## 3. 代码组织

以下为建议的文件职责（按选定语言补扩展名；不是已有源码）：

```text
calendar / time_scale
world_map / region_graph / terrain_cost
party_motion / route_planner / contact_detector
weather_system / visibility_index / intel_store
world_queries / world_commands
```

## 4. 数据模型与约束

`MapNode{id,pos,region,terrain}`；`TravelEdge{from,to,length,terrain,access_tags,open}`；`Route{party_id,edge_ids,index,progress,revision}`；`IntelRecord{observer_ref,target_id,last_position,last_seen_minute,confidence,source}`；`WeatherCell{region_id,state,until_minute}`。战略单位由地图定义固定；战场米制仅由场景选取转换。

## 5. 公共接口

```text
MoveParty(party_id, destination, expected_revision) -> Receipt
SetTimeScale(scale) -> Receipt
plan_route(query, allowed_edges) -> Result<Route>
step_movement(delta_game_min, snapshot) -> ContactCandidate[]
visible_entities(observer, at_minute) -> VisibleWorldView
select_scene_for_encounter(position, seed) -> SceneDefId
```

所有修改型接口须在所属权威阶段提交；查询不推进时间。命令失败遵循公共错误码；空结果与非法输入分开。非幂等的外部请求须使用稳定请求 ID 或事务回执。

## 6. 核心算法与运行流程

使用 A*/Dijkstra 搜索授权道路，边成本按长度/速度和危险计算；速度 = clamp(base*terrain*weather*burden*mount*morale*skill,min,max)，载重、伤员等来自只读投影。分步积分并检查两条队伍移动线段最小同时距离，接触立即生成候选并交 APP 验证敌对与预留。地图动态边版本变化使相关路径失效；天气按独立 RNG 流变更。情报距离、地形、昼夜、侦察技能决定发现；不可见只读取最后已知位置与时效。

## 7. 配置、异常与安全边界

`movement_step_min=1–5`、`party_behavior_min=10–60` 为初始范围；边代价非负，速度最小值正数（不可移动另行设状态）。不可达返回 NotFound/Unavailable；停战/桥断使订单重新评估。不可把全局索引直接交给玩家或 AI。

## 8. 表现及可观测性

地图图标区分已知/最后见到/传闻；路径预览和预计时间来自同一移动规则；暂停/速度档位按 Session 回执更新。

**性能与诊断：** 按区域索引接触候选，禁止全队伍两两比较；路线缓存按图版本与能力键；记录查询数量、可见候选、接触漏检。

## 9. 验收用例

| 测试 ID | 需求 ID / 质量门禁 | Given（前置） | When（操作） | Then（判据） |
|---|---|---|---|---|
| T-WORLD-01 | WLD-01 | 两支相向队伍跨越接触半径 | 三种速度推进 | 均发生一次接触，不跳过遭遇 |
| T-WORLD-02 | WLD-03 | 敌军离开观察范围 | 查询和 AI 规划 | 只得到旧情报，不泄漏实时坐标 |
| T-WORLD-03 | WLD-04 | 道路关闭、天气变化 | 移动中更新 | 路线版本失效并合法重算或停留 |
| T-WORLD-04 | WLD-05 | 同种子与定义 | 创建地图与初始单位 | 拓扑/初始位置一致 |

## 10. 完成条件与实施约束

- 公开接口与本模块数据所有权已落地；所有配置通过内容编译或启动校验。
- 本章测试及受影响跨模块验收通过，保留实际运行报告；没有已知的状态一致性/权限阻断缺陷。
- 接口或存档结构变化同步契约、迁移与 ADR；性能目标需在指定基准上测量，不以空场或 mock 数据代替。
- 实现和测试变更限于本模块及获准契约；不得把尚未实现的部分伪装成已完成。

## 文档导航（镜像目录）

- 主要实现目录：`game/campaign/world/`；权威设计：本文件。
- 上级入口：[上级模块 / 分组](../README.md)；[全部模块索引](../../../README.md)。
