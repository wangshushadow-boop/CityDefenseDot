# P3 人物独立终审

结论为 PASS。审查覆盖 GDD CHR-01 至 CHR-03 及本批 T-CHR-01 至 T-CHR-04。冻结后的实际合入提交为 `53cde6d32a5d0a8f40177e64b5773ce39dfe210e`。审查者从该提交用 `git archive --format=zip 53cde6d game` 提取冷副本，在 Godot 4.7.2 Standard 重新导入、运行八个独立 headless 进程和一个 Windows 图形桌面进程。共 404 项断言，失败 0，各进程退出码 0。业务文件未由审查者修改。

[审查证据压缩包](review-evidence.zip)收录了下文引用的脚本、日志及两轮结果。

## 首轮问题及修订验证

| 首轮复现 | 最终结果 |
|---|---|
| 通用库存交换、普通日结计划、玩家休养日结计划三条路径能移动人物专属库存，写入后不能冷恢复 | 对三条入口提交相同非法流转，均拒绝，拒绝后分别冷恢复成功。装备及库存用例另行覆盖合法装备交换、唯一实例流转、传承和失败回滚。 |
| 有人物装备却丢失人物仓库的快照通过旧档降级；未来时间游标可能留下无法推进的恢复状态 | 前者稳定返回 `character.missing_repository`，后者返回 `characters.day`；CAMP 人物套件亦覆盖合法旧世界兼容与正常冷恢复。 |
| 医术个人天赋面板 +2 未进入治疗，骑术个人天赋面板 +2 未进入已乘马的骑矛检查 | 同为基础医术 6 级，一日后普通伤值 64、带天赋伤值 63；基础骑术 6 级、有效骑术 8 级，装备所需 8 级的骑矛成功。 |
| 普通过日和主动休养产生相同恢复 | 两条从 70 伤出发的轨迹各走一日，普通日结余 65、主动休养余 60。 |
| 同一人物在互不相交的两个兵员位置被重复接受 | 最终来源核验拒绝重复人物的部署；保留普通兵来源和合法人物来源的正向检查。 |

第一轮为 CHANGES_REQUIRED，初始数据与具体复现见 `initial.md`。中间版重复部署检查仍失败，见 `reservations.log`。首次探索的医术经验未跨门槛，结论采用按经验软限重作的 `effects-recount.log`。最终复验见 `final/provenance.log` 及 `final/effects.log`。

## 最终集成验证

| 实测入口 | 通过/断言数 |
|---|---:|
| 审查探针，来源、资产、日结和冷恢复 | 8/8 |
| 审查探针，有效医术、骑术和休养 | 3/3 |
| 人物领域 | 125/125 |
| 人物装备 | 40/40 |
| 库存实例 | 19/19 |
| 人物及家户流程 | 68/68 |
| Campaign 权威运行时 | 30/30 |
| Application 会话 | 28/28 |
| Windows 桌面人物界面，经 BOOT 组合入口 | 83/83 |

冻结相比首轮更新了人物技能消费、装备门槛、人物保留库存、家户传承、人物来源约束和 Campaign 兼容恢复，完成了 APP、BOOT 与桌面界面的集成。终审检查了玩家命令与权威伤亡/经验入口、读模型与存档恢复、锻造实例转移及继承者缺位的处理。合并前组合与 Git 冷包的 11 份关键实现和规则数据 LF 规范化 SHA-256 一致。完整脚本入口、独立进程退出码和文件清单见 `final/results.json`，合并前对照见 `premerge/results.json`。

归档冷导入使用 `--headless --editor --import`。八套无窗口测试的重跑入口为 `python out/p3/review/revalidate.py out/p3/review/53cde6d final`。图形测试在 NVIDIA GeForce RTX 3090、Vulkan 1.4.325 Forward+ 上执行 `--path out/p3/review/53cde6d/game --script res://tests/p3/character_desktop/run.gd`。导入日志 `53cde6d-import.log` · 图形日志 `final/desktop.log` · 图形进程退出码 `final/desktop-exit.txt`

本审查没有执行真实手柄、人工试玩、P2 大规模战斗性能或跨后续阶段的完整家族/战役长线验收。人物功能以本批阶段范围为通过边界。
