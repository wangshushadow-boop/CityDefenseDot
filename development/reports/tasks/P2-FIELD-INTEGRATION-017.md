# P2-FIELD-INTEGRATION-017 战场字幕

独立音频输出与 HUD 从同一处读取已本地化且经优先级筛选的字幕。选择 HUD 展示时隐藏随音频创建的 CanvasLayer。默认独立运行继续在原位置绘制。公开音频事件及已有信号保持原有签名。测试涵盖中文坚守指令、静音可读、单一显示、选项与场景释放。初版测试同时验证语音后立刻停服，Godot 退出 0 并报告 1 项音频资源尚在使用。字幕专测以静音设置验证数据来源，语音混音继续由真实 AUD 套件验证。

## 快速退出时的音频引用

开发修正基线为 `d7b810d39c012bd8e5f4509a57bdb18feecf1319`，工作树为 `.worktrees/p2-hud-captions`。状态为 CANDIDATE，提交与独立验收由主 Agent 负责。范围为 AUD 实现、专属测试和本报告。

Godot 4.7.2 Standard 的播放器调用 `stop()` 后，混音线程仍需执行淡出，主线程在后续迭代释放播放实例。进程提前退出时，两步可能只完成一步。独立项目的单个播放器和 WAV 在 Windows/WASAPI、headless/Dummy 均可复现各一个 WAV 与 Playback 未回收。探针未加载游戏脚本、内容或总线。在原河原 QA 场景中，战斗音乐与命令语音各产生一对。该行为与 4.7.2 上游的播放状态机和退出逻辑相符。[播放状态机](https://github.com/godotengine/godot/blob/4.7.2-stable/servers/audio/audio_server.h#L260-L276) · [播放清理与退出](https://github.com/godotengine/godot/blob/4.7.2-stable/servers/audio/audio_server.cpp#L1507-L1542)

`game/presentation/audio/ports/field_audio.gd` 在已有的实际播放调用后记录弱引用。只读方法 `active_playbacks() -> Array[WeakRef]` 返回尚存的播放实例，涵盖音乐、语音、其他效果、刚抢占及静音的实例。空闲查询返回空数组。BOOT 可在释放场景前保存快照，仅在进程退出时按弱引用逐帧等待，并设置总等待时限。普通离场仍同步释放节点、总线和作用域。

## 实跑记录

命令使用 `D:/Program/Godot/Standard/Godot_v4.7.2-stable_win64_console.exe`。正式套件以 `--headless --path game --script res://tests/p2/<脚本>` 启动。Windows 真窗使用 `--display-driver windows --audio-driver WASAPI`，独立探针和音频专项使用 OpenGL，河原使用其正式 Forward+ Vulkan 配置。独立探针可用一个仅含 `config_version=5` 的临时 `project.godot`，以 `--path <临时工程> --script <backend_probe.gd 的绝对路径>` 启动。

| 脚本及参数 | 环境 | 退出码 | 实际结果 |
|---|---|---|---|
| 原 `out/p2-qa/field-final-review/controls.gd` + `field-boot2/src/game` | Dummy，原脚本强制退出 | 0 | 清理判据 FAIL，2 WAV + 2 Playback，且一个资源仍在使用；原前进方向和 HUD 断言通过 |
| `field_audio_handoff/backend_probe.gd`，无附加参数 | 独立工程，Dummy 和实际 WASAPI | 均 0 | 两者均重现 1 WAV + 1 Playback；关闭播放器节点时本地 WAV 强引用已置空 |
| 同探针，`-- --pcm --drain` | 独立工程，Dummy | 0 | 4096 个有效混音采样帧，峰值 0.377；停后观测 27.446 ms、4096 个混音帧，两弱引用均释放 |
| 同探针，`-- --pcm --drain` | 独立工程，WASAPI | 0 | 6144 帧，峰值 0.377；停后 33.140 ms、1536 个混音帧，两弱引用均释放 |
| `field_audio_handoff/retirement.gd` | Dummy / WASAPI | 均 0 | 音乐和两次语音共 3 个弱引用，都在 250 ms 上限内释放。两次实测为 68.493 / 16.235 ms，分别观察到 4096 / 1024 个停后混音帧，输出 PCM 峰值 0.110 / 0.308 |
| 同一 `field-boot2/src/game` 的临时副本，只替换候选 AUD 文件，在原 `controls.gd` 的离场前取弱引用、退出前按该信号逐帧等待 | Dummy / 窗口 WASAPI、RTX 3090 | 均 0 | 2 个真实播放（战场音乐及命令）全部释放，分别用时 39.428 / 12.192 ms。镜头前进方向点积 1.0，两边字幕均为“坚守阵地！”，无退出警告 |
| `field_audio_handoff/run.gd` | Dummy | 0 | 原字幕交接回归通过 |
| `audio/run.gd` 与 `audio/recorded_voices.gd` | Dummy | 均 0 | 500 人、250 次命中；12 音源预算实测峰值 10。T-AUD-01 自动部分、T-AUD-02、T-AUD-03 通过；48 个中英语音样本通过，实际语音混音峰值分别为 0.505 与 0.715 |

开发期间，专项首次只在 120 ms 取样，Dummy 对实际语音及渐入音乐的捕获全为零，该次 FAIL。用 350 ms 取样后捕获到实际语音和音乐；停止后的 250 ms 退出判据保持原值。表内混音帧是每声道的采样帧数，单次观察时长受音频设备、渲染与系统调度影响。WASAPI 实跑使用双声道，设备周期为 480 帧 / 10 ms。人工语音可辨度为 NOT_RUN。

可复跑脚本为 `game/tests/p2/field_audio_handoff/backend_probe.gd` 和 `retirement.gd`。本报告中的组合根观测基于原 QA 脚本加弱引用探针，正式 BOOT 退出入口的独立验收另行记录。
