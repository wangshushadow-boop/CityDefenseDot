# recollection 完整阶段计划（P0–P8）

继承 [总体设计 §23](../../docs/game_design.md) 和 [原依赖策略](../../docs/architecture/dependency_policy.md)。这是开发实施顺序，不是产品范围削减。阶段由用户逐一授权，主 Agent 选择前置满足的工作包，细化并分配 Subagent。实际任务必须定义边界和可执行判据，不能直接把工作包当作一条完成整个模块的提示词。

## 阶段目标和门禁

| 阶段 | 目标 | 关键验收 | 跨阶段测试边界 |
|---|---|---|---|
| P0 架构与技术验证 | 验证引擎、主语言、真实负载、网络、内容工具及关键契约；批准技术/契约 ADR。 | 真实 500/1000 混合场景报告、动画/动态导航/专服实验、环境锁定和负责人批准。 | 无；本阶段是技术验证，不执行正式游戏 AT。 |
| P1 公共运行时与工程基础 | 公共类型、Session、时钟随机、定义编译、仓库/事务、存档、Mission 端口、测试和 CI 起步。 | 可启动/可 headless（按选定环境）、纯领域测试、内容验证、原子存档与初始迁移；冻结战场、联网、MOD 端口。 | AT-10 存档与事务基础切片；完整遭遇故障在 P3 及 P7 复验。 |
| P2 实时战争 | 方向动作、近远战、骑乘、导航、阵型、分层战场 AI、部署增援、野战及结果。 | 真实混合野战、编队/命令/士气/结果、500/1000 人性能验证；COM/BAT/BAI/NAV 本阶段能力。 | AT-04 完整；AT-05 战场来源槽切片；COM-06 与多人完整验收留 P6。 |
| P3 战略世界与角色 | 地图、角色/家族、兵力名册、后勤、遭遇、自动结算、持久化和基本 UI。 | 角色创建/招兵/地图接战/结算及保存恢复闭环，身份与资源一致。 | AT-05/09/10 的已具备功能；AT-01 贸易/任务部分待 P4/P5；AT-09 涉及领地/政治/任务部分同样延期。 |
| P4 社会仿真与攻城 | 经济、工坊/锻造、领地治理、政治外交、四类战略 AI、战略围城与实时攻城。 | 经济/政治长期仿真，围城粮耗、器械/动态链接、占领回写；无非法资产或身份。 | AT-02/03/06/08/14 按完整已具备范围；需后续内容/任务部分在 P5/P7 复验。 |
| P5 完整单人内容 | 主线/动态任务、对话、访问、竞技、藏身处、潜入、自定义、主流程 UX 与内容。 | MOD-01/02/03、全部单人主要玩法与可访问性；原创内容制作标准已实施。 | AT-01/07/09/16 完整；其他单人 AT 回归；AT-11 的自定义战斗切片，多人部分待 P6。 |
| P6 多人联机与扩展工具 | 专用权威服务器、全部多人模式、大厅/匹配、网络故障/安全、MOD SDK 与编辑器。 | NET/EXT、模式隔离、版本/身份/重连、联机与内容工具真实验收。 | AT-11/12/13；AT-15 服务器相关切片。 |
| P7 内容扩量、优化与发布 | 全量原创地图、兵种、资产、任务、本地化、平衡、性能、QA、安装与升级。 | 全部 MUST 需求/本体测试、AT-01–16、长时间仿真和回归、授权与人工试玩/发布批准。 | 全部 AT-01–16 以最终内容、构建和环境重新验收。 |
| P8 海战独立扩展 | 海域/港口/舰队、舰船运动与接舷、船员 AI、内容/工具与结算。 | NAVAL/EXT 范围完成，AT-17、本体回归与兼容迁移；独立发布批准。 | AT-17 与本体相关回归。 |

跨阶段 AT 由多个模块支撑，早期可验证切片但原完整 AT 保持 NOT_RUN，最终 P7 重新执行全部本体需求与 17 个场景中的 AT-01–16。P8 只验收扩展及本体回归，不拖延本体发布。P0/P1 验证和冻结网络/存档/MOD 端口，P6 才完整交付在线能力；内容生产从骨架和导入标准批准后并行。

## 工作包与依赖

