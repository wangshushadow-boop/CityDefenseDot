# 子系统详细设计索引 · 代码目录镜像版

57 份独立 SDD；93 个原始需求编号、208 条模块验收规格、17 条跨系统验收均保留。所有设计仍待评审，测试尚未执行。

映射规则：`<项目相对实现目录>/` → `docs/systems/<项目相对实现目录>/README.md`。例如 `game/mission/ai/tactical/` → `docs/systems/game/mission/ai/tactical/README.md`。

每份 SDD 只保留一个权威文件。多路径模块在其他目录放共享入口；更细的子目录由父 SDD 管理，导航文件不是新的独立设计。所有目录均为计划路径，不表示已有代码。

先读 [总体规格书](../game_design.md)、[公共契约](../architecture/common_contracts.md)、[依赖与研发顺序](../architecture/dependency_policy.md)、[工程目录与映射](../architecture/directory_map.md)。

## 按工程根目录浏览

| 对应实现目录 | 设计入口 | 类型 |
|---|---|---|
| `game/` | [游戏工程](game/README.md) | 分组索引 |
| `native/` | [可选原生热路径与 GDExtension](native/README.md) | 独立 SDD |
| `server/` | [服务器工程](server/README.md) | 分组索引 |
| `tools/` | [内容 CLI、验证器与开发调试工具](tools/README.md) | 独立 SDD |
| `test_scenarios/` | [验收场景与固定输入](test_scenarios/README.md) | 共享 SDD 入口 |
| `ci/` | [持续集成、架构门禁与发布构建](ci/README.md) | 独立 SDD |

## 全部独立 SDD（按代码目录）

### 游戏工程 game/

