# P2-FIELD-INTEGRATION-019 编队修订与步骑切换

开发候选基于 `867fb810890ab8804ff41eb916ad63a837152b6f`，由 revision_fix 在隔离工作树 p2-field-revision 完成。对应 MIS-RT、BAT-01、MIS-02，以及 T-MIS-RT-02 和 T-TEST-01 的野战切片。

真实河原野战在 500 人同场、1000 人预留、第 1304 个权威步报告 `StaleVersion/formation_revision`。诊断记录显示第 7 编队的控制/命令修订从 `[0,2]` 退回 `[0,1]`，原步重试两次仍然失败。此前已有 503 名兵员入场。

`field_pipeline.gd` 中切换骑手的运动模式会重建编队各成员的运动路线。原代码删除了整个布局缓存，导致已经发布的修订丢失。现在只在当前固定步的拷贝中使布局签名失效，保留编队锚点和单调修订。完成新的槽位/路线投影时递增修订，随后若有系统拒绝该步，整个候选随事务一起回滚。沿用既有端口及 AI 的旧修订校验。

## 实际自测

下表中的 Godot 命令使用 4.7.2 Standard Windows console、`--headless --path game --script`。独立日志见该工作树本地 `out/revision/<运行名>/godot.log`。

| 运行名 | 脚本或命令 | 实测结果 |
|---|---|---|
| baseline-short | `res://tests/p2/field_revision/run.gd`，原业务代码 | 退出 1。12 项中 2 项失败。已形成楔形阵的骑兵在第 3 步下马，首次及重试均因修订回退在 AI 阶段拒绝。 |
| final-short | 同一脚本，修复后 | 退出 0，16 项通过。拒绝旧玩家控制修订。下马后的末端故障保持上一状态，重试仅递增一次；再上马时恢复原坐骑。 |
| existing-pipeline | `res://tests/p2/field_pipeline/run.gd -- --brains=res://mission/runtime/field_brains.gd --mount --casualties --large` | 退出 0。346 项断言，含实际倒地、补员、步骑变化及千人预留。 |
| existing-ai | `res://tests/p2/field_brains/run.gd` | 退出 0。1316 项，三层 AI 均工作，产生 13 次实际命中。 |
| 依赖与文件 | `python -B ci/gates.py dependencies`、`git diff --check` | 均退出 0。 |

变更限于 `game/mission/runtime/field_pipeline.gd`、`game/tests/p2/field_revision/run.gd` 和本报告。图形帧率和目标设备性能归阶段验收复测。
