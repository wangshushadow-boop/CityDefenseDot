# P2-VIS-BATTLE-006 Windows 首次启动

在同一 Windows 主机上交替启动三个源码版本的 15 个已导出开发客户端。P1 五次均成功，旧 P2 的五次中失败两次，带完整野战资源原件的 P2 也失败两次。失败进程在显示 RTX 3090 / Vulkan 之后退出，未到达 BOOT 记录，出现 0xc0000374、0xc0000005。

用同一份 152e1f4 源码及引擎做八轮独立用户目录对照。设备朗读保持原设置为 6/8，原设置加八工作线程为 5/8，仅关闭设备朗读为 8/8。主集成人在 fe301c6 记录 Windows 专属配置。头部阴影 2048 和 Forward+ 在 Godot 查询中实测通过，Windows 的有效原生朗读设置为 false。Windows 改用随包的语音，见 P2-VIS-BATTLE-005。

运行 `python game/tests/p2/field_profile/cold_start.py --godot <Godot-console.exe> --project game --trials 12 --evidence <证据路径>`。首次解析时修正了 valid 的 bool 类型声明。最终 Windows 源码客户端使用各自的全新用户目录，12/12 成功。每个进程创建真实窗口并经 BOOT 进入训练，推进三步并正常退出。脚本同样支持 `--pack client.pck`。Linux、macOS 和人工听辨未测。野战 AT-04、AT-05 需由整场入口验收。