[task_graph.json](task_graph.json) 为机器可读的初始 DAG，包含 9 个阶段门禁；工作包内相关需求和测试是索引，不是提前通过承诺。主 Agent 必须细化执行任务、逐项核对真实依赖和验收。工作包共享多个模块时拆成不重叠的单模块任务；集成用例由授权角色串行处理。不得把运行时协作关系直接当作代码依赖。

### P0 · 架构与技术验证

- `P0-ENV`：检查工具、硬件、权限与项目基线；前置：无
- `P0-CRITERIA`：设计真实负载实验与判据；前置：P0-ENV
- `P0-BATTLE`：动作、蒙皮与混合战场容量试验；前置：P0-CRITERIA
- `P0-NAV`：动态导航与人群瓶颈实验；前置：P0-CRITERIA
- `P0-NET`：专用服务器与联网可行性实验；前置：P0-CRITERIA
- `P0-CONTENT`：资产、编辑器与工具链可行性；前置：P0-CRITERIA
- `P0-CONTRACTS`：公共契约与版本化方案提案；前置：P0-ENV
- `P0-DECISIONS`：技术栈、基准和契约冻结；前置：P0-BATTLE, P0-NAV, P0-NET, P0-CONTENT, P0-CONTRACTS

### P1 · 公共运行时与工程基础

- `P1-CON`：公共契约与版本管理；前置：GATE-P0
- `P1-CORE`：核心运行时原语与调度；前置：GATE-P0, P1-CON
- `P1-DEF`：定义数据与引用注册；前置：GATE-P0, P1-CON
- `P1-TEST-HARNESS`：领域、集成、场景与长期测试（HARNESS）；前置：GATE-P0, P1-CORE, P1-DEF
- `P1-SHRULE`：公共规则、数值与效果计算；前置：GATE-P0, P1-CORE, P1-DEF
- `P1-INV`：库存、账户、账本与资源事务；前置：GATE-P0, P1-CORE, P1-DEF
- `P1-INF-CONTENT-CORE`：数据包编译、MOD 注册与配置合并（CORE）；前置：GATE-P0, P1-DEF, P1-CORE
- `P1-PERSIST-CORE`：存档、原子提交、迁移与恢复（CORE）；前置：GATE-P0, P1-CON, P1-CORE, P1-DEF
- `P1-INF-ENGINE-PORTS`：引擎适配、物理、导航与资源端口（PORTS）；前置：GATE-P0, P1-CORE, P1-CON
- `P1-TELEM`：日志、指标、诊断与崩溃报告；前置：GATE-P0, P1-CORE
- `P1-CAMP-RUNTIME`：战略世界运行时（RUNTIME）；前置：GATE-P0, P1-CORE, P1-INV, P1-DEF
- `P1-MIS-RT-PORTS`：Mission 运行时、实体与增援（PORTS）；前置：GATE-P0, P1-CORE, P1-DEF, P1-INF-ENGINE-PORTS
- `P1-APP-CORE`：应用层、GameSession 与事务（CORE）；前置：GATE-P0, P1-CAMP-RUNTIME, P1-MIS-RT-PORTS, P1-PERSIST-CORE, P1-INV
- `P1-BOOT`：启动、装配与配置；前置：GATE-P0, P1-APP-CORE, P1-INF-CONTENT-CORE, P1-INF-ENGINE-PORTS, P1-TELEM
- `P1-CI-CORE`：持续集成、架构门禁与发布构建（CORE）；前置：GATE-P0, P1-BOOT, P1-TEST-HARNESS

### P2 · 实时战争

