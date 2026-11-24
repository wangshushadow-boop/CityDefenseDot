# P2-VIS-BATTLE-002 · 河原野战场景与临时美术

主 Agent 开发，隔离工作树 p2-field_assets，基线 `6e399f2`。BASE 工作仅写 `game/content/base/field/`、专属测试和本报告。临时资源在包内随附作者、出处、许可、改动和 SHA-256，独立于正式原创量。野战规则 field:ruleset/field_battle、场景 field:scene/river_plain 和步兵、弩手、骑兵定义使用原有内容编译器、v1 注册表与基础文化。名册与战役经济由相应领域负责。

在 Windows 及 Godot 4.7.2 Standard 中执行 `python game/tests/p2/field_assets/cold_import.py --godot <Godot控制台路径>`。在新的临时工程和用户目录完成真实编辑器导入，再执行 Godot 游戏入口，进程分别退出 0。将包次序颠倒重编后内容摘要均为 `aec256b449a3ebadc8d8b24ba75ff773a72523f70898f112a4d06faea6cc13a1`。取样相隔 0.22 秒，三具 22 骨角色各有 20、19、19 根骨骼位姿发生改变，50 骨坐骑有 32 根。三个人物分别有 12 个蒙皮网格，马匹有 1 个。正式场景的西东集结点在同一物理导航世界可达。

资源测试覆盖 T-VIS-01 的绑定前提。整套真实战斗的挂点、命中时间、500/1,000 人的显存和帧率仍待 VIS、FIELD-INTEGRATION 实测。[包内署名](../../../game/content/base/field/CREDITS.md)

跨签出复测首次发现 Windows 自动将 river_plain.tscn 变为 CRLF，使首次开发与新签出的 ContentHash 分别为 aec256b4… 和 3e4ead4b…，尽管可见内容一致。已给资源包内 TSCN 固定 LF，并对作为内容哈希输入的场景字节加入冷导入回归；GLB 保持原始字节。
