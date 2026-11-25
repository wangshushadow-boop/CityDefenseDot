# P2-FIELD-INTEGRATION-016 首次取得角色时同步输入航向

开发候选，等待主 Agent 独立审查与组合根回归。开发者为 `recollection_developer/presentation`，工作区为 `.worktrees/p2-input-heading`，基线为 `a89ac81541109869e6ab0b294e02bca1587e125e`，交付形式为未提交 diff。

## 范围与变更

任务承接 P2-INPUT 和 INPUT SDD §4–6 的本地设备采样。阶段追踪需求为 BAI-06、BAT-03、NET-06、SAV-02，阶段门禁编号为 T-TEST-01 至 T-TEST-04。本次开发验证的具体行为是角色取得控制时的前进朝向、设备转向和输入重试。

- `game/presentation/input/ports/field_input.gd` 新增进程内 `align_look(heading: Vector3)`。从角色面朝的水平分量求航向，返回量化后的航向和当前俯仰，单位为弧度。键鼠和手柄从同一航向继续采样，手中按下的移动键、已有鼠标位移、前一帧的投递回执各自保留。只有水平转向输入才重新量化航向，避免静止时在正负 π 边界交替换符号。
- `game/tests/p2/field_input_handoff/run.gd` 通过 INPUT 配置、Godot 事件、提交端口和原版 v1 编解码器对照首次 W 的世界方向、后续旋转、无效朝向、投递中重入、有待重试的帧和新代际控制句柄。
- `development/reports/tasks/P2-FIELD-INTEGRATION-016.md` 记录本次运行。所有写入属于任务许可目录。v1 序列化契约、模块依赖和公共端口文件无 diff。

## 开发验证

Windows，Godot 4.7.2 Standard（ed1daf0bf），工作目录为上述工作树。下表各行执行 `Godot_v4.7.2-stable_win64_console.exe --headless --log-file <日志> --path game --script <脚本>`，使用独立日志，设置 `APPDATA` 和 `LOCALAPPDATA` 为当前进程的临时目录。

| 实际脚本 | 测试范围 | 退出码 | 结果 | 日志 |
|---|---|---|---|---|
| `res://tests/p2/field_input_handoff/run.gd` | 新增 016 专测，覆盖四个正方向、斜向、键鼠手柄、跨 π 转向、控制切换和待重试编码 | 0 | PASS，32 项 | `%TEMP%/P2-016-handoff.log` |
| `res://tests/p2/input/run.gd` | T-INPUT-01 自动化、T-INPUT-02、T-INPUT-03 | 0 | PASS，379 项 | `%TEMP%/P2-016-devices.log` |
| `res://tests/p2/input/retry_cases.gd` | 同 tick 重送、端口独立回执、取消及焦点切换 | 0 | PASS，49 项 | `%TEMP%/P2-016-retry.log` |
| `git diff --check` | 已跟踪文件差异空白校验 | 0 | PASS | 工作树 diff |

实体手柄实操为 NOT_RUN，运行时报告 `physical_pads=0`。本任务使用 Godot 的手柄轴事件执行输入路径。BOOT 组合根联测和独立验收由主 Agent 在集成后记录。
