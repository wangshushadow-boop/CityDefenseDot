# game/presentation/audio/

项目：`recollection`。模块：`AUD`。

[野战音频端口](ports/field_audio.gd)负责已确认事件的声音、音乐和字幕。[模块用例](../../tests/p2/audio/run.gd)演示 Mission 接线与作用域释放。[模块规格](../../../docs/systems/game/presentation/audio/README.md)

无设备朗读时，Voice 声道播放项目中英文字幕对应的 48 句离线语音。两套临时语音由 eSpeak NG 1.52.0 的普通话 cmn 与美式英语 en-us 共振峰音色合成。制作工具使用 GPL-3.0-or-later；游戏包只携带项目台词生成的 PCM。制作命令及固定摘要见[任务记录](../../../development/reports/tasks/P2-VIS-BATTLE-005.md)。[eSpeak NG](https://github.com/espeak-ng/espeak-ng) · [制作工具的 Windows 发行包](https://pypi.org/project/espeakng-loader/0.2.4/)
