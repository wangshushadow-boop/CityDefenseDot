# UI — 界面、ReadModel 与交互流程

> 版本 0.1（设计内容未变；目录版 0.2） | 状态：详细设计提案，待评审与实现 | 所属工程：recollection（古代中国风原创沙盒）
> 实现目录：`game/presentation/ui/` | 总体基线：[§15.1、§1.4、§2.3、§16](../../../../game_design.md) | [系统索引](../../../README.md)

本文在总体规格书约束内补充实现级设计。接口为语言无关伪代码，字段及新增参数为拟定契约；未标明已冻结的数值需经 ADR/测试确认。公共语义见[公共契约](../../../../architecture/common_contracts.md)。测试均为待执行规格，不代表功能已实现。

## 1. 职责与边界

负责菜单、战役地图各面板、人物家族、军队库存交易、王国领地、任务百科、场景互动、部署战斗 HUD、结算及多人大厅。仅维护本地视图状态；权威查询和变更通过 APP/Network，不绑定可变领域对象。

**协作边界：** CON、APP/MP 公共查询和命令端口、INPUT/CAMERA/VIS/AUD 的表现端口。跨模块写入经 application 或权威运行时编排；不直接访问其他模块私有仓库。

## 2. 数据所有权与生命周期

ViewModel、筛选、选择、窗口和待提交命令状态归 UI；来源 ReadModel 只读且带 revision，真实金钱、兵力、伤亡不在 UI 写。

## 3. 代码组织

以下为建议的文件职责（按选定语言补扩展名；不是已有源码）：

```text
screens/frontend / character_creation / campaign_map
screens/character_clan / party_inventory / trade_workshop
screens/settlement / kingdom / quest_encyclopedia
screens/encounter / deployment / battle_hud / results
screens/multiplayer_lobby / scoreboard / settings
view_models / widgets / navigation / localization / accessibility
```

## 4. 数据模型与约束

`ReadModel{scope_id,revision,visibility_context,fields}`；`PendingAction{command_id,preview,expected_revision,status,error}`；`UIRoute{session_state,screen_id,modal_stack}`；`Settings{locale,ui_scale,subtitles,color_palette,input_profile,...}`。切换 Session scope 时清除过期窗口和回执。

## 5. 公共接口

```text
open_screen(route,view) -> Result<Unit>
refresh_view(model_delta) -> Unit
preview_action(command_draft) -> Preview
submit_action(command) -> PendingAction
on_receipt(receipt) -> Unit
apply_local_settings(settings) -> Result<Unit>
```

所有修改型接口须在所属权威阶段提交；查询不推进时间。命令失败遵循公共错误码；空结果与非法输入分开。非幂等的外部请求须使用稳定请求 ID 或事务回执。

## 6. 核心算法与运行流程

面板进入→读取合法 ReadModel→用户操作构建 command draft→需要时调用预览报价/兵力/成本→确认→提交→以回执/新 revision 刷新，不乐观扣真实资产。列表分页/虚拟化，批量 UI 更新。地图信息按发现/传闻标识，百科遵守可见性。支持键鼠/手柄导航、焦点管理、按键重映射入口、字幕字号、色盲区分、镜头晃动和血腥显示开关。主菜单、加载、退出由 Session 控制。

## 7. 配置、异常与安全边界

本地化使用键+参数，不硬编码剧情；UI 缓存不可参与结算。过期报价/权限变化显示原因并重新预览。模态菜单和战役暂停由 Session 规则协调；多人 UI 暂停不停止赛局。

## 8. 表现及可观测性

本模块负责玩家可见信息架构；详细视觉风格及原创 UI 资产另见内容标准。

**性能与诊断：** 虚拟化长列表；增量 ReadModel 更新；监控 UI frame cost、重建次数、命令等待时间。

## 9. 验收用例

| 测试 ID | 需求 ID / 质量门禁 | Given（前置） | When（操作） | Then（判据） |
|---|---|---|---|---|
| T-UI-01 | UX-01 | 键鼠、手柄及回退/取消 | 完成招募交易战斗等主流程 | 无阻断，取消不改数据 |
| T-UI-02 | UX-02 | 多编队部署和命令失败 | 操作 HUD | 选择、目标、当前命令和失败原因准确 |
| T-UI-03 | UX-03 | 切换语言、1080p/不同分辨率及字号 | 遍历主界面 | 文本无溢出阻断，使用本地化键 |
| T-UI-04 | ACC-01 | 重新映射、色盲/字幕设置 | 保存重启 | 设置恢复且主流程可操作 |

## 10. 完成条件与实施约束

- 公开接口与本模块数据所有权已落地；所有配置通过内容编译或启动校验。
- 本章测试及受影响跨模块验收通过，保留实际运行报告；没有已知的状态一致性/权限阻断缺陷。
- 接口或存档结构变化同步契约、迁移与 ADR；性能目标需在指定基准上测量，不以空场或 mock 数据代替。
- 实现和测试变更限于本模块及获准契约；不得把尚未实现的部分伪装成已完成。

## 文档导航（镜像目录）

- 主要实现目录：`game/presentation/ui/`；权威设计：本文件。
- 上级入口：[上级模块 / 分组](../README.md)；[全部模块索引](../../../README.md)。
