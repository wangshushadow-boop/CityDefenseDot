# P2-VIS-BATTLE-005 野战命令离线语音

开发候选，基线 `81aa05b201bc909f78f756d684ef90d1223e958d`。AUD 模块，ACC-01、AUD-01，T-AUD-01、T-AUD-02。工作目录为隔离的 p2-voice_assets。候选由主 Agent 固定和集成。

现有 23 条命令和 1 条警告逐句使用项目字幕原文制作。每个语言包包含 24 个单声道 22,050 Hz、16-bit PCM AudioStreamWAV。系统朗读可用并与当前语言相符时，沿用设备语音及提示音。缺少适用系统语音时，实际口令走既有 Voice 声道。高优先级命令可替换正在播放的口令，静音或退出会停止播放。字幕、去重、串场保护和混音设置继续通过已有入口。授权范围内更新了音频端口、声音库、两组资源、换行约定、模块入口以及两份专属测试工具。

## 素材与可复建性

开发机的 eSpeak NG 1.52.0 使用 cmn 与 en-us 普通共振峰音色，以种子 241124 离线制作，无项目外配音录音。Windows x64 制作 wheel 为 `espeakng_loader-0.2.4-py3-none-win_amd64.whl`，SHA-256 `41f1e08ac9deda2efd1ea9de0b81dab9f5ae3c4b24284f76533d0a7b1dd7abd7`。游戏发布物只使用生成的声音。资源由[项目合成器](../../../game/tests/p2/audio/generate_voices.py)按 [eSpeak NG](https://github.com/espeak-ng/espeak-ng) 的[上游 C 接口](https://github.com/espeak-ng/espeak-ng/blob/master/src/include/espeak-ng/speak_lib.h)生成。[工具发行页](https://pypi.org/project/espeakng-loader/0.2.4/)

```powershell
python -m pip download --no-deps --only-binary=:all: --dest out/voice-tool espeakng-loader==0.2.4
python -m zipfile -e out/voice-tool/espeakng_loader-0.2.4-py3-none-win_amd64.whl out/voice-tool/extracted
python game/tests/p2/audio/generate_voices.py out/voice-tool/extracted/espeakng_loader/espeak-ng.dll
```

两个独立生成进程的文件摘要逐字节相同。

| 资源 | 字节 | SHA-256 |
|---|---:|---|
| orders_zh.tres | 1323984 | `6376aa3e86238187173fe1c3b00c5f921e9e68df31eddceb482e0ad59613872b` |
| orders_en.tres | 1186696 | `b2f3f6995d2d827bc4f90e0ffee67ae795006c2580c6c9b434bf03103aa1b69a` |

## 实测

Windows x64，Godot 4.7.2 Standard。原始用例与新增用例均从正常 play_event 入口进入，并检查实际音频混音结果。

| 执行 | 退出码 | 结果 |
|---|---:|---|
| `Godot --headless --path game --script res://tests/p2/audio/run.gd` | 0 | T-AUD-01 自动部分通过。500 名角色产生 250 次实际命中，12 音源预算内峰值 10，弃播 185，Voice 捕获 16,384 帧，PCM 峰值 0.437。T-AUD-02、T-AUD-03 通过。 |
| `Godot --headless --path game --script res://tests/p2/audio/recorded_voices.gd` | 0 | 48 个独立、非空的真实语音样本，经运行中的语言切换选择。在四音源预算场景中讲话峰值为 1。中英文各捕获 7,680 帧，静音即时停止发声，退出释放全部播放节点。 |
| 临时工程 `--editor --headless --import`、`--headless --export-pack Audio cold.pck`、删除源码目录后从空目录 `--headless --main-pack cold.pck --script <recorded_voices.gd>` | 0 / 0 / 0 | 两种语言 48 段由导出 PCK 的正常音频入口播放。各采集 7,680 帧，峰值 0.505 和 0.715。引擎无错误。 |

首次新增测试把低优先级警告误当作可覆盖正在展示的指令字幕，两条断言失败。保留原来的 2 秒高优先级字幕保护，并在其自然消失后验证警告。最终源码与冷 PCK 的相同用例均退出 0。

人耳听辨、扬声器音量和非 Windows 原生设备语音本次未测。整场混战与最终 Windows 发布包的正式复核由主线程组织。
