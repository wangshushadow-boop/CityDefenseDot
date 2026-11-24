# AUD — 音频、战斗语音与音乐

> 版本 0.1（设计内容未变；目录版 0.2） | 状态：详细设计提案，待评审与实现 | 所属工程：recollection（古代中国风原创沙盒）
> 实现目录：`game/presentation/audio/` | 总体基线：[§15.2–15.3、§1.4、§21](../../../../game_design.md) | [系统索引](../../../README.md)

本文在总体规格书约束内补充实现级设计。接口为语言无关伪代码，字段及新增参数为拟定契约；未标明已冻结的数值需经 ADR/测试确认。公共语义见[公共契约](../../../../architecture/common_contracts.md)。测试均为待执行规格，不代表功能已实现。

## 1. 职责与边界

消费已确认表现事件，管理 Voice/Effects/Music/Ambience/UI 混音、空间声、音乐状态、命令语音、字幕触发和并发音源。音效不能触发权威行为；多人语音传输/管理归 MP/NET。

**协作边界：** CON/DEF、VIS ViewEvents、UI 设置、INF-ENGINE 音频适配。跨模块写入经 application 或权威运行时编排；不直接访问其他模块私有仓库。

## 2. 数据所有权与生命周期

AudioCue、VoicePool、MixerSettings 和 MusicState 为本地状态；声音事件 ID 去重；资产按内容包版本加载。

## 3. 代码组织

以下为建议的文件职责（按选定语言补扩展名；不是已有源码）：

```text
audio_event_router / cue_registry
mixer / spatial_voice_pool / priority_budget
combat_voice / command_barks / ambience
music_director / subtitle_bridge
```

## 4. 数据模型与约束

`AudioCue{id,bus,variants,priority,max_distance,concurrency,cooldown}`；`AudioRequest{event_id,cue_id,position?,priority,scope}`；`MixerSettings{master,voice,effects,music,ambience,ui,subtitles}`。

## 5. 公共接口

```text
play_event(event,listener_view) -> PlayReceipt
set_mixer(settings) -> Unit
transition_music(session_state,combat_state) -> Unit
stop_scope(scope) -> Unit
```

所有修改型接口须在所属权威阶段提交；查询不推进时间。命令失败遵循公共错误码；空结果与非法输入分开。非幂等的外部请求须使用稳定请求 ID 或事务回执。

## 6. 核心算法与运行流程

事件路由查音效键和材质/动作标签，按距离/遮挡/优先级筛选，选择独立表现随机变体并播放。语音命令/警告优先于远处普通碰撞；并发超限丢弃低优先级/淡出，保留字幕和重要提示。音乐按地图、战斗、胜败状态交叉淡化；场景退出释放全部 scope 音源。

## 7. 配置、异常与安全边界

音量设置持久化；字幕与语音/文本 ID 分离；重复事件不重复爆音，预测未确认事件可撤回。不得因未播放音效取消伤害、指令或任务。

## 8. 表现及可观测性

音量分组、字幕开关及重要命令提示。

**性能与诊断：** 监控活跃音源、优先级丢弃、混音 CPU、声音加载和内存。

## 9. 验收用例

| 测试 ID | 需求 ID / 质量门禁 | Given（前置） | When（操作） | Then（判据） |
|---|---|---|---|---|
| T-AUD-01 | AUD-01 | 500 人战斗、大量命中和命令语音 | 播放 | 音源预算内，命令可辨识 |
| T-AUD-02 | ACC-01 | 关闭音效或开启字幕 | 完成战斗 | 信息仍可访问 |
| T-AUD-03 | BAT-05 | 结束 Mission | 释放音源 | 无残留跨场景播放 |

## 10. 完成条件与实施约束

- 公开接口与本模块数据所有权已落地；所有配置通过内容编译或启动校验。
- 本章测试及受影响跨模块验收通过，保留实际运行报告；没有已知的状态一致性/权限阻断缺陷。
- 接口或存档结构变化同步契约、迁移与 ADR；性能目标需在指定基准上测量，不以空场或 mock 数据代替。
- 实现和测试变更限于本模块及获准契约；不得把尚未实现的部分伪装成已完成。

## 文档导航（镜像目录）

- 主要实现目录：`game/presentation/audio/`；权威设计：本文件。
- 上级入口：[上级模块 / 分组](../README.md)；[全部模块索引](../../../README.md)。
