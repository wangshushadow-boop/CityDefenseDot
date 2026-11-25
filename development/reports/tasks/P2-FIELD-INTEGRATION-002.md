# P2-FIELD-INTEGRATION-002 野战会话及授权分派

开发候选，基线 5b60654。已按独立审查修订首次候选 ab8f8a9。开发者 engine_field，隔离工作树 .worktrees/p2-field-session，模块 APP。覆盖 BAT-03、BAI-06、NET-06、SAV-02 在会话入口的切片。

## 接入

game/application/game_session.gd 为现有 GameSession 的构造函数增加可选第七参数 field_gateway(operation, payload, context)。会话将上下文交给 BOOT 注入的身份解析器与当前 Mission 网关。野战 HUD、视觉、镜头和输入从 query("field", visibility) 读取。已认证的输入、编队命令、部署和撤退等通过 dispatch 进入。服务器用空输入的 step_fixed 推进。作用域释放后清空野战回执，战役存档继续使用原有结构。

game/application/field_commands.gd 在命令进入前检查 v1 数据。APP 接受 v1 原生整数或浮点速度比例；网络入口先用 S.decode_value 解码百万分整数，APP 使用 S.encode_value 生成规范回执摘要。编队修订支持本机整数键和规范的十进制字符串键。权限凭据单独传入。game/application/receipt_book.gd 复用既有回执构造，并为活动 Mission 的成功命令逐条登记。

第一次结束野战前，Session 读取 Mission 已经提交的 field.rules 目标阶段报告，比对完整决定。保存失败重试可提交同一决定或完整结果，冷载后可直接调用 route_result() 续办当前待结算结果。它只读取已验证的持久化结果。冷载与结算复用 RESULTS 的覆盖校验，保留队伍编号的原始类型、自定义及赛局路由。

## 运行验证

Windows，Godot 4.7.2.stable.official.ed1daf0bf Standard，固定种子 1234567890abcdef。游戏测试从工作树执行 `Godot_v4.7.2-stable_win64_console.exe --headless --path game --log-file <工作树绝对日志路径> --script res://tests/<入口>/run.gd`。实际日志位于 out/field-session。

| 入口 | 退出 | 结果 |
|---|---:|---|
| p2/field_session | 0 | 89 个主进程检查，0 失败；另起三个独立 Godot 进程，分别有 21、10、7 个检查，均退出 0。真实 GameSession、Mission、Jolt、FORM、RULES、RESULTS 和持久化。检查四种查询、身份/作用域/修订拒绝、分数与修订映射、原回执重放、服务器对直接输入的拒绝、三方撤退、伪造赢家、落盘失败、冷载及跨新 Mission 重放。 |
| p1/application | 0 | T-APP-01 / AT-10 切片、T-APP-02、T-APP-03、T-APP-04 切片均通过。 |
| p2/results | 0 | 147 个断言，0 失败，1000 个来源、3 种路由与真实碰撞。 |
| p2/input | 0 | 379 检查，0 失败，实际手柄连接数 0。 |
| p1/mission | 0 | 50 次切换，重放摘要一致。 |
| python ci/gates.py dependencies | 0 | 静态依赖问题 0。 |

game/tests/p2/field_session/run.gd 使用测试装配注入不透明凭据、实际领域命令和输入队列。正式 BOOT 适配、全场输入驱动、网络传输、真实手柄和完整 T-TEST-01–04、AT-04/05 留给各自执行任务。本次变更仅在任务白名单内，git diff --check 退出 0。独立审查和集成由主 Agent 记录。

首次独立审查要求修复三个问题。新增 cold.gd 跨进程重现写入、结算和再次载入。中间进程只接收存档目录、槽和安装内容，路由两次仅转移 7 铜钱一次，存档修订加一，清除预留与待结算记录。原生 Int(1) 验证为满速；线上的 Int(625000) 经 v1 解码为 0.625，再进入会话。已缓存的编队指令先调用 field.check_order 复验实时持有者和原授权修订；正常丢失回执、撤权及重新授予三种情况均经实际 FORM 验证。
