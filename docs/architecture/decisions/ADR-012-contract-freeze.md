# ADR-012 — 公共契约 v1 冻结

**APPROVED · 2026-11-24 · 批准人：项目负责人。** 关联原 ADR-002/003/005/007。本文给出 P0-CONTRACTS-001 的已批准的表示和兼容政策。字段清单与唯一写入方沿用[公共契约 §1–7](../common_contracts.md)，跨域最小字段沿用[总体规格 §17.4](../../game_design.md)。本阶段交付契约基线和隔离向量。

## 已批准的表示

| 决策 | v1 语义及理由 |
|---|---|
| 身份 | Hero、Party 等持久实体及 Encounter 使用类型标签加小写规范 UUIDv4 字符串，如 `party/b48883c0-79fb-4cd3-96fe-43bb44dfddbb`。读取时同时校验标签与 UUID。各所有者分配、持久化并检查唯一性，禁复用。重放需要生成 ID 的领域从已版本化、可恢复的独立伪随机流按稳定顺序取位并设置 version/variant，碰撞取下一值。相比把 64 位数直接作为 JSON 数字，多进程合并方便，代价为更大的键和索引。紧凑的会话索引仅在对应 Mission 内有效。DefId 保持 `namespace:type/name`。 |
| 作用域 | Team、Formation 和 Agent 属于一个 Mission。句柄 index 为 uint32，generation 取 1..2³²−1。回收递增，达到上限则退役槽，禁止回绕复活旧引用。SourceSlotId 为 Encounter 内 uint32，区间使用左闭右开 [start,stop)，末端可取 2³²。坐骑另外统计。 |
| 数值 | JSON 中整数限定 ±(2⁵³−1)，非负最小货币单位、影响、人数、GameMinute、SimTick、Revision 各自校验非负且只接受整数。大于此范围的无符号 64 位 RNG 种子/状态采用固定 16 位小写十六进制字符串。可空字段用 null（零仍有值）；同一版本的规范对象总是输出该可空键。字段溢出拒绝，除显式货币取整政策外禁止静默截断。 |
| 坐标 | Mission 右手系，+X 右、+Y 上、−Z 前，内部使用米、秒、弧度。跨实现位置样例每轴有符号 int32 毫米，最近值取整，正负半单位均远离零。方向角的边界单位为有符号整数微弧度，采用同一取整规则，yaw 先归一至 [−π,π)。WorldMapPos 使用地图定义的坐标及比例，由引擎适配器显式投影。网络相对原点/压缩可独立编码，但解码须恢复协议规定的轴和精度。 |
| 规范字节和摘要 | schema 定义对象键为可打印非空 ASCII，升序排列，数组保持语义顺序，无序集合按各自稳定 ID 先排序。UTF-8、NFC 字符串、不写 BOM/空格/尾换行。双引号、反斜杠及控制字符使用 JSON 转义，其他 Unicode 原文编码。数值只用十进制整数，零规范为 0；拒绝重复键、非有限数和浮点，分数先按字段规则量化。SHA-256 输出 64 个小写十六进制字符。MissionResult 排除顶层 integrity_hash 自身后取摘要；ContentHash 针对按依赖顺序及稳定 ID 排好的包版本和规范化定义/资产摘要清单。PERSIST 文件 checksum 覆盖被引用的实际快照字节，读盘先验文件，再验引用。 |
| 交换与存储 | 使用上述规范 JSON 作为命令/契约样例、manifest 和不可变快照的逻辑编码。保留 §18.1 的 world.bin、transactions.bin、备份及提交标记；落盘压缩/容器按 save schema 标识，网络热路径按 protocol_version 单独编码。压缩前后的摘要对象分开标识。P0 的向量未测大世界存档尺寸、原子替换或协议吞吐。 |

## 权威端口和时序

