# recollection 完整交付目录

以下为实际包内文件结构；代码目录 README 仅为设计导航。详细模块映射见 [directory_map](docs/architecture/directory_map.md)。

```text
recollection/
├── .codex/
│   ├── agents/
│   │   ├── architect.toml
│   │   ├── developer.toml
│   │   ├── integration.toml
│   │   ├── planner.toml
│   │   ├── qa.toml
│   │   └── reviewer.toml
│   ├── config.toml
│   └── README.md
├── ci/
│   └── README.md
├── development/
│   ├── agents/
│   │   ├── architect.md
│   │   ├── developer.md
│   │   ├── integration.md
│   │   ├── orchestrator.md
│   │   ├── planner.md
│   │   ├── qa.md
│   │   ├── README.md
│   │   └── reviewer.md
│   ├── planning/
│   │   ├── tasks/
│   │   │   ├── P0-ENV-001.json
│   │   │   └── README.md
│   │   ├── module_owners.json
│   │   ├── roadmap.md
│   │   └── task_graph.json
│   ├── prompts/
│   │   ├── initialize.md
│   │   ├── P0.md
│   │   ├── P1.md
│   │   ├── P2.md
│   │   ├── P3.md
│   │   ├── P4.md
│   │   ├── P5.md
│   │   ├── P6.md
│   │   ├── P7.md
│   │   ├── P8.md
│   │   ├── phase.md
│   │   ├── README.md
│   │   ├── resume.md
│   │   └── review.md
│   ├── reports/
│   │   ├── benchmarks/
│   │   │   └── README.md
│   │   ├── integration/
│   │   │   └── README.md
│   │   ├── reviews/
│   │   │   └── README.md
│   │   ├── stages/
│   │   │   └── README.md
│   │   ├── tasks/
│   │   │   └── README.md
│   │   ├── tests/
│   │   │   └── README.md
│   │   ├── bootstrap_verification.md
│   │   └── README.md
│   ├── state/
│   │   ├── blockers.json
│   │   ├── locks.json
│   │   ├── modules.json
│   │   ├── project.json
│   │   ├── README.md
│   │   └── tasks.json
│   ├── templates/
│   │   ├── adr.md
│   │   ├── benchmark_report.md
│   │   ├── integration_report.md
│   │   ├── README.md
│   │   ├── review_report.md
│   │   ├── sdd_detail.md
│   │   ├── stage_report.md
│   │   ├── task.json
│   │   └── task_report.md
│   ├── workflows/
│   │   ├── acceptance.md
│   │   ├── development.md
│   │   ├── integration.md
│   │   ├── recovery.md
│   │   └── review.md
│   ├── check_diff.py
│   ├── check_project.py
│   ├── codex_setup.md
│   ├── README.md
│   └── workflow.md
├── docs/
│   ├── architecture/
│   │   ├── baselines/
│   │   │   ├── README.md
│   │   │   └── source_game_design_v1.0.md.txt
│   │   ├── decisions/
│   │   │   ├── ADR-011-technology-stack.md
│   │   │   ├── ADR-012-contract-freeze.md
│   │   │   └── README.md
│   │   ├── check_mirror.py
│   │   ├── common_contracts.md
│   │   ├── dependency_policy.md
│   │   ├── directory_map.md
│   │   ├── migration_report.md
│   │   └── module_registry.json
│   ├── content/
│   │   └── README.md
│   ├── standards/
│   │   ├── assets.md
│   │   ├── coding.md
│   │   ├── documentation.md
│   │   ├── README.md
│   │   └── testing.md
│   ├── systems/
│   │   ├── ci/
│   │   │   └── README.md
│   │   ├── game/
│   │   │   ├── addons/
│   │   │   │   ├── naval/
│   │   │   │   │   ├── campaign/
│   │   │   │   │   │   └── README.md
│   │   │   │   │   ├── mission/
│   │   │   │   │   │   └── README.md
│   │   │   │   │   └── README.md
│   │   │   │   └── README.md
│   │   │   ├── application/
│   │   │   │   └── README.md
│   │   │   ├── bootstrap/
│   │   │   │   └── README.md
│   │   │   ├── campaign/
│   │   │   │   ├── character/
│   │   │   │   │   └── README.md
│   │   │   │   ├── clan/
│   │   │   │   │   └── README.md
│   │   │   │   ├── economy/
│   │   │   │   │   └── README.md
│   │   │   │   ├── encounter/
│   │   │   │   │   └── README.md
│   │   │   │   ├── party/
│   │   │   │   │   └── README.md
│   │   │   │   ├── politics/
│   │   │   │   │   └── README.md
│   │   │   │   ├── quest/
│   │   │   │   │   └── README.md
│   │   │   │   ├── settlement/
│   │   │   │   │   └── README.md
│   │   │   │   ├── strategic_ai/
│   │   │   │   │   ├── army/
│   │   │   │   │   │   └── README.md
│   │   │   │   │   ├── clan/
│   │   │   │   │   │   └── README.md
│   │   │   │   │   ├── evaluation/
│   │   │   │   │   │   └── README.md
│   │   │   │   │   ├── kingdom/
│   │   │   │   │   │   └── README.md
│   │   │   │   │   ├── party/
│   │   │   │   │   │   └── README.md
│   │   │   │   │   ├── perception/
│   │   │   │   │   │   └── README.md
│   │   │   │   │   ├── planning/
│   │   │   │   │   │   └── README.md
│   │   │   │   │   ├── scheduler/
│   │   │   │   │   │   └── README.md
│   │   │   │   │   └── README.md
│   │   │   │   ├── world/
│   │   │   │   │   └── README.md
│   │   │   │   └── README.md
│   │   │   ├── content/
│   │   │   │   ├── base/
│   │   │   │   │   ├── assets/
│   │   │   │   │   │   └── README.md
│   │   │   │   │   ├── definitions/
│   │   │   │   │   │   └── README.md
│   │   │   │   │   ├── localization/
│   │   │   │   │   │   └── README.md
│   │   │   │   │   ├── maps/
│   │   │   │   │   │   └── README.md
│   │   │   │   │   ├── scenes/
│   │   │   │   │   │   └── README.md
│   │   │   │   │   └── README.md
│   │   │   │   ├── expansions/
│   │   │   │   │   ├── naval/
│   │   │   │   │   │   └── README.md
│   │   │   │   │   └── README.md
│   │   │   │   └── README.md
│   │   │   ├── contracts/
│   │   │   │   └── README.md
│   │   │   ├── core/
│   │   │   │   └── README.md
│   │   │   ├── infrastructure/
│   │   │   │   ├── content/
│   │   │   │   │   └── README.md
│   │   │   │   ├── engine/
│   │   │   │   │   └── README.md
│   │   │   │   ├── network/
│   │   │   │   │   └── README.md
│   │   │   │   ├── persistence/
│   │   │   │   │   └── README.md
│   │   │   │   ├── telemetry/
│   │   │   │   │   └── README.md
│   │   │   │   └── README.md
│   │   │   ├── mission/
│   │   │   │   ├── ai/
│   │   │   │   │   ├── blackboard/
│   │   │   │   │   │   └── README.md
│   │   │   │   │   ├── debug/
│   │   │   │   │   │   └── README.md
│   │   │   │   │   ├── formation/
│   │   │   │   │   │   ├── behaviors/
│   │   │   │   │   │   │   └── README.md
│   │   │   │   │   │   ├── controller/
│   │   │   │   │   │   │   └── README.md
│   │   │   │   │   │   ├── evaluation/
│   │   │   │   │   │   │   └── README.md
│   │   │   │   │   │   └── README.md
│   │   │   │   │   ├── individual/
│   │   │   │   │   │   ├── behaviors/
│   │   │   │   │   │   │   └── README.md
│   │   │   │   │   │   ├── controller/
│   │   │   │   │   │   │   └── README.md
│   │   │   │   │   │   ├── decision/
│   │   │   │   │   │   │   └── README.md
│   │   │   │   │   │   ├── roles/
│   │   │   │   │   │   │   └── README.md
│   │   │   │   │   │   ├── targeting/
│   │   │   │   │   │   │   └── README.md
│   │   │   │   │   │   └── README.md
│   │   │   │   │   ├── perception/
│   │   │   │   │   │   └── README.md
│   │   │   │   │   ├── ports/
│   │   │   │   │   │   └── README.md
│   │   │   │   │   ├── scheduler/
│   │   │   │   │   │   └── README.md
│   │   │   │   │   ├── tactical/
│   │   │   │   │   │   ├── commander/
│   │   │   │   │   │   │   └── README.md
│   │   │   │   │   │   ├── evaluation/
│   │   │   │   │   │   │   └── README.md
│   │   │   │   │   │   ├── planning/
│   │   │   │   │   │   │   └── README.md
│   │   │   │   │   │   ├── strategies/
│   │   │   │   │   │   │   └── README.md
│   │   │   │   │   │   └── README.md
│   │   │   │   │   └── README.md
│   │   │   │   ├── combat/
│   │   │   │   │   └── README.md
│   │   │   │   ├── formation/
│   │   │   │   │   └── README.md
│   │   │   │   ├── interaction/
│   │   │   │   │   └── README.md
│   │   │   │   ├── movement/
│   │   │   │   │   └── README.md
│   │   │   │   ├── results/
│   │   │   │   │   └── README.md
│   │   │   │   ├── rules/
│   │   │   │   │   └── README.md
│   │   │   │   ├── runtime/
│   │   │   │   │   └── README.md
│   │   │   │   ├── siege/
│   │   │   │   │   └── README.md
│   │   │   │   └── README.md
│   │   │   ├── multiplayer/
│   │   │   │   └── README.md
│   │   │   ├── presentation/
│   │   │   │   ├── audio/
│   │   │   │   │   └── README.md
│   │   │   │   ├── camera/
│   │   │   │   │   └── README.md
│   │   │   │   ├── input/
│   │   │   │   │   └── README.md
│   │   │   │   ├── ui/
│   │   │   │   │   └── README.md
│   │   │   │   ├── visuals/
│   │   │   │   │   └── README.md
│   │   │   │   └── README.md
│   │   │   ├── shared/
│   │   │   │   ├── definitions/
│   │   │   │   │   └── README.md
│   │   │   │   ├── inventory/
│   │   │   │   │   └── README.md
│   │   │   │   ├── rules/
│   │   │   │   │   └── README.md
│   │   │   │   └── README.md
│   │   │   ├── tests/
│   │   │   │   └── README.md
│   │   │   └── README.md
│   │   ├── native/
│   │   │   ├── benchmarks/
│   │   │   │   └── README.md
│   │   │   ├── include/
│   │   │   │   └── README.md
│   │   │   ├── src/
│   │   │   │   └── README.md
│   │   │   └── README.md
│   │   ├── server/
│   │   │   ├── dedicated/
│   │   │   │   └── README.md
│   │   │   ├── deployment/
│   │   │   │   └── README.md
│   │   │   ├── lobby_service/
│   │   │   │   └── README.md
│   │   │   └── README.md
│   │   ├── test_scenarios/
│   │   │   └── README.md
│   │   ├── tools/
│   │   │   └── README.md
│   │   └── README.md
│   ├── testing/
│   │   ├── acceptance_matrix.md
│   │   ├── requirements_trace.csv
│   │   └── test_cases.csv
│   └── game_design.md
├── game/
│   ├── addons/
│   │   ├── naval/
│   │   │   ├── campaign/
│   │   │   │   └── README.md
│   │   │   ├── mission/
│   │   │   │   └── README.md
│   │   │   └── README.md
│   │   └── README.md
│   ├── application/
│   │   └── README.md
│   ├── bootstrap/
│   │   └── README.md
│   ├── campaign/
│   │   ├── character/
│   │   │   └── README.md
│   │   ├── clan/
│   │   │   └── README.md
│   │   ├── economy/
│   │   │   └── README.md
│   │   ├── encounter/
│   │   │   └── README.md
│   │   ├── party/
│   │   │   └── README.md
│   │   ├── politics/
│   │   │   └── README.md
│   │   ├── quest/
│   │   │   └── README.md
│   │   ├── settlement/
│   │   │   └── README.md
│   │   ├── strategic_ai/
│   │   │   ├── army/
│   │   │   │   └── README.md
│   │   │   ├── clan/
│   │   │   │   └── README.md
│   │   │   ├── evaluation/
│   │   │   │   └── README.md
│   │   │   ├── kingdom/
│   │   │   │   └── README.md
│   │   │   ├── party/
│   │   │   │   └── README.md
│   │   │   ├── perception/
│   │   │   │   └── README.md
│   │   │   ├── planning/
│   │   │   │   └── README.md
│   │   │   ├── scheduler/
│   │   │   │   └── README.md
│   │   │   └── README.md
│   │   ├── world/
│   │   │   └── README.md
│   │   └── README.md
│   ├── content/
│   │   ├── base/
│   │   │   ├── assets/
│   │   │   │   └── README.md
│   │   │   ├── definitions/
│   │   │   │   └── README.md
│   │   │   ├── localization/
│   │   │   │   └── README.md
│   │   │   ├── maps/
│   │   │   │   └── README.md
│   │   │   ├── scenes/
│   │   │   │   └── README.md
│   │   │   └── README.md
│   │   ├── expansions/
│   │   │   ├── naval/
│   │   │   │   └── README.md
│   │   │   └── README.md
│   │   └── README.md
│   ├── contracts/
│   │   └── README.md
│   ├── core/
│   │   └── README.md
│   ├── infrastructure/
│   │   ├── content/
│   │   │   └── README.md
│   │   ├── engine/
│   │   │   └── README.md
│   │   ├── network/
│   │   │   └── README.md
│   │   ├── persistence/
│   │   │   └── README.md
│   │   ├── telemetry/
│   │   │   └── README.md
│   │   └── README.md
│   ├── mission/
│   │   ├── ai/
│   │   │   ├── blackboard/
│   │   │   │   └── README.md
│   │   │   ├── debug/
│   │   │   │   └── README.md
│   │   │   ├── formation/
│   │   │   │   ├── behaviors/
│   │   │   │   │   └── README.md
│   │   │   │   ├── controller/
│   │   │   │   │   └── README.md
│   │   │   │   ├── evaluation/
│   │   │   │   │   └── README.md
│   │   │   │   └── README.md
│   │   │   ├── individual/
│   │   │   │   ├── behaviors/
│   │   │   │   │   └── README.md
│   │   │   │   ├── controller/
│   │   │   │   │   └── README.md
│   │   │   │   ├── decision/
│   │   │   │   │   └── README.md
│   │   │   │   ├── roles/
│   │   │   │   │   └── README.md
│   │   │   │   ├── targeting/
│   │   │   │   │   └── README.md
│   │   │   │   └── README.md
│   │   │   ├── perception/
│   │   │   │   └── README.md
│   │   │   ├── ports/
│   │   │   │   └── README.md
│   │   │   ├── scheduler/
│   │   │   │   └── README.md
│   │   │   ├── tactical/
│   │   │   │   ├── commander/
│   │   │   │   │   └── README.md
│   │   │   │   ├── evaluation/
│   │   │   │   │   └── README.md
│   │   │   │   ├── planning/
│   │   │   │   │   └── README.md
│   │   │   │   ├── strategies/
│   │   │   │   │   └── README.md
│   │   │   │   └── README.md
│   │   │   └── README.md
│   │   ├── combat/
│   │   │   └── README.md
│   │   ├── formation/
│   │   │   └── README.md
│   │   ├── interaction/
│   │   │   └── README.md
│   │   ├── movement/
│   │   │   └── README.md
│   │   ├── results/
│   │   │   └── README.md
│   │   ├── rules/
│   │   │   └── README.md
│   │   ├── runtime/
│   │   │   └── README.md
│   │   ├── siege/
│   │   │   └── README.md
│   │   └── README.md
│   ├── multiplayer/
│   │   └── README.md
│   ├── presentation/
│   │   ├── audio/
│   │   │   └── README.md
│   │   ├── camera/
│   │   │   └── README.md
│   │   ├── input/
│   │   │   └── README.md
│   │   ├── ui/
│   │   │   └── README.md
│   │   ├── visuals/
│   │   │   └── README.md
│   │   └── README.md
│   ├── shared/
│   │   ├── definitions/
│   │   │   └── README.md
│   │   ├── inventory/
│   │   │   └── README.md
│   │   ├── rules/
│   │   │   └── README.md
│   │   └── README.md
│   ├── tests/
│   │   └── README.md
│   └── README.md
├── native/
│   ├── benchmarks/
│   │   └── README.md
│   ├── include/
│   │   └── README.md
│   ├── src/
│   │   └── README.md
│   └── README.md
├── schemas/
│   ├── development_task.schema.json
│   └── README.md
├── server/
│   ├── dedicated/
│   │   └── README.md
│   ├── deployment/
│   │   └── README.md
│   ├── lobby_service/
│   │   └── README.md
│   └── README.md
├── test_scenarios/
│   └── README.md
├── tools/
│   └── README.md
├── .gitattributes
├── .gitignore
├── AGENTS.md
├── CHANGELOG.md
├── KNOWN_ISSUES.md
├── PROJECT.md
├── PROJECT_STATE.md
├── PROJECT_TREE.md
└── README.md
```
