# 第 20.1 节补充：工程目录与设计文档镜像映射

> 原文 `docs/game_design.md` 按上传内容原样保留；本补充是详细设计的目录落地建议（镜像版 0.2）。各路径是计划实现路径，不创建空代码目录。新增路径通过 ADR-005/010 评审。

```text
recollection/
├── docs/
│   ├── game_design.md
│   ├── architecture/
│   ├── systems/                     # 镜像项目目录，详细设计使用 README.md
│   ├── content/
│   ├── standards/                   # 全局规范导航
│   └── testing/
├── game/
│   ├── project.godot                 # Godot 仍为候选
│   ├── bootstrap/
│   ├── core/
│   ├── contracts/
│   ├── application/
│   ├── campaign/
│   │   ├── campaign_runtime.*        # 根级编排，不新建另一个 Session
│   │   ├── world/
│   │   ├── character/
│   │   ├── clan/
│   │   ├── party/
│   │   ├── economy/
│   │   ├── settlement/
│   │   ├── politics/
│   │   ├── encounter/
│   │   ├── quest/
│   │   └── strategic_ai/              # L0 战略 AI (SAI)
│   │       ├── kingdom/              # SAI-K
│   │       ├── clan/                 # SAI-C
│   │       ├── army/                 # SAI-A
│   │       ├── party/                # SAI-P
│   │       ├── planning/             # HTN、计划状态机
│   │       ├── evaluation/           # Utility、硬约束
│   │       ├── perception/           # 许可情报投影
│   │       └── scheduler/            # 低频错峰
│   ├── mission/
│   │   ├── runtime/
│   │   ├── combat/
│   │   ├── formation/                # FORM，编队指令、成员、槽位执行
│   │   ├── ai/                       # BAI，战场 AI
│   │   │   ├── tactical/             # L1 BAI-T
│   │   │   │   ├── commander/
│   │   │   │   ├── strategies/
│   │   │   │   ├── evaluation/
│   │   │   │   └── planning/
│   │   │   ├── formation/            # L2 BAI-F：编队行为决策
│   │   │   │   ├── controller/
│   │   │   │   ├── behaviors/
│   │   │   │   └── evaluation/
│   │   │   ├── individual/           # L3 BAI-I：士兵决策
│   │   │   │   ├── controller/
│   │   │   │   ├── decision/
│   │   │   │   ├── targeting/
│   │   │   │   ├── behaviors/
│   │   │   │   └── roles/             # infantry, archer, cavalry, horse_archer
│   │   │   ├── perception/
│   │   │   ├── blackboard/
│   │   │   ├── scheduler/
│   │   │   ├── ports/
│   │   │   └── debug/
│   │   ├── movement/
│   │   ├── siege/
│   │   ├── rules/
│   │   ├── interaction/
│   │   └── results/
│   ├── shared/
│   │   ├── definitions/
│   │   ├── inventory/
│   │   └── rules/
│   ├── presentation/
│   │   ├── ui/
│   │   ├── input/
│   │   ├── camera/
│   │   ├── visuals/
│   │   └── audio/
│   ├── infrastructure/
│   │   ├── persistence/
│   │   ├── content/
│   │   ├── engine/
│   │   ├── network/
│   │   └── telemetry/
│   ├── multiplayer/
│   ├── addons/
│   │   └── naval/                    # EXT 可信扩展代码，建议路径
│   │       ├── campaign/
│   │       └── mission/
│   ├── content/
│   │   ├── base/
│   │   │   ├── definitions/
│   │   │   ├── maps/
│   │   │   ├── scenes/
│   │   │   ├── assets/
│   │   │   └── localization/
│   │   └── expansions/naval/         # EXT 内容包
│   └── tests/
├── native/
│   ├── include/
│   ├── src/
│   └── benchmarks/
├── server/
│   ├── dedicated/
│   ├── lobby_service/
│   └── deployment/
├── tools/
├── test_scenarios/
└── ci/
```

## 文档目录镜像（正式导航规则）

- 代码路径 `game/mission/ai/tactical/` 对应 `docs/systems/game/mission/ai/tactical/README.md`；其余计划实现目录同理。
- 父级独立 SDD 继续负责本模块的公共职责，下一级目录有独立 SDD 则使用其自身 README；没有独立 SDD 时仅创建导航入口。逻辑模块镜像不要求每个源代码文件都配一份文档。
- `NAVAL-P` 以 `game/content/expansions/naval/` 为主目录，`game/addons/naval/` 为共享入口；`TEST` 以 `game/tests/` 为主目录，`test_scenarios/` 为共享入口。两个入口共用同一模块 ID 和测试，不复制设计正文。
- 全局规格、架构契约、内容设定及测试追踪文件独立存放；代码目录中的 README 若后续建立，应只指向正式设计。目录变更必须同步 `module_registry.json` 和相关链接/追踪文件。
- [模块注册表](module_registry.json) 中 `code_paths` 与 `entrypoints` 逐项对应，`doc` 指向唯一权威 SDD；`directory_entries` 覆盖本补充列出的全部逻辑目录。所有新增实现路径仍是提案。