- `P2-MIS-RT-BATTLE`：Mission 运行时、实体与增援（BATTLE）；前置：GATE-P1
- `P2-COM`：动作、装备、命中、伤害与士气执行；前置：GATE-P1
- `P2-MOV`：战场路径、避障、运动与动态导航；前置：GATE-P1
- `P2-FORM`：编队、指挥授权、阵型与槽位执行；前置：GATE-P1
- `P2-BAI`：战场 AI 共同基础、感知与调度；前置：GATE-P1, P2-FORM, P2-MOV, P2-COM
- `P2-BAI-T`：L1 战术 AI：全军计划；前置：GATE-P1, P2-BAI
- `P2-BAI-F`：L2 编队 AI：执行战术任务；前置：GATE-P1, P2-BAI
- `P2-BAI-I`：L3 个体 AI：士兵感知、目标与动作意图；前置：GATE-P1, P2-BAI
- `P2-RULES-FIELD`：Mission 规则、目标与玩法组合（FIELD）；前置：GATE-P1, P2-MIS-RT-BATTLE, P2-FORM, P2-COM
- `P2-RESULTS`：来源追踪、战斗结果与统计；前置：GATE-P1, P2-MIS-RT-BATTLE, P2-COM, P2-RULES-FIELD
- `P2-INPUT`：输入设备、控制映射与玩家命令；前置：GATE-P1, P2-COM, P2-FORM
- `P2-CAM`：相机、视角、选取与观战；前置：GATE-P1, P2-INPUT, P2-MOV
- `P2-VIS-BATTLE`：地图与战场视觉代理、动画、LOD（BATTLE）；前置：GATE-P1, P2-COM, P2-MOV
- `P2-AUD-BATTLE`：音频、战斗语音与音乐（BATTLE）；前置：GATE-P1, P2-COM, P2-FORM
- `P2-UI-BATTLE`：界面、ReadModel 与交互流程（BATTLE）；前置：GATE-P1, P2-FORM, P2-RULES-FIELD, P2-INPUT
- `P2-FIELD-INTEGRATION`：混合战场端到端集成与性能；前置：P2-MIS-RT-BATTLE, P2-RULES-FIELD, P2-RESULTS, P2-BAI-T, P2-BAI-F, P2-BAI-I, P2-VIS-BATTLE, P2-AUD-BATTLE, P2-CAM, P2-UI-BATTLE

### P3 · 战略世界与角色

- `P3-WORLD`：世界地图、时钟、交通、情报；前置：GATE-P2
- `P3-CHR`：英雄、成长、装备与生命状态；前置：GATE-P2
- `P3-CLAN`：家族、婚育、同伴、职责与继承；前置：GATE-P2, P3-CHR
- `P3-PARTY`：队伍、军团、名册、俘虏、补给；前置：GATE-P2, P3-CHR, P3-CLAN, P3-WORLD
- `P3-ENC-ENCOUNTER`：遭遇、战略围城、预留与自动结算（ENCOUNTER）；前置：GATE-P2, P3-PARTY, P3-WORLD
- `P3-CAMP-DOMAINS`：战略世界运行时（DOMAINS）；前置：GATE-P2, P3-ENC-ENCOUNTER
- `P3-APP-CAMPAIGN`：应用层、GameSession 与事务（CAMPAIGN）；前置：GATE-P2, P3-ENC-ENCOUNTER, P3-CAMP-DOMAINS
- `P3-PERSIST-CAMPAIGN`：存档、原子提交、迁移与恢复（CAMPAIGN）；前置：GATE-P2, P3-APP-CAMPAIGN
- `P3-UI-CAMPAIGN`：界面、ReadModel 与交互流程（CAMPAIGN）；前置：GATE-P2, P3-APP-CAMPAIGN

### P4 · 社会仿真与攻城

- `P4-ECO`：经济、市场、商队、工坊与锻造；前置：GATE-P3
- `P4-SET`：城镇、城堡、村庄与领地治理；前置：GATE-P3
- `P4-POL`：王国、决议、外交、战争与身份；前置：GATE-P3, P4-SET
- `P4-ENC-SIEGE`：遭遇、战略围城、预留与自动结算（SIEGE）；前置：GATE-P3, P4-ECO, P4-SET, P4-POL
- `P4-SAI`：战略 AI 总控、调度与任务规划；前置：GATE-P3, P4-ECO, P4-SET, P4-POL
- `P4-SAI-K`：战略 AI：王国规划；前置：GATE-P3, P4-SAI
- `P4-SAI-C`：战略 AI：家族规划；前置：GATE-P3, P4-SAI
- `P4-SAI-A`：战略 AI：军团规划；前置：GATE-P3, P4-SAI, P4-ENC-SIEGE
- `P4-SAI-P`：战略 AI：队伍规划与类型策略；前置：GATE-P3, P4-SAI
- `P4-SIEGE`：实时攻城器械、城防与动态连接；前置：GATE-P3, P4-ENC-SIEGE
- `P4-RULES-SIEGE`：Mission 规则、目标与玩法组合（SIEGE）；前置：GATE-P3, P4-SIEGE
- `P4-BAI-SIEGE`：战场 AI 共同基础、感知与调度（SIEGE）；前置：GATE-P3, P4-SIEGE, P4-RULES-SIEGE
- `P4-UI-SOCIETY`：界面、ReadModel 与交互流程（SOCIETY）；前置：GATE-P3, P4-ECO, P4-SET, P4-POL
- `P4-SOCIETY-INTEGRATION`：社会系统与攻城集成；前置：P4-SAI-K, P4-SAI-C, P4-SAI-A, P4-SAI-P, P4-BAI-SIEGE, P4-UI-SOCIETY

