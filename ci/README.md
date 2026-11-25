# ci/

项目：`recollection`。模块：`CI`。

在 Windows 上用 Python 3.12 和已锁版本的 Godot Standard 控制台从仓库根运行。

```powershell
python ci/build.py --godot D:/Program/Godot/Standard/Godot_v4.7.2-stable_win64_console.exe --out out/field-build
python ci/gates.py dependencies
python ci/gates.py release
python game/tests/p1/ci/test_gates.py
```

构建只使用当前 Git 提交的源码。成功后输出新的完整开发构建目录，含 `client.pck`、`server.pck`、`base.zip`、领域测试记录和 `manifest.json`。客户端可用 `godot --main-pack client.pck -- --p1-smoke`，专服使用 `godot --headless --main-pack server.pck -- --p1-smoke`。构建命令会短暂启动实际客户端窗口。

base.zip 内含基础包 base/ 及带署名的野战包 field/。构建清单的 field 项记录源码、两个 PCK 和原始 ZIP 实际加载后的野战摘要，以及在两个 PCK 内均已实例化的模型。field.matches 分别记录从冷客户端包实际点击部署、发布命令与撤退后的 20 槽战果，以及从冷专服包得到的 20 人入场和 40 槽结算。正常游玩用 `godot --main-pack client.pck`，从主菜单选择“进入河原野战”。

release 检查本体 MUST 与 AT-01 至 AT-16 的证据，返回非零时阻断发布验证。证据文件可包含独立行 `T-… PASS` 或结构化记录 `{"id":"T-…","status":"PASS"}`，同样规则适用于需求 ID 和完整 AT。AT 矩阵的 PASS 状态须附指向对应证据的相对 Markdown 链接。此命令只核验证据。正式发布还须通过 P7 的负责人试玩与批准。[模块规格](../docs/systems/ci/README.md)
