extends Node3D

static func start_mm(i: int) -> Array:
	return [((i%16)-8)*2500,0,(floori(i/16.0)-8)*2200]

func _ready() -> void:
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.15,1.2,0.5)
	for i in 250:
		var origin := start_mm(i)
		var body := StaticBody3D.new()
		body.position = Vector3(origin[0]+1000,0,origin[2])*0.001
		body.set_meta("entity_handle",str(250+i))
		var collision := CollisionShape3D.new()
		collision.shape = shape
		body.add_child(collision)
		add_child(body)