### P5 · 完整单人内容

- `P5-QUEST`：动态任务、剧情导演、对话与事件；前置：GATE-P4
- `P5-INTERACT`：场景交互、NPC 与访问流程；前置：GATE-P4, P5-QUEST
- `P5-RULES-SINGLE`：Mission 规则、目标与玩法组合（SINGLE）；前置：GATE-P4, P5-INTERACT
- `P5-BASE-INITIAL`：本体原创内容包与资源制作（INITIAL）；前置：GATE-P4, P5-QUEST
- `P5-UI-SINGLE`：界面、ReadModel 与交互流程（SINGLE）；前置：GATE-P4, P5-RULES-SINGLE, P5-BASE-INITIAL
- `P5-SINGLE-INTEGRATION`：完整单人闭环与内容集成；前置：P5-UI-SINGLE, P5-BASE-INITIAL, P5-RULES-SINGLE

### P6 · 多人联机与扩展工具

- `P6-NET`：网络协议、传输、权威与状态复制；前置：GATE-P5
- `P6-MP`：多人会话、大厅、匹配与模式组装；前置：GATE-P5, P6-NET
- `P6-RULES-MULTI`：Mission 规则、目标与玩法组合（MULTI）；前置：GATE-P5, P6-NET, P6-MP
- `P6-SERVER-D`：专用权威战斗服务器；前置：GATE-P5, P6-NET, P6-RULES-MULTI
- `P6-SERVER-L`：大厅后端、身份、匹配与赛果；前置：GATE-P5, P6-MP
- `P6-SERVER-OPS`：部署、扩容、运维与发布；前置：GATE-P5, P6-SERVER-D, P6-SERVER-L
- `P6-INF-CONTENT-SDK`：数据包编译、MOD 注册与配置合并（SDK）；前置：GATE-P5
- `P6-ADDONS`：编辑器插件与可信扩展 SDK；前置：GATE-P5, P6-INF-CONTENT-SDK
- `P6-TOOLS`：内容 CLI、验证器与开发调试工具；前置：GATE-P5, P6-INF-CONTENT-SDK, P6-ADDONS
- `P6-UI-MULTI`：界面、ReadModel 与交互流程（MULTI）；前置：GATE-P5, P6-MP, P6-RULES-MULTI
- `P6-NET-INTEGRATION`：联机和 MOD 端到端验收；前置：P6-SERVER-OPS, P6-TOOLS, P6-UI-MULTI

### P7 · 内容扩量、优化与发布

- `P7-BASE-FULL`：本体原创内容包与资源制作（FULL）；前置：GATE-P6
- `P7-TOOLS-RELEASE`：内容 CLI、验证器与开发调试工具（RELEASE）；前置：GATE-P6, P7-BASE-FULL
- `P7-NATIVE-PROFILING`：可选原生热路径与 GDExtension（PROFILING）；前置：GATE-P6
- `P7-POLISH`：跨域平衡、性能、稳定性与体验收口；前置：GATE-P6, P7-BASE-FULL, P7-NATIVE-PROFILING
- `P7-TEST-RELEASE`：领域、集成、场景与长期测试（RELEASE）；前置：GATE-P6, P7-POLISH, P7-TOOLS-RELEASE
- `P7-CI-RELEASE`：持续集成、架构门禁与发布构建（RELEASE）；前置：GATE-P6, P7-TEST-RELEASE

### P8 · 海战独立扩展

- `P8-NAVAL-C`：海战扩展：战略水域、港口、舰队；前置：GATE-P7
- `P8-NAVAL-M`：海战扩展：船舶运动、接舷、战斗 AI；前置：GATE-P7
- `P8-NAVAL-P`：海战扩展：内容包、工具与兼容；前置：GATE-P7, P8-NAVAL-C, P8-NAVAL-M