```text
docs/systems/
├── README.md  # 总索引
├── game/
│   ├── README.md  # 分组入口
│   ├── bootstrap/
│   │   └── README.md  # 独立 SDD
│   ├── core/
│   │   └── README.md  # 独立 SDD
│   ├── contracts/
│   │   └── README.md  # 独立 SDD
│   ├── application/
│   │   └── README.md  # 独立 SDD
│   ├── campaign/
│   │   ├── README.md  # 独立 SDD
│   │   ├── world/
│   │   │   └── README.md  # 独立 SDD
│   │   ├── character/
│   │   │   └── README.md  # 独立 SDD
│   │   ├── clan/
│   │   │   └── README.md  # 独立 SDD
│   │   ├── party/
│   │   │   └── README.md  # 独立 SDD
│   │   ├── economy/
│   │   │   └── README.md  # 独立 SDD
│   │   ├── settlement/
│   │   │   └── README.md  # 独立 SDD
│   │   ├── politics/
│   │   │   └── README.md  # 独立 SDD
│   │   ├── encounter/
│   │   │   └── README.md  # 独立 SDD
│   │   ├── quest/
│   │   │   └── README.md  # 独立 SDD
│   │   └── strategic_ai/
│   │       ├── README.md  # 独立 SDD
│   │       ├── kingdom/
│   │       │   └── README.md  # 独立 SDD
│   │       ├── clan/
│   │       │   └── README.md  # 独立 SDD
│   │       ├── army/
│   │       │   └── README.md  # 独立 SDD
│   │       ├── party/
│   │       │   └── README.md  # 独立 SDD
│   │       ├── planning/
│   │       │   └── README.md  # 父规格导航
│   │       ├── evaluation/
│   │       │   └── README.md  # 父规格导航
│   │       ├── perception/
│   │       │   └── README.md  # 父规格导航
│   │       └── scheduler/
│   │           └── README.md  # 父规格导航
│   ├── mission/
│   │   ├── README.md  # 分组入口
│   │   ├── runtime/
│   │   │   └── README.md  # 独立 SDD
│   │   ├── combat/
│   │   │   └── README.md  # 独立 SDD
│   │   ├── formation/
│   │   │   └── README.md  # 独立 SDD
│   │   ├── ai/
│   │   │   ├── README.md  # 独立 SDD
│   │   │   ├── tactical/
│   │   │   │   ├── README.md  # 独立 SDD
│   │   │   │   ├── commander/
│   │   │   │   │   └── README.md  # 父规格导航
│   │   │   │   ├── strategies/
│   │   │   │   │   └── README.md  # 父规格导航
│   │   │   │   ├── evaluation/
│   │   │   │   │   └── README.md  # 父规格导航
│   │   │   │   └── planning/
│   │   │   │       └── README.md  # 父规格导航
│   │   │   ├── formation/
│   │   │   │   ├── README.md  # 独立 SDD
│   │   │   │   ├── controller/
│   │   │   │   │   └── README.md  # 父规格导航
│   │   │   │   ├── behaviors/
│   │   │   │   │   └── README.md  # 父规格导航
│   │   │   │   └── evaluation/
│   │   │   │       └── README.md  # 父规格导航
│   │   │   ├── individual/
│   │   │   │   ├── README.md  # 独立 SDD
│   │   │   │   ├── controller/
│   │   │   │   │   └── README.md  # 父规格导航
│   │   │   │   ├── decision/
│   │   │   │   │   └── README.md  # 父规格导航
│   │   │   │   ├── targeting/
│   │   │   │   │   └── README.md  # 父规格导航
│   │   │   │   ├── behaviors/
│   │   │   │   │   └── README.md  # 父规格导航
│   │   │   │   └── roles/
│   │   │   │       └── README.md  # 父规格导航
│   │   │   ├── perception/
│   │   │   │   └── README.md  # 父规格导航
│   │   │   ├── blackboard/
│   │   │   │   └── README.md  # 父规格导航
│   │   │   ├── scheduler/
│   │   │   │   └── README.md  # 父规格导航
│   │   │   ├── ports/
│   │   │   │   └── README.md  # 父规格导航
│   │   │   └── debug/
│   │   │       └── README.md  # 父规格导航
│   │   ├── movement/
│   │   │   └── README.md  # 独立 SDD
│   │   ├── siege/
│   │   │   └── README.md  # 独立 SDD
│   │   ├── rules/
│   │   │   └── README.md  # 独立 SDD
│   │   ├── interaction/
│   │   │   └── README.md  # 独立 SDD
│   │   └── results/
│   │       └── README.md  # 独立 SDD
│   ├── shared/
│   │   ├── README.md  # 分组入口
│   │   ├── definitions/
│   │   │   └── README.md  # 独立 SDD
│   │   ├── inventory/
│   │   │   └── README.md  # 独立 SDD
│   │   └── rules/
│   │       └── README.md  # 独立 SDD
│   ├── presentation/
│   │   ├── README.md  # 分组入口
│   │   ├── ui/
│   │   │   └── README.md  # 独立 SDD
│   │   ├── input/
│   │   │   └── README.md  # 独立 SDD
│   │   ├── camera/
│   │   │   └── README.md  # 独立 SDD
│   │   ├── visuals/
│   │   │   └── README.md  # 独立 SDD
│   │   └── audio/
│   │       └── README.md  # 独立 SDD
│   ├── infrastructure/
│   │   ├── README.md  # 分组入口
│   │   ├── persistence/
│   │   │   └── README.md  # 独立 SDD
│   │   ├── content/
│   │   │   └── README.md  # 独立 SDD
│   │   ├── engine/
│   │   │   └── README.md  # 独立 SDD
│   │   ├── network/
│   │   │   └── README.md  # 独立 SDD
│   │   └── telemetry/
│   │       └── README.md  # 独立 SDD
│   ├── multiplayer/
│   │   └── README.md  # 独立 SDD
│   ├── addons/
│   │   ├── README.md  # 独立 SDD
│   │   └── naval/
│   │       ├── README.md  # 共享入口
│   │       ├── campaign/
│   │       │   └── README.md  # 独立 SDD
│   │       └── mission/
│   │           └── README.md  # 独立 SDD
│   ├── content/
│   │   ├── README.md  # 分组入口
│   │   ├── base/
│   │   │   ├── README.md  # 独立 SDD
│   │   │   ├── definitions/
│   │   │   │   └── README.md  # 父规格导航
│   │   │   ├── maps/
│   │   │   │   └── README.md  # 父规格导航
│   │   │   ├── scenes/
│   │   │   │   └── README.md  # 父规格导航
│   │   │   ├── assets/
│   │   │   │   └── README.md  # 父规格导航
│   │   │   └── localization/
│   │   │       └── README.md  # 父规格导航
│   │   └── expansions/
│   │       ├── README.md  # 分组入口
│   │       └── naval/
│   │           └── README.md  # 独立 SDD
│   └── tests/
│       └── README.md  # 独立 SDD
├── native/
│   ├── README.md  # 独立 SDD
│   ├── include/
│   │   └── README.md  # 父规格导航
│   ├── src/
│   │   └── README.md  # 父规格导航
│   └── benchmarks/
│       └── README.md  # 父规格导航
├── server/
│   ├── README.md  # 分组入口
│   ├── dedicated/
│   │   └── README.md  # 独立 SDD
│   ├── lobby_service/
│   │   └── README.md  # 独立 SDD
│   └── deployment/
│       └── README.md  # 独立 SDD
├── tools/
│   └── README.md  # 独立 SDD
├── test_scenarios/
│   └── README.md  # 共享入口
└── ci/
    └── README.md  # 独立 SDD
```

