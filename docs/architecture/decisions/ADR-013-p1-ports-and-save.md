# ADR-013 — P1 战场、联网、MOD 端口和存档提交

**APPROVED · 2026-11-24 · 项目负责人。** 负责人回复“按照默认来完成”，选择 1A 完整批准本修订版本，已测联合候选 f37b8f4。 本次评审把 ADR-011/012 的 P0 决定落实到第一版工程入口。P1 生产模块沿用同一套契约、Session 和写入方。

| 接口 | v1 决定 |
|---|---|
| 战场 | 应用层只向 Mission 公开端口提交准备、固定步输入、结束和释放请求；实体引用同时携带 Mission 作用域、索引和 generation。prepare / step_fixed / request_end / finalize / dispose 的生命周期由 MIS-RT 单写入。 |
| 移动速度 | MoveIntent.speed_fraction 在领域中取 0 到 1，规范字节以百万分整数承载，最近值取整、半值远离零。解码逆变换，非法范围拒绝。此精度补齐 ADR-012 已批准的分数先按字段量化原则。 |
| 联网 | 接入先校验协议版本、内容 API 与 ContentHash，再由已鉴权连接映射 actor。输入和编队命令按 scope、tick/序号和授权版本提交，客户端只消费快照与回执。冻结 handshake / receive_input / receive_order / build_snapshot / apply_authoritative_snapshot / query_history / close_connection 的契约面；P6 接入完整传输与模式。 |
| MOD | 内容 API v1 读取 manifest、排序依赖、一次编译并返回不可变定义和内容摘要；通过公开注册入口校验扩展类别及信任来源。纯数据包默认不执行代码。用户脚本、SDK 发布和多人完整流程留至 P6。 |
| 存档 | schema v1 延用 GDD §18.1 的 manifest.json、world.bin、可选 transactions.bin 与 backup/。本阶段 payload 使用 ADR-012 规范 UTF-8 JSON，无压缩；manifest 的校验摘要指向实际 payload 字节。安全点取得快照，跨域状态及去重事实在同一次提交内可见，备份保存上一有效版。先写并验证同卷临时文件，最后原子替换提交标记；故障时按有效校验读取旧/新版本。兼容 v0 的迁移在副本中逐级执行。 |

方法签名以语言无关 SDD 为源，GDScript 参数按各域类型和返回结果实现。新增未来版本、破坏性字段变化或不同的磁盘容器须另行签核。P1 以实际正反例、双端规范字节、原子提交故障和模式隔离验收。当前阶段不宣称通过完整 AT-10。
