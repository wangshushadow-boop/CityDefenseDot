# P2-FIELD-INTEGRATION-011 野战四职能配装

基线 7fc48bc。正式内容编译器从兵种解析既有 EquipmentSet、Item 和资源，区分长枪步兵、弩手、骑士与短弓骑射手。短弓是本项目的临时美术资源，随包提供；原有人物与马匹保留包内署名。

Godot 4.7.2 Standard 的 --headless --import 退出 0。随后用 --headless --path game --script 分别运行 res://tests/p2/field_loadouts/run.gd 和 res://tests/p2/field_assets/run.gd，均退出 0。编译后的内容集摘要为 e8ca20856c8d23b53d89e4aa8694b2057b73c8300c5ae23c31d9a952a039452d。整场战斗姿态、正式 PCK 与 8 GiB 整机门禁由对应任务验证。
