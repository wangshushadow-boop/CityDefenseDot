# P2-FIELD-INTEGRATION-005 野战交付

两份开发 PCK 在干净目录中分别运行真实野战。客户端通过主菜单与实际 HUD 完成选队、部署、坚守、撤退和返回。专服完成 20 人实战与 40 槽权威结算。测试探针从同一 Git 提交复制到临时目录，PCK 仍只包含生产文件。原有三步训练、P1 套件、资源导出、内容摘要和四个模型的冷启动检查继续运行。

只有 bootstrap/composition_root.gd 可以新增构造 field_mission 和 field_brains 的依赖。运行 game/tests/p2/field_ci/test_scope.py 验证其他 UI、APP 以及无关私有类的规则，退出 0。构建命令与冷启动实际结果见集成报告中的候选和合并提交证据。
