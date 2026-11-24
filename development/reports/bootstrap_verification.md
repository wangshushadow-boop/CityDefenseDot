# recollection 0.3 交付核查

核查日期：2026-11-24。范围：本次交付的设计、目录、配置和研发计划，非游戏功能测试。

| 检查 | 结果 |
|---|---|
| 原用户上传 GDD 及上一版 ZIP 中 GDD | 字节级相同，历史原件 SHA-256 `04c00274a2465d24ee71ae492810cdcd02dca99279143027c566eb37d5b90e54` |
| 当前 GDD 1.1 | 仅更名、根目录名及版本标记变更，SHA-256 `421296a4fce6344a8a403a92d3a71619e20756fe50968504e0c6bf000bee672a` |
| 57 份原 SDD | 对照上一版逐一验证，只有项目名称替换，其他正文一致 |
| 93 需求、208 测试、17 AT | 原 CSV 与验收矩阵字节级一致，全部初始状态保持 |
| 代码目录 | 96 个导航 README 与注册表一一对应 |
| 任务图 | 88 个工作包 + 9 阶段门禁，无环；首个 P0 执行任务已登记，尚未执行 |
| Codex 配置 | 6 个自定义角色 TOML 与全局配置语法解析通过；实际客户端加载待 P0 验证 |
| 文件范围检查器 | 临时 Git 仓库正反用例实际通过：授权路径返回 0，越权路径返回 1 |

## 实际运行：`python3 development/check_project.py --ready P0`

```text
PASS: 57 canonical SDDs, 96 directory mappings, 39 navigation/alias entries
PASS: 93 requirement rows, 208 test rows, 815 local Markdown link occurrences
PASS: source baseline SHA-256 and registry/trace consistency
Documentation checks only; no game implementation or test execution verified.
PASS: 96 code navigation directories; 57 owner boundaries; original archive integrity
PASS: 97 graph nodes (88 work packages + 9 gates), acyclic, 1 registered execution tasks
PASS: module/requirement/test references, state records, 6 custom role TOML files parse
Structure checks only. Codex runtime, game code, real tests and performance NOT verified by this script.
Planning candidates for P0; authorized stage = NONE.
  P0-ENV: 检查工具、硬件、权限与项目基线 (PACKAGE)
Refine execution tasks, check actual permissions and obtain authorization before starting.
```

## 实际运行：临时 Git 仓库的提交 diff 检查

```text
PASS: 1 changed paths, 0 outside authorization. Committed diff only.
DENIED: 'game/mission/ai/individual/b.txt'
FAIL: 2 changed paths, 1 outside authorization. Committed diff only.
```

脚本只检验文档和计划结构、提交路径；不证明业务正确或实际客户端支持。所有游戏测试 NOT_RUN，技术选型 UNDECIDED，项目尚未启动 Codex 或实现游戏。后续依据 P0 真实实验和负责人审批执行。
