# P2-VIS-BATTLE-004 野战资源冷交付

基线 `152e1f4`。模块 CI。验收范围为 T-CI-03 与 T-VIS-01 的野战素材交付部分。

旧的 server.pck 用 `--profile=tool --content-path=res://infrastructure/content/base --content-path=res://content/base/field` 启动时退出 1，报告缺失 CREDITS.md。另用 FileAccess 检查四份 GLB 原件也均不存在。源码同参数退出 0。

候选 `c09b99b` 在临时导出工程使用 Godot 的 EditorExportPlugin，从 field/manifest.json 提取原始 GLB 与许可文档。PCK 同时保留导入后的 PackedScene。base.zip 含原 base/ 及清单列出的 field/ 文件。构建工具删除源码副本后，用真实内容编译器分别启动两份 PCK 和解包出来的原始内容，检查与源码相同的摘要，并在客户端和服务端的 PCK 内实际实例化每个模型并检查网格。

运行 `python ci/build.py --godot D:/Program/Godot/Standard/Godot_v4.7.2-stable_win64_console.exe --out out/p2-field-build`。Windows、Godot 4.7.2 Standard，退出 0。两项 CI 自测、依赖门禁、十五套 P1 回归、旧 base 冷启动，以及两份 PCK 各四个模型的实例化均通过。源码、client.pck、server.pck、base.zip 的野战内容 SHA-256 均为 `aec256b449a3ebadc8d8b24ba75ff773a72523f70898f112a4d06faea6cc13a1`。开发清单记录各个制品的 SHA-256。完整野战入口、独立 EXE 和 8 GiB 设备测试未执行。
