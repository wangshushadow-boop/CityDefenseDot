# P1 独立验证记录

测试使用 ADR-011 指定的 Godot 4.7.2 Standard、Python 3.12.14。下文记录正式用例、有限切片、失败修复与未执行范围，最终从集成提交复跑。

契约 codec 的独立 Python/Godot 探针已比对 13,384 份输入。使用 Python Unicode 15.0.0 为 NFC 参考，覆盖分解/组合属性、Hangul、组合附加符、首尾/连续 NUL、重复键和异常数值，结果与预期一致，退出 0。正式候选及套件结果随后登记。

38 个独立 shape/兼容性断言已通过。独立端口入口输出 T-CON-02 和 P1-PORTS-V1，退出 0。CON-001 首次运行退出 1，T-CON-01 的来源覆盖、重复、旧预留与原输入检查失败。作者定位到自测创建的摘要键为 StringName；修正结果须重跑验证。加入畸形 UTF-8、BOM 和原始 NUL 后，差分样本增至 13,390 项，0 差异。

## 第一批合并态复验

联合候选 `f37b8f4`：独立 13,390 样本零差异，46/46 形状断言通过。Godot T-CON-01/02/03、P1-CON-BOUNDARY 和 P1-PORTS-V1 均通过；第二套 oracle 的 34,155 个 NFC 样本和 14 组规范字节向量通过。另一个审查入口覆盖 24 种 schema，双向 24/24 通过。主 Agent 从同一个合并态 game/ 复跑全部入口退出 0。首轮失败与未运行项见[QA 复测明细](contracts/README.md)、[合并态原始输出](contract-candidate.txt)和[双向摘要](contract-oracle.txt)。
