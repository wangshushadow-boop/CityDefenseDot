# P1-TEST-HARNESS-001 · 可执行测试与证据

`game/tests/p1/harness/suite.py` 接受 Godot、工程目录、测试选择、种子、构建标记和 JSON 证据路径；各套件使用独立进程、用户目录和超时。除进程退出码外，还核对明确的断言输出和引擎错误。

Python 3.12.14、Godot 4.7.2，`suite.py --godot <console> --self-test` 返回 0：真实成功样例为 PASS/0，实际断言失败为 FAIL/1，静默退出 0 被识别为 FAIL，缺少入口为 NOT_RUN。另以 `--suite core --suite definitions --suite harness --seed 820` 运行三个实际套件，全部退出 0；固定种子抽样与恢复复现 64 次取值。完整 T-TEST-01–04 所需的全场景、多年仿真和容量用例按原前置继续追踪。
