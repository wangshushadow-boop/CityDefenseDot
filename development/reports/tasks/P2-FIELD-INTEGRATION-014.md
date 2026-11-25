# P2-FIELD-INTEGRATION-014 · 上下马与权威跳跃

开发者 ai_tx_dev，工作树 `.worktrees/p2-horse-movement`，基线 `333410e`。候选状态 CANDIDATE。依据 MOV 规格、总体设计 §10.1 及主 Agent 对本任务的跳跃补充授权，覆盖 T-MIS-RT-02、T-TEST-01 的运动切片。

| 授权文件 | 实现 |
|---|---|
| game/mission/movement/ports/field_movement.gd | 原 Body 和 roster 原位切换。set_profile 接纳当前步的 foot、mounted，包括动作伤害后的落马。保留已经提交给下游的本步位移，重置该成员的通行、直接驱动及足迹缓存，维护同一编队两个 profile 的独立路径。 |
| game/mission/movement/jump_motion.gd | 请求落在既有 MOV 的 request_jump(handle,context,stage)；复验地面、身体和头顶净空。空中横向运动、重力轨迹、顶碰与落地使用同一 Mission 物理空间，直接更新权威位置和速度。默认起跳初速 4.6 m/s、重力 11 m/s²。 |
| game/tests/p2/mount_profile/run.gd、field.tscn | 真实场景含细通道、硬墙、地面、无地面区域和两种高度的屋顶。验证重复、代际失效、回调重入、撤权、弃步重试、身体投影和主动移动。 |

实际命令为 `Godot_v4.7.2-stable_win64_console.exe --headless --path game --script res://tests/p2/<目录>/run.gd`，Windows，Godot 4.7.2 Standard、Jolt。各进程使用独立临时日志。

| 入口 | 退出码 | 实测 |
|---|---:|---|
| mount_profile | 0 | MOUNT_PROFILE checks=1092 failures=0。步骑宽度为 0.56 / 0.94 m，0.70 m 通道阻止骑手，落马后步行到目标。骑速峰值 7.938 m/s，队友沿自己的路径运动。持有 Jolt 马体和人体时直驱离开原位，改为步行后被场景墙挡在 x=-0.504 m。 |
| mount_profile 的跳跃项 | 0 | 自由上抛峰值 0.962 m、2.34 m 净高屋顶下峰值 0.540 m，均落回地面。低顶、无地面、骑乘及重复起跳均拒绝。撤回授权后同 tick 重试与原候选位姿相同。将上抛位姿同步到真实人体后，地面射线落空，高位射线命中该代际句柄。 |
| movement | 0 | T-MOV-01 至 04 的现有入口通过，两个规模的成员均完成路径接入，单步查询最多 8 个。 |
| move_intents | 0 | 4541 项通过，500/1000 直驱工作负载、门、静态墙与撤权回归均通过。 |
| field_brains | 1 | 本工作的基线尚无 013 的测试脚本，Godot 输出 File not found。组合实际运行待合并态复验。 |

开发期间首次解析跳跃代码时 GDScript 无法推断绑定回调的类型。补显式 Callable 后，重新运行包含真实起落的整套测试通过。场景级允许跳跃由 BOOT 传给 006，当前 MOV 接受经授权的技能意图。P2 完整窗口、500/1000 人战争与 8 GiB 目标设备在本任务中均为 NOT_RUN。
