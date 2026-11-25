# 端到端验收矩阵（原规格书 §22.2）

以下 17 个场景保留原规格书要求；实际验收按已冻结的技术栈和阶段门禁执行。各模块用例 ID 见 `test_cases.csv`，需求索引见 `requirements_trace.csv`。表内状态对应完整场景。

| AT ID | 操作 | 成功标准 | 关联需求 | 状态 |
|---|---|---|---|---|
| AT-01 | 新建原创角色，招募、交易、旅行、接任务、野战、结算 | 状态闭环，经验/名望/货物/资金一次更新 | MOD-01/02, WLD, CHR, ARM, ECO, BAT, QST | NOT_RUN |
| AT-02 | 创建两支家族队伍，组成军团，集结后围城 | 粮耗/凝聚力、器械、驻军、援军与撤围正常 | ARM, POL, SAI, SGE | NOT_RUN |
| AT-03 | 城镇被围堵后开放商路 | 供应减少→价格/饥荒变化→恢复，库存及账本一致 | ECO, SET, WLD | NOT_RUN |
| AT-04 | 500 人混合野战，玩家切换阵型、目标与委派 | 命令响应、兵种行为、路径、士气、胜负与预算达标 | BAT, COM, BAI, NAV | FAIL [整场实测](../../development/reports/tests/P2/field-benchmark-final/summary.json) |
| AT-05 | 千人军队分波次参战，部分未生成，玩家撤退 | 每个来源槽位有唯一结果，伤亡/俘虏正确 | BAT-02/03, ARM-05 | NOT_RUN |
| AT-06 | 城门、城墙缺口、攻城塔多路径攻防 | AI 可操作器械和通行，胜负回写领地与损坏 | SGE, NAV, SET | NOT_RUN |
| AT-07 | 城镇访问、锦标赛、盗匪藏身处、监狱任务 | 各模式共享角色/战斗，奖励/临时装备不串域 | MIS, QST, COM | NOT_RUN |
| AT-08 | 加入王国、投票、封地易主、退国建国、议和 | 权限、影响力、外交、军团和封地一致 | POL, CLN, SET | NOT_RUN |
| AT-09 | 角色死亡/退休，继承人接续游戏 | 人物唯一、资产合法、任务处理、可继续存档 | CHR, CLN, SAV | NOT_RUN |
| AT-10 | 保存战前；在结算写入前/中/后模拟崩溃 | 不重复结算、不丢已提交状态、恢复合法 | BAT-03, SAV-02 | NOT_RUN |
| AT-11 | 自定义攻城/野战、多模式多人、队长指挥 | 单人与多人规则复用，战役状态不被写入 | MOD-03/04, NET | NOT_RUN |
| AT-12 | 150 ms RTT、30 ms 抖动、3% 丢包模拟（起始测试档） | 权威收敛、无重复伤害；重连与超时可解释 | NET-03/04/05, COM-06 | NOT_RUN |
| AT-13 | 添加全新文化、兵种、装备、任务、场景、AI 行为 MOD | 不改核心即可载入；依赖/冲突与版本校验正确 | EXT, MOD-05 | NOT_RUN |
| AT-14 | 多种种子连续模拟十年，无玩家干预 | 无负库存/非法身份/孤儿引用；势力变化、经济有恢复性 | WLD, ECO, CLN, POL, SAI | NOT_RUN |
| AT-15 | 50 次任务切换、8 小时连续压力、存档迁移 | 无崩溃、无资源泄漏、预算满足且存档可载入 | BAT, SAV, NET, VIS | NOT_RUN |
| AT-16 | 手柄、重映射、多个分辨率/语言、字幕和难度选项 | 可完成所有主流程，显示和操作无阻断 | UX, ACC, AUD | NOT_RUN |
| AT-17 | 海上运输—战斗—占领—舰队/战役回写（扩展） | 船舶、船员、港口与货物一致，旧本体存档有迁移策略 | NAVAL（EXT） | NOT_RUN |

文档镜像版：需求追踪表的 `document_paths` 及模块用例表的 `document_path` 指向 `docs/systems/` 内唯一权威 SDD；`code_paths` 列出计划实现目录。测试状态和原有判据不变。

## P1 切片证据

AT-10 的四个结算写入断点覆盖进程终止、冷启动和重发，账户及回执恰好提交一次。AT-15 已覆盖同一世界 50 次 Mission 切换、写盘与重载，完整八小时压力尚未执行。完整场景状态见上表。[运行记录](../../development/reports/tests/P1/session/README.md)

## P2 实战验收

AT-04 的编队指挥、伤亡和逐人战果有实测，整场性能未达，完整场景为 FAIL。AT-05 已执行千人兵源、分波、未入场、撤退和逐槽战果，战役名册及俘虏持久回写留待后续阶段。

[行军与突击的逐槽对照](../../development/reports/tests/P2/field-final-acceptance/results.json) · [阶段报告](../../development/reports/stages/P2.md)


## P3 人物切片

AT-01 的人物创建及 AT-09 的退休、继承人控制权、装备归属和冷载续玩已有成品证据。完整的跨队伍、封地、任务与战役流程沿用表中原状态。[人物工作包验收](../../development/reports/stages/P3-character.md)

P4-GOV 已通过独立专项 T-GOV-01、T-GOV-02，覆盖总督资格与领地日结。AT-02、AT-03 等完整场景保留原验收状态。[总督专项报告](../../development/reports/stages/P4-governor.md)

P5-VISIT 的 NPC 名册、时限庄簿委托、交差与单次领奖通过 T-VISIT-01/02；AT-01、AT-07、AT-09 等仍按完整场景验收。[庄署人物验收](../../development/reports/stages/P5-estate-visit.md)
