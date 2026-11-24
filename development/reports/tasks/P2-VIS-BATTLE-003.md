# P2-VIS-BATTLE-003 项目渲染与音频选项

从 549f157 恢复 ADR-011 固定的方向光阴影 2048，并开启战场音频已有的系统 TTS 入口。QA 在原项目实测默认阴影为 4096。测试查询真实 ProjectSettings。首版检查脚本因布尔变量类型推断失败退出 1，显式声明类型后，同一引擎读得 shadow=2048、renderer=forward_plus、tts=true，原 P2 音频回归也退出 0。头戴设备、人工听感及屏幕朗读质量未实测。

运行 `Godot --headless --path game --script res://tests/p2/field_profile/run.gd`。外部 API、存档与资源包内容均无格式变化。