1. **命令、查询和回执。** CON 唯一定义 ID、Result、错误、Envelope 和 SnapshotStamp，CORE 引用它们调度。APP 从已验证的会话确定 actor/scope。对已认证发起方，先查询 scope + actor + command_id 的已提交记录，同 ID 且规范请求相同返回原回执（即使旧 expected_revision 已经过期），不同内容返回 Conflict。新命令经权限/expected_revision/不变量校验后一次提交写集、revision 及去重记录，随后发布事件。Query 仅输出按可见性过滤的只读版本投影。错误码及恢复方式见公共契约 §2。
2. **快照和 tick。** WORLD 持有 GameMinute，MIS-RT 持有 SimTick，业务 revision 随提交递增。工作线程读取不可变 SnapshotStamp，返回同一 scope/tick、generation、control/nav_revision 的候选；主线程到屏障按稳定顺序合并。快照过期返回 StaleVersion，句柄过期返回 NotFound。意图以批次送入真实权威阶段。P0 基线为单人 60 Hz、专服 30 Hz，快照 15 Hz，各局建立时通告并锁定。频率和 P0 回溯窗口按已批准的 ADR-011；服务端用权威时间及有限历史判断，客户端不可指定任意旧 tick。
3. **EncounterSpec → MissionResult。** ENC 预留兵源，APP 创建战前检查点并传 §17.4 的完整 EncounterSpec 给 MIS-RT。Hero 的 count 必须为 1，预留区间不重叠。RESULTS 在结束屏障以不可变快照为每个槽写恰好一个六态结局（含 not_spawned），伤情独立于撤离。结果经 APP 按模式路由；战役才校验 encounter_id、reservation_revision、全部来源、俘虏容量和结果摘要。战役伤病转换、经验和俘虏落地由 ENC 协调各唯一写入方，最终写集与 applied_result_id 同一持久提交。自定义结果送本机统计，多人结果送认证赛局服务。
4. **FormationOrder。** 玩家、AI 和网络经同一合法命令入口。FORM 唯一写控制权、成员、队列及槽位，MOV 唯一写位置和 nav_revision，COM 唯一写动作和生命。FORM 校验同 Mission、认证 issuer、所有目标编队授权、输入序列、issued_tick 及有效控制版本。撤销委派立即使旧授权失效。过期目标刷新或失败；已提交重试按原回执处理。队列策略、完成条件和超时放进 parameters 的版本化子 schema，不扩展 §17.4 顶层。网络鉴权和权限验证先于命令去重。

## 版本、迁移与冲突裁决

| 边界或分歧 | 裁决与消费者影响 |
|---|---|
| CON 与 CORE 都提及 ID/Result | 依赖方向 CORE → CON。公共值类型只定义在 CON，CORE 提供时钟、调度、随机流和事件投递。APP 的 ChangeSet.events 按公共契约的 committed_events 解释为待提交事件集合，提交后投递。 |
| RESULTS 统计 captured 与 ENC 结算可能重新判定俘虏 | 保留 §17.4 单槽六态输入以及撤离伤情。战场记录供结算验证，战役实际归属仅依 ENC 结算回执；库存和队伍的所有权不转给 RESULTS。 |
| 存档格式 | save schema 独立版本。加载时验证 checksum/内容依赖，按 vN→vN+1 对副本执行纯数据迁移，先恢复动态定义、再解析引用。缺迁移、未知关键字段、枚举或必需 MOD 均返回诊断并保留原档。向量 v0 是合成旧头，尚无已发行档案。 |
| 协议、内容及 ABI | 会话建立时校验 protocol_version、内容 API 版本及 ContentHash。初版要求相等；缺版本协商或内容不合时在进入前拒绝。MOD 读取公开注册接口，清单声明所需 API、依赖版本和内容摘要；显式声明为可忽略且无权威语义的扩展才允许跳过。原生 ABI 独立版本，升级没有已验证的兼容层则拒载。 |
| 自检与签名 | 客户端提供的摘要只做损坏/兼容性检查；多人身份及赛果的认证由服务端信任链完成。战役和 Mission 间只交换公开纯数据。 |

## 批准及验证

指定 Godot 4.7.2 与 Python 在固定三字段消息上得到相同规范字节和 SHA-256。引擎默认数值解析会合并整数与浮点词法，重复键以后值覆盖；因此，要求规范线格式的端口必须在接受前按 schema 校验并核对原始字节。接受非规范排版的编辑源须在词法层检查键的唯一性和整数文法，再规范化。Unicode 仍采用 NFC，实验字符子集仅用于 P0 向量。六步网络历史窗在 30 Hz 回环中测到了边界行为，生产公平性在 P6 复核。[跨引擎向量](../../../development/reports/tasks/P0-CONTRACTS-002.md) · [受限历史实测](../../../development/reports/tasks/P0-NET-002.md)

2026-11-24，项目负责人在本次会话回复“批准两份 ADR 和 P0 验收”，确认本版本的持久 ID、单位、规范化与哈希、权威时序及版本兼容政策。P1 仍需为完整 schema 验证两端编解码、真实幂等事务与故障恢复；实际对战的回溯公平性随完整专服复验。此后变更数值范围或协议须同步版本、消费者清单和迁移向量。[CON-VECTORS 脚本](../../../test_scenarios/p0/P0-CONTRACTS-001/vectors.py) · [实验记录](../../../development/reports/tasks/P0-CONTRACTS-001.md)