## 分层 AI 追溯

| 层级 | 设计文档 | 入口 | 决策输出 |
|---|---|---|---|
| L0 | [战略 AI 总控](../systems/game/campaign/strategic_ai/README.md) | CampaignRuntime | 战略 Command / Plan |
| L0 子层 | [王国](../systems/game/campaign/strategic_ai/kingdom/README.md)、[家族](../systems/game/campaign/strategic_ai/clan/README.md)、[军团](../systems/game/campaign/strategic_ai/army/README.md)、[队伍](../systems/game/campaign/strategic_ai/party/README.md) | SAI scheduler | 目标、合法命令 |
| 战场公共 | [感知与调度](../systems/game/mission/ai/README.md) | MissionRuntime | 可见快照、调度任务 |
| L1 | [战术 AI](../systems/game/mission/ai/tactical/README.md) | TacticalCommander | FormationTask/Order |
| L2 | [编队 AI](../systems/game/mission/ai/formation/README.md) | FormationBrain | BehaviorIntent/MemberConstraint |
| L3 | [个体 AI](../systems/game/mission/ai/individual/README.md) | AgentBrain | Move/Attack/Block Intent |
| 执行 | [编队](../systems/game/mission/formation/README.md)、[移动](../systems/game/mission/movement/README.md)、[战斗](../systems/game/mission/combat/README.md) | MissionRuntime | 权威状态变化 |

各 AI 层不直接写领域真值。`mission/ai/formation/` 是决策，`mission/formation/` 是队形及订单执行；战略 AI 和战场 AI 无直接代码依赖，仅以 Encounter/Mission 契约衔接。详细模块映射见[系统索引](../systems/README.md)。

## 研发包补充目录（0.3）

代码骨架已按 96 个注册路径创建 README，均为导航，不是实现。引擎入口（如 project.godot）由 P0/P1 决策后创建。新增 `.codex/`、`development/`、`schemas/` 和 `docs/architecture/decisions/` 属于研发管理而非新增游戏模块；具体组织见 [项目目录索引](../../PROJECT_TREE.md)。
