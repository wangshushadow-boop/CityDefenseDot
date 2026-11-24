# P1-TEST-HARNESS-002 · 隔离模块 PCK 配置

预设生产 main_scene 后，内容测试的缩小工程在导入阶段报 Cannot open file res://bootstrap/main.tscn，返回 1。该测试只打包 CON/DEF/CONTENT，自此使用自己的 Godot fixture 配置。持久层 PCK 也打入本次测试打包器的独立配置。两个入口仍对真实业务脚本打包，并在无源码目录验证；产品级整包由 CI 检验。

验证环境为 Godot 4.7.2 Standard/Windows，Python 3.12.14。运行 content/pck.py 和 persistence/pack_smoke.py，以下以实际测试及集成记录为准。

两份最终 PCK 均实跑通过，退出 0。内容基础摘要 fe76080c…a579，PERSIST_PCK_STANDALONE PASS。
