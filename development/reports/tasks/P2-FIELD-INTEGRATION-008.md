# P2-FIELD-INTEGRATION-008 · 感知与调度同一步撤销

开发者 ai_tx_dev 在独立工作树 `.worktrees/p2-ai-tx` 基于 `e1c7f95` 实现 BAI 候选。需求 BAI-06，覆盖 T-MIS-RT-02 与 T-TEST-01 的 BAI 固定步切片。任务状态为 CANDIDATE，独立审查和合并态验收由主 Agent 组织。

| 文件 | 变更 |
|---|---|
| game/mission/ai/ports/field_ai.gd | 在原实例上实现 begin_tick、commit_tick、rollback_tick。回滚恢复原 roster token、已接受结果、已发工作和代际。每次试算单独分配工作编号，旧工作不能在重试后消费新授权。 |
| game/mission/ai/perception/field_perception.gd | 保存可变映射和计数器，保留原只读成员行，在首次改动时复制受影响的空间桶和视线缓存。撤销恢复旧成员位置、观察、威胁、生命及侦察游标。 |
| game/mission/ai/scheduler/field_schedule.gd | 撤销到期日修改，再恢复原时钟、日历、紧急事件和调度 tick。 |
| game/tests/p2/ai_transaction/run.gd | 验证原票据身份、迟到票据、已转交的可变返回值、退回代际、重复撤销、回调重入及 scope 释放。另以 1000 人连续 75 步比较正常运行与 18 次失败重试后的工作、可见信息、计数及积压。 |

在本工作树使用 Godot 4.7.2 Standard Windows console，入口命令为 `Godot_v4.7.2-stable_win64_console.exe --headless --path game --script res://tests/p2/<目录>/run.gd`，各进程使用单独临时日志。git diff --check 通过。

| 入口与测试 | 退出码 | 实测证据 |
|---|---:|---|
| ai_transaction | 0 | AI_TRANSACTION checks=29 failures=0；独立重复运行通过。 |
| ai | 0 | FIELD_AI errors=0；T-BAI-01/02 的真实遮挡、T-BAI-04 的延迟工作拒绝以及 500/1000 人 120 步的参考工作量通过。组合耗时 P95 为 6.736 / 14.027 ms，积压为 0。 |
| tactical | 0 | FIELD_TACTICS errors=0，1576 次导航查询、4593 次真实视线查询。 |
| formation_ai | 0 | P2-BAI-F-001 PASS，4877 项断言。 |
| individual，追加 `-- --functional-only` | 0 | P2-BAI-I-001 PASS，910 项检查；1000 人另加 500 匹坐骑的本次夹具耗时 P95 为 29.045 ms。此命令只检查功能。 |

另从既有 ai/run.gd 生成临时脚本，在 mixed_load 计时的 begin_ai 之后调用 begin_tick() 并检查成功，在 ai_cost.append 前调用 commit_tick()。同一真实 Jolt/COM/MOV 负载每步开启 BAI 事务，退出 0。500 / 1000 人各 120 步，决策数分别为 5120 / 10120，物理视线数为 10504 / 20501，最大积压均为 0。BAI P95 为 4.173 / 9.291 ms，组合 P95 为 7.150 / 16.364 ms。这是单轮测量，正式窗口、完整 Mission 及 8 GiB 设备在该任务中均为 NOT_RUN。源码变更限于授权模块，既有公共契约和各 AI 子模块未发生变更。