| ID | 详细设计 | 主要实现目录 | 原始章节 |
|---|---|---|---|
| BOOT | [启动、装配与配置](game/bootstrap/README.md) | `game/bootstrap/` | §2.3、§3、§19、§20 |
| CORE | [核心运行时原语与调度](game/core/README.md) | `game/core/` | §2.3、§3.3、§4.2、§19.2 |
| CON | [公共契约与版本管理](game/contracts/README.md) | `game/contracts/` | §3.3、§17、§20.2 |
| APP | [应用层、GameSession 与事务](game/application/README.md) | `game/application/` | §2.3、§3、§10.2、§17.5、§20 |
| CAMP | [战略世界运行时](game/campaign/README.md) | `game/campaign/` | §3.4、§4.2、§10.2、§17、§22 |
| WORLD | [世界地图、时钟、交通、情报](game/campaign/world/README.md) | `game/campaign/world/` | §4、§17.5、§19 |
| CHR | [英雄、成长、装备与生命状态](game/campaign/character/README.md) | `game/campaign/character/` | §5.1、§5.3、§11、§17 |
| CLAN | [家族、婚育、同伴、职责与继承](game/campaign/clan/README.md) | `game/campaign/clan/` | §5.2、§9.1、§17 |
| PARTY | [队伍、军团、名册、俘虏、补给](game/campaign/party/README.md) | `game/campaign/party/` | §6、§9.3、§10.2、§17 |
| ECO | [经济、市场、商队、工坊与锻造](game/campaign/economy/README.md) | `game/campaign/economy/` | §7、§8、§9.3、§17.5 |
| SET | [城镇、城堡、村庄与领地治理](game/campaign/settlement/README.md) | `game/campaign/settlement/` | §8、§9.1、§13、§17 |
| POL | [王国、决议、外交、战争与身份](game/campaign/politics/README.md) | `game/campaign/politics/` | §9.1–9.2、§17.5 |
| ENC | [遭遇、战略围城、预留与自动结算](game/campaign/encounter/README.md) | `game/campaign/encounter/` | §4.3、§9.4、§10.2、§13.1、§17.4 |
| QUEST | [动态任务、剧情导演、对话与事件](game/campaign/quest/README.md) | `game/campaign/quest/` | §14、§2、§8.3、§13、§17 |
| SAI | [战略 AI 总控、调度与任务规划](game/campaign/strategic_ai/README.md) | `game/campaign/strategic_ai/` | §9.3–9.5、§4.2、§19 |
| SAI-K | [战略 AI：王国规划](game/campaign/strategic_ai/kingdom/README.md) | `game/campaign/strategic_ai/kingdom/` | §9.1、§9.3、§9.5 |
| SAI-C | [战略 AI：家族规划](game/campaign/strategic_ai/clan/README.md) | `game/campaign/strategic_ai/clan/` | §5.2、§9.3 |
| SAI-A | [战略 AI：军团规划](game/campaign/strategic_ai/army/README.md) | `game/campaign/strategic_ai/army/` | §6.2、§9.3、§13.1 |
| SAI-P | [战略 AI：队伍规划与类型策略](game/campaign/strategic_ai/party/README.md) | `game/campaign/strategic_ai/party/` | §4.3、§6、§7.2、§9.3 |
| MIS-RT | [Mission 运行时、实体与增援](game/mission/runtime/README.md) | `game/mission/runtime/` | §10.1、§10.3–10.5、§11.1、§19 |
| COM | [动作、装备、命中、伤害与士气执行](game/mission/combat/README.md) | `game/mission/combat/` | §10.4、§11、§12.7、§16.2 |
| FORM | [编队、指挥授权、阵型与槽位执行](game/mission/formation/README.md) | `game/mission/formation/` | §12.1–12.4、§17.4、§10.3 |
| BAI | [战场 AI 共同基础、感知与调度](game/mission/ai/README.md) | `game/mission/ai/` | §12.1、§12.3–12.5、§19.2–19.4 |
| BAI-T | [L1 战术 AI：全军计划](game/mission/ai/tactical/README.md) | `game/mission/ai/tactical/` | §12.1、§12.3、§12.8 |
| BAI-F | [L2 编队 AI：执行战术任务](game/mission/ai/formation/README.md) | `game/mission/ai/formation/` | §12.1–12.4、§12.8 |
| BAI-I | [L3 个体 AI：士兵感知、目标与动作意图](game/mission/ai/individual/README.md) | `game/mission/ai/individual/` | §12.5、§11、§12.8 |
| MOV | [战场路径、避障、运动与动态导航](game/mission/movement/README.md) | `game/mission/movement/` | §11.5、§12.6、§13.1、§19 |
| SIEGE | [实时攻城器械、城防与动态连接](game/mission/siege/README.md) | `game/mission/siege/` | §13.1、§12、§10.2 |
| RULES | [Mission 规则、目标与玩法组合](game/mission/rules/README.md) | `game/mission/rules/` | §1.2、§10、§13.2、§16.3 |
| INTERACT | [场景交互、NPC 与访问流程](game/mission/interaction/README.md) | `game/mission/interaction/` | §8.3、§13.2、§14.3、§15 |
| RESULTS | [来源追踪、战斗结果与统计](game/mission/results/README.md) | `game/mission/results/` | §10.2、§10.5、§17.4、§22 |
| DEF | [定义数据与引用注册](game/shared/definitions/README.md) | `game/shared/definitions/` | §5–7、§17.1、§17.3、§18.2 |
| INV | [库存、账户、账本与资源事务](game/shared/inventory/README.md) | `game/shared/inventory/` | §6、§7.1、§17.5 |
| SHRULE | [公共规则、数值与效果计算](game/shared/rules/README.md) | `game/shared/rules/` | §3.3、§5、§6、§7、§11、§17 |
| UI | [界面、ReadModel 与交互流程](game/presentation/ui/README.md) | `game/presentation/ui/` | §15.1、§1.4、§2.3、§16 |
| INPUT | [输入设备、控制映射与玩家命令](game/presentation/input/README.md) | `game/presentation/input/` | §1.4、§11.2、§12.2、§15、§16.2 |
| CAM | [相机、视角、选取与观战](game/presentation/camera/README.md) | `game/presentation/camera/` | §11.2、§15.2、§16.3 |
| VIS | [地图与战场视觉代理、动画、LOD](game/presentation/visuals/README.md) | `game/presentation/visuals/` | §11.1–11.4、§15.2、§19、§21 |
| AUD | [音频、战斗语音与音乐](game/presentation/audio/README.md) | `game/presentation/audio/` | §15.2–15.3、§1.4、§21 |
| PERSIST | [存档、原子提交、迁移与恢复](game/infrastructure/persistence/README.md) | `game/infrastructure/persistence/` | §10.2、§17、§18.1、§22 |
| INF-CONTENT | [数据包编译、MOD 注册与配置合并](game/infrastructure/content/README.md) | `game/infrastructure/content/` | §17.3、§18.2、§21、§25 |
| INF-ENGINE | [引擎适配、物理、导航与资源端口](game/infrastructure/engine/README.md) | `game/infrastructure/engine/` | §19、§10.4、§11、§12.6、§20 |
| NET | [网络协议、传输、权威与状态复制](game/infrastructure/network/README.md) | `game/infrastructure/network/` | §16.2、§16.4、§17、§19 |
| TELEM | [日志、指标、诊断与崩溃报告](game/infrastructure/telemetry/README.md) | `game/infrastructure/telemetry/` | §19.4、§20.2、§22、§16.3 |
| MP | [多人会话、大厅、匹配与模式组装](game/multiplayer/README.md) | `game/multiplayer/` | §1.2、§16.1–16.4、§20 |
| ADDONS | [编辑器插件与可信扩展 SDK](game/addons/README.md) | `game/addons/` | §18.2、§20.1、§21 |
| NAVAL-C | [海战扩展：战略水域、港口、舰队](game/addons/naval/campaign/README.md) | `game/addons/naval/campaign/` | §24.1、§24.3–24.4，MOD-06 |
| NAVAL-M | [海战扩展：船舶运动、接舷、战斗 AI](game/addons/naval/mission/README.md) | `game/addons/naval/mission/` | §24.2–24.3、§12、§19，MOD-06 |
| BASE | [本体原创内容包与资源制作](game/content/base/README.md) | `game/content/base/` | §1.1–1.3、§15.2、§18、§21 |
| NAVAL-P | [海战扩展：内容包、工具与兼容](game/content/expansions/naval/README.md) | `game/content/expansions/naval/` | §24、§18.2、§21，MOD-06 |
| TEST | [领域、集成、场景与长期测试](game/tests/README.md) | `game/tests/` | §22、§23.3 |

