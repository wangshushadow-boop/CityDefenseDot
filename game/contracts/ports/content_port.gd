@abstract
extends RefCounted
## BOOT and tools compile data packs through this port. INF-CONTENT owns all registry writes.
const VERSION := 1
const Result = preload("res://contracts/result.gd")


@abstract func scan_packages(paths: Array) -> Array
@abstract func resolve_packages(selection: Array, game_api: int) -> Dictionary
@abstract func compile(order: Array, overrides: Dictionary) -> Dictionary
@abstract func validate_package(package: Dictionary) -> Dictionary
@abstract func check_save_or_network_compatibility(manifest: Dictionary, compiled: Dictionary) -> Dictionary


## The host supplies the trust decision independently of metadata in the package.
func register_extension(key: String, implementation: Variant, trust: bool) -> Dictionary:
	if not trust:
		return Result.fail("Unauthorized", "trust")
	if key.strip_edges().is_empty() or implementation == null:
		return Result.fail("InvalidArgument", "extension")
	return _register_trusted_extension(key, implementation)


@abstract func _register_trusted_extension(key: String, implementation: Variant) -> Dictionary
