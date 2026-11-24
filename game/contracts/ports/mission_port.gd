@abstract
extends RefCounted
## APP operates the mission through pure data. MIS-RT owns scope, tick and entity generations.
const VERSION := 1


@abstract func prepare(spec: Dictionary, scene: Dictionary, ruleset: Dictionary) -> Dictionary
@abstract func step_fixed(tick: int, inputs: Array) -> Dictionary
@abstract func request_end(outcome: Dictionary) -> Dictionary
@abstract func finalize() -> Dictionary
@abstract func dispose() -> Dictionary