### 原生计算 native/

| ID | 详细设计 | 主要实现目录 | 原始章节 |
|---|---|---|---|
| NATIVE | [可选原生热路径与 GDExtension](native/README.md) | `native/` | §19.1–19.4、§20.1、§23 |

### 服务器 server/

| ID | 详细设计 | 主要实现目录 | 原始章节 |
|---|---|---|---|
| SERVER-D | [专用权威战斗服务器](server/dedicated/README.md) | `server/dedicated/` | §16.1、§16.2、§19、§20 |
| SERVER-L | [大厅后端、身份、匹配与赛果](server/lobby_service/README.md) | `server/lobby_service/` | §16.1、§16.3、§16.4、§20 |
| SERVER-OPS | [部署、扩容、运维与发布](server/deployment/README.md) | `server/deployment/` | §16、§19.4、§20.3、§23 |

### 开发工具 tools/

| ID | 详细设计 | 主要实现目录 | 原始章节 |
|---|---|---|---|
| TOOLS | [内容 CLI、验证器与开发调试工具](tools/README.md) | `tools/` | §20.1、§21、§22 |

### 构建 ci/

| ID | 详细设计 | 主要实现目录 | 原始章节 |
|---|---|---|---|
| CI | [持续集成、架构门禁与发布构建](ci/README.md) | `ci/` | §20.2–20.3、§21–23 |

## 多路径模块的共享入口

| 模块 | 对应入口 | 权威设计 |
|---|---|---|
| NAVAL-P | [game/addons/naval/](game/addons/naval/README.md) | [海战扩展：内容包、工具与兼容](game/content/expansions/naval/README.md) |
| TEST | [test_scenarios/](test_scenarios/README.md) | [领域、集成、场景与长期测试](game/tests/README.md) |
