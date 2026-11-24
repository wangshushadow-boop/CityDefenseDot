# P2-AUD-BATTLE-001 野战音频与可访问反馈

开发者 p2combat 在 `.worktrees/p2-audio` 的分离工作树上交付 CANDIDATE，基线为 `d5725c7b695ae5a1765af9590cb9c513b99884e5`。需求为 AUD-01、ACC-01、BAT-05。变更限于音频模块、专属用例和本报告。公共契约沿用 EventEnvelope v1。 [AUD SDD](../../../docs/systems/game/presentation/audio/README.md)

[客户端节点](../../../game/presentation/audio/ports/field_audio.gd)通过 open_scope 创建 Voice、Effects、Music、Ambience、UI 和作用域主总线。分类与总音量、静音、字幕开关写入本地 ConfigFile。不同实例拥有独立音源及总线。play_event 接收已提交的 EventEnvelope，检查作用域、预测标记、稳定事件 ID 和重放窗口，然后按优先级、距离与已知遮挡路由。近场命中、坐骑冲撞、落马、盾破、溃退等效果使用实际空间播放器。命令和警告保留非空间播放位并压低背景音量。预留的双音乐播放器可在地图、战斗、胜、败和静音间淡化切换。

字幕使用独立的本地化键。22 类编队命令、警告和战场反馈拥有中文与英文文本。HUD 可接收 subtitle_requested 及独立的 important_notice 信号。客户端支持 Godot 本机 TTS 时按语言选择本地音色，音量服从主控与语音设置，占用一个并发名额。无 TTS 时，原创提示音型与字幕继续工作。客户端组合根需启用项目设置 `audio/general/text_to_speech`，专服无需实例化此节点。

### 声源与授权

随包效果、命令提示音与四段音乐均由项目内[声源脚本](../../../game/presentation/audio/field_cues.gd)生成，旋律及[双语短句](../../../game/presentation/audio/captions.tres)为本任务新写。开发期间以 Windows.Media.SpeechSynthesis 的 Microsoft Kangkang 音色临时朗读 24 条文本，随后从候选中移除了全部语音录音。微软文档介绍了安装音色的本机合成接口。此候选使用游戏设备自身的播放接口，提交内容中没有微软音色或录音，也没有外部下载素材。[Microsoft SpeechSynthesizer](https://learn.microsoft.com/en-us/uwp/api/windows.media.speechsynthesis.speechsynthesizer)

### 开发者实测

Windows，Godot 4.7.2 Standard ed1daf0bf，Dummy 混音驱动，种子 42。用例在临时目录设置 APPDATA、LOCALAPPDATA 和 Godot 日志，然后执行 `Godot_v4.7.2-stable_win64_console.exe --headless --path game --script res://tests/p2/audio/run.gd`。退出码 0，输出 `P2-AUD-BATTLE-001 PASS errors=0`。[测试入口](../../../game/tests/p2/audio/run.gd)

| 用例 | Given / When | Then 与实测 |
|---|---|---|
| T-AUD-01 | 正常 Mission 固定步分配 500 名真实 COM 角色；250 名发起近战攻击，物理扫掠命中 250 个目标碰撞体。将确认命中与实际 FORM 生效的坚守命令送入本地播放器 | 预算 12，峰值 10，185 个低优先级请求被舍弃。Voice 总线采集到 16,384 帧，命令提示音 PCM 峰值 0.485。语音期间 Effects 实际衰减，受遮挡空间源另衰减 10 dB。重复、预测、过期或其他作用域消息不重播。自动部分 PASS。真实扬声器、系统语音与主观辨识率 NOT_RUN |
| T-AUD-02 | 打开字幕并将主控、语音、音效设零，完成同一 Mission，触发胜利，再以新作用域读取设置 | 撤退及胜利字幕可见，静音期间切换至胜利曲，再完全淡出；关闭字幕时重要消息仍送达 HUD。配置恢复、非法值拒绝均通过。PASS |
| T-AUD-03 | 正常结束并 dispose Mission，停止音频作用域，重新打开，另测信息回调中关闭和直接析构播放中的节点 | 所有池节点、音乐节点及字幕层释放，总线恢复原数量，旧事件拒绝。PASS |

受影响回归以相同 Godot 命令运行 `res://tests/p2/combat/run.gd`、`res://tests/p2/formation/run.gd`、`res://tests/p1/mission/run.gd` 和 `res://tests/p1/bootstrap/run.gd`，均退出 0。编队和战斗原有 500/1000 微基准通过，专服引导 T-BOOT-02 保持无音频节点。静态依赖检查 `python ci/gates.py dependencies` 输出 `dependencies PASS issues=0`。

早期版本测试曾因脚本类型推断、三参数 maxf、并发断言和默认沙盒用户目录不可写失败。修正后采用项目既有隔离 APPDATA 测法。预算按同时活跃音源及路由总量断言，保留抢占已播放低优先级声音的行为。捕获 PCM 证明了引擎实际混音。真实设备的 TTS/扬声器、硬件听感验收和整场视听性能仍待集成。开发者未更新任务状态或创建提交。

主 Agent 据独立审查修复了胜败曲在 Music 与 UI 总线重复播放的问题。仅关闭 Music、保持 UI 与主音量开启时，胜败字幕仍可见，结算音乐由唯一的音乐轨处理。已重跑 500 人音频测试和 P1 Mission，均退出 0。
