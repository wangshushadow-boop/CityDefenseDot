# P1-CAMP-RUNTIME-001 战略世界运行时

- CANDIDATE。开发者 p1ports，工作区 `.worktrees/p1-campaign` 位于分离 HEAD `dd832adc93a2206196aab105ae8024a6994d59d6`。候选以新增文件交主 Agent，无提交。
- CAMP SDD 及 GDD §4.2，需求 WLD-02、WLD-04、WLD-05、SAI-03、ECO-06。授权内新增 `game/campaign/runtime.gd`、`game/tests/p1/campaign/run.gd` 和本报告。未修改权威契约或独立子模块。
- 可复核的工作树 SHA-256 为生产脚本 `62D255A93BFB847BF4C6C21B5920B51F1A08EE545FD24F80092551CA861A1882`、测试脚本 `6F17096935998C828D0484D7F1FEE30FFABF453EFC88086E5F7EF73038F11034`。

## 运行时边界

`create_world(seed,start_def,content,authorize)` 接受已编译内容的 hash 和有序包表、整数初始分钟、可选起始库存与世界标识。未指定标识时，按稳定起始内容和 CORE 随机流生成带 `world/` 标签的 UUIDv4。存档中保留种子和可恢复的独立流。空世界可创建、步进、保存和销毁。

`step_until(target_minute,budget)` 只驱动一个整数分钟时钟。跨日按生产、账务校验、市场、供给薪资、领地、政治 AI、日终排列；同相位由 `register_phase` 键稳定排序。规则回调产生纯数据写集，INV 预检并在日终统一提交。预算以一次注册回调、相位边界或日内推进计数。预算中断时对外仍读上一次提交，存档、冻结和外部交易入口等待安全点。日结写集失败后暂停，恢复已验证快照即可回到安全边界。

`read_snapshot` 提供公开的时钟与版本投影。`save_snapshot` 输出独立世界快照，含 world_id、game_minute、revision、content_hash、content_packages、seed、rng_states、last_committed_day、freeze、inventory 和 schema_version。`restore` 校验自身关键字段、时钟、CORE 流与 INV 快照，成功后替换状态；APP 持有的扩展应在 APP 边界拆装。`freeze_for_encounter` 与 `release_freeze` 验证 EncounterId 类型与冻结版本，返回后由调用方按规则给出目标分钟。

`exchange(txn_id,lines,expected_inventory_revision,durable)` 的版本参数属于 INV 账本。APP 负责命令去重后的世界版本检查。durable 收到世界候选及 INV 回执，回调成功后发布世界版本和已提交库存。相同交易重试返回原回执，无额外保存和版本推进。CAMP 使用 INV 的公开 prepare、commit、snapshot、restore 和 ledger_for，生产代码未引用 Mission、PERSIST 私有实现或未来经济政治域。

## 自测结果

Windows，Godot `4.7.2.stable.official.ed1daf0bf`。从上述工作树执行，外层同时检查引擎状态、脚本报错及四个 PASS 标记。

```powershell
& 'D:/Program/Godot/Standard/Godot_v4.7.2-stable_win64_console.exe' --headless --path game --log-file "$env:TEMP/recollection-p1-camp-agent.log" --quit-after 120 --script res://tests/p1/campaign/run.gd
```

| 验收 ID | 结果 | 实际证据 |
|---|---|---|
| T-CAMP-01 | PASS，退出 0 | 跨帧续跑与一次性执行产生相同世界、随机轨迹及真实 INV 账本。生产回调只扣一笔，重复目标和重复日计划提交均未加扣。预算中断看不到半日，账本失败回滚且停止推进。 |
| T-CAMP-03 | PASS，退出 0 | 实际编译内置 base 包，固定种子 `0011223344556677` 用于两次开局。调换初始库存枚举顺序，规范哈希仍相同。另测不同种子生成不同世界、冷启动后随机流继续产生相同轨迹。 |
| T-CAMP-02 | 完整用例 NOT_RUN，P1-CAMP-FREEZE-TRADE 切片 PASS，退出 0 | 按类型化遭遇令牌冻结、保存、还原、释放并按调用方目标推进。候选存档失败保留原世界，成功后世界和实际 INV 回执一起可见。尚无真实访问场景、遭遇及远方队伍仿真。 |
| T-CAMP-04 | 完整十年用例 NOT_RUN，P1-CAMP-20-SEED-SLICE 切片 PASS，退出 0 | 20 个固定种子各运行 10 日，共 200 次逐日核查。测试回调在两个实账间转移 1–3 单位，按日验证总量、非负和日结流水。未运行后续经济、政治、战略 AI 及孤儿引用、软指标十年门禁。 |

第一轮测试退出 1，测试数据的常量表达式和运行时布尔变量的类型推断在脚本加载阶段出错。修复后正式入口四个标记均输出，Godot 与外层退出码均为 0。审查反馈还促成未知字段拒载、类型化遭遇令牌及显式库存版本域，已纳入测试。

## 交接

独立 QA、审查与集成另由主 Agent 记录。300–500 地点、2,000–5,000 队伍规模性能、真实访问和战役十年门禁本次未执行。
