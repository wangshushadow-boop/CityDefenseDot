# P1 独立验证记录

测试使用 ADR-011 指定的 Godot 4.7.2 Standard、Python 3.12.14。下文记录正式用例、有限切片、失败修复与未执行范围，最终从集成提交复跑。

契约 codec 的独立 Python/Godot 探针已比对 13,384 份输入。使用 Python Unicode 15.0.0 为 NFC 参考，覆盖分解/组合属性、Hangul、组合附加符、首尾/连续 NUL、重复键和异常数值，结果与预期一致，退出 0。正式候选及套件结果随后登记。

38 个独立 shape/兼容性断言已通过。独立端口入口输出 T-CON-02 和 P1-PORTS-V1，退出 0。CON-001 首次运行退出 1，T-CON-01 的来源覆盖、重复、旧预留与原输入检查失败。作者定位到自测创建的摘要键为 StringName；修正结果须重跑验证。加入畸形 UTF-8、BOM 和原始 NUL 后，差分样本增至 13,390 项，0 差异。

## 第一批合并态复验

联合候选 `f37b8f4`：独立 13,390 样本零差异，46/46 形状断言通过。Godot T-CON-01/02/03、P1-CON-BOUNDARY 和 P1-PORTS-V1 均通过；第二套 oracle 的 34,155 个 NFC 样本和 14 组规范字节向量通过。另一个审查入口覆盖 24 种 schema，双向 24/24 通过。主 Agent 从同一个合并态 game/ 复跑全部入口退出 0。首轮失败与未运行项见[QA 复测明细](contracts/README.md)、[合并态原始输出](contract-candidate.txt)和[双向摘要](contract-oracle.txt)。

CORE 首轮三次独立进程重放的 SHA-256 均为 35230c81dc693bc55bfe1acd788d4f120e5f2c707df773421f612d938b5f2171。DEF 独立确认 DAG 合流、循环路径、顺序无关的索引、只读视图等 19 项通过；加入布尔值冒充 troop.role 后 20 项有 1 项失败，退出 1，保留此回归记录。

修订 CORE 在三次独立进程重复通过 76/76 断言；1 与 3 个 worker 结果相同，最终重放摘要 ef175296753b220567b00855d3cf0cfffe3e0308de4b842d37c9184442705f15。已回归跨运行时令牌、缺戳、分数 tick/revision、及已缓存 RNG 在恢复后的身份。DEF 修订独立通过 22/22 类型和引用断言。

## 基础适配与规则

独立 QA 在隔离目录运行真实入口及额外探针。引擎修正后 10/10，包括起点重叠立即命中及连续长距离球扫；50 次资源加载/释放的 QA P95 为 4,094 µs。SHRULE 53/53；库存小数金额与修订号拒绝，幂等及持久回调原子性通过。内容校验拒绝负人数和可变 NUL 配置，实际无源 PCK 可重载。遥测恶意嵌套 code 不再进入日志。框架用种子 917 两次得到相同输出，换为 918 并选缺失入口时总退出 1，证据分别为 PASS 与 NOT_RUN。

PERSIST 的独立故障测试开启 25 个 Godot 子进程，另起两个写者以相同旧版本提交，只有其中一个成功，第三个进程读到唯一胜方的奖励及回执。此处验证进程中止/指定故障点；未进行物理拔电和真实满盘实验。

最终库存与持久层经二次独立 QA。513 笔跨页历史的 18 条断言及已损坏索引/未来版本对照的 12 条实盘断言全部通过。[跨页输出](qa-archive.txt) · [索引恢复输出](qa-marker_recovery.txt) · [持久层合并态输出](persistence.txt)。

Mission 的同一已记录权威实例在实际 Windows 与 headless 重放，摘要 24427810fe1ace3d1cdfb22fbb42cdca7b98ec8eee7bc7a362dde96fd9677373，各完成 50 次带在途 worker 的任务切换，节点回到 1。CAMP 通过 T-CAMP-01/03，另以 20 个种子各十天核对短期账本及暂停恢复；完整多年经济政治条件仍由后续阶段验收。

## 会话、故障恢复与资源释放

APP 候选的 48 项独立鉴权、幂等、失败恢复断言通过。65,537 项的 APP 规范回执可恢复；独立 QA 从合规的旧 v1 存档实际写入第 65,537 个关键赛果，17 页逐条校验、冷读、最早回执重发与旧版备份通过。[APP 独立输出](qa-application.txt) · [长档实盘](qa-persist-pages.txt)

c6981d3 的 Session 跨模块实测满足 T-TEST-03 的结算故障判据：写前、写中、标记前及标记后中止，再用新进程重发，同一奖励只有一笔。T-PERSIST-04 的完整 50 次 Mission 切换、保存、重载通过，关闭后节点、对象、资源和引擎租约回到预热基线。结算夹具注入结果与奖励规则，完整 AT-10 保留 NOT_RUN。[逐次指标、历史失败与断点记录](session/README.md)

## 启动回归

普通 Windows 客户端的按钮走生产 Session，完成新建、保存、训练、退出及重新读盘；普通 headless 进程持续运行到第 15 个固定步，未创建 Control，随后逆序释放服务。早期 BOOT 候选在缺少必需 battle_limit 时进入训练后才抛出脚本错误。修订后在 content 装配阶段返回具体字段、清理已创建服务，预期退出 1。注册环可在构造 Session 前检出；清理遇到可重试错误时，业务入口保持关闭。[双端对照脚本](boot_profiles.py) · [普通菜单实测](qa-boot-desktop.txt)

## 最终构建与启动

在运行时集成提交 b4c36e1 上执行 `python ci/build.py --godot <Godot-console> --out out/p1-build`，退出 0。先从 Git 归档运行 2 组 Python 门禁测例和 15 套真实 Godot 模块入口，再导出客户端与专服 PCK、基础内容 ZIP。在无源码目录以 RTX 3090 Windows 客户端及 headless 各推进 3 tick，协议 1、内容摘要和状态摘要均一致。真实数据工具从解压的外置 ZIP 编译得到相同的内容摘要。主 Agent 另独立核算 4 个文件的大小与 SHA-256，并逐字节将基础 ZIP 对照 Git 源文件。三次从同一候选 565c32e 重建，client.pck、server.pck、base.zip 三件分别字节一致，运行耗时单独留在测试记录。[构建清单](build-manifest.json) · [逐套结果](domain-tests.json) · [独立冷启动](delivery-profiles.txt) · [同提交复建](build-repro.json)

独立 CI 运行 25 个正反场景。缺失的完整 MUST/AT 凭证使 release 命令预期返回 1，候选报告 293 条诊断；每条诊断可以是一个需求或一个关联用例。T-CI-04 未进行同硬件正式战场性能回退演练。本机对 P1 完整工程的独立 Windows EXE 发布导出同样返回 1，找不到匹配的 Windows 模板。[门禁结果](ci.txt) · [原生导出](native-export.txt) · [独立 QA 汇总](qa-ci-summary.json)

主 Agent 另按 UTF-8 控制台重放 13,390 个参照样本、46 项形状断言及 34,155 个 NFC 样本，全部通过。之前未启用 UTF-8 的一次调用因系统 GBK 无法打印预期的无效输入诊断而退出 1。[完整输出](contracts-final.txt)
