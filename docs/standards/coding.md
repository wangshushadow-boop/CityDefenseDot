# 编码与架构规范

以 [依赖规则](../architecture/dependency_policy.md)、[公共契约](../architecture/common_contracts.md) 和总体设计 §20 为准。P0 未冻结语言/格式化器；实现不假定 Godot 或 C# 已选。统一命名、强类型 ID/单位、显式可空与 Result；注入时钟和随机流；用纯规则计算与单权威阶段提交。优先组合、模块公开端口、不可变快照，禁止循环依赖、复制状态和重复系统。高频批量调用，避免每实体线程/每 tick 全局事件。日志按 world/mission/tick/ID，去除隐私及凭证。对异常提供清晰语义。提交最小可审查 diff，不混入全局格式化、未经许可的依赖或构建输出。P0 确定具体 lint、格式化和依赖检查器，P1 接入 CI。
