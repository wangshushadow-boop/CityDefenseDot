extends SceneTree
const Field=preload("res://mission/movement/ports/field_movement.gd")
const Adapter=preload("res://infrastructure/engine/adapter.gd")
const DT:=1.0/30.0
var engine
var errors:=0
func h(i:int)->Dictionary:
	return {"index":i,"generation":1}
func need(yes:bool,msg:String)->void:
	if not yes:
		errors+=1
		printerr("FAIL ",msg)
func _initialize()->void:
	run.call_deferred()
func run()->void:
	engine=Adapter.new(root,true)
	var token=engine.open_scope("qa")
	need(token.ok and engine.load_scene({"id":"base:scene/moving_field","simulation_scene":"res://tests/p2/movement/field.tscn"},token.value).ok,"load")
	for frame in 180:
		await physics_frame
		var receipt:Dictionary=engine.sync_navigation("qa")
		if receipt.value.status == "applied":
			var route:Dictionary=engine.query_path_batch([{"from":[-35000,0,0],"to":[22000,0,0]}],receipt.value.applied_revision,"qa")
			if route.ok and route.value[0].reachable: break
		if frame == 179: need(false,"native mesh readiness")
	pressure()
	crowd(false)
	crowd(true)
	engine.release_scope("qa")
	await process_frame
	print("INDEPENDENT_MOV ", "PASS" if errors==0 else "FAIL", " errors=",errors)
	quit(1 if errors else 0)
func pressure()->void:
	var f=Field.new(engine,"qa")
	var starts:=[]
	var count:=160
	for i in count:
		var profile:="mounted" if i%4==0 else "foot"
		var p:=Vector3(-55+i%20,0,-8.4+floori(i/20.0)*2.0)
		starts.append(p)
		need(f.spawn(h(i),p,profile,Vector3.RIGHT).ok,"spawn")
		need(f.set_corridor(str(i),Vector3(-40,0,0),Vector3(-30+.002*i,0,0),profile).ok,"route")
		need(f.assign(h(i),str(i),p-Vector3(-40,0,0)).ok,"assign")
	var max_queries:=0
	var total:=0
	for tick in 60:
		var r=f.step(tick,DT)
		need(r.ok,"step")
		max_queries=maxi(max_queries,r.value.queried)
		total+=r.value.queried
	var moved_by_type:=[0,0]
	for i in count:
		if f.view(h(i)).value.position.distance_to(starts[i])>.01:
			moved_by_type[1 if i%4==0 else 0]+=1
	print("PRESSURE active=",count," corridors=",total," peak_queries=",max_queries," foot_moved=",moved_by_type[0]," horses_moved=",moved_by_type[1])
	need(total==count and max_queries<=8 and moved_by_type[0]>0 and moved_by_type[1]>0,"bounded distinct routes")
func crowd(bidi:bool)->void:
	var f=Field.new(engine,"qa")
	need(f.set_terrain([{"bounds":AABB(Vector3(-1.1,-1,-.7),Vector3(6.2,2,1.4)),"profiles":["foot"]}]).ok,"terrain")
	f.set_corridor("east",Vector3(-35,0,0),Vector3(22,0,0))
	f.set_corridor("west",Vector3(28,0,0),Vector3(-22,0,0))
	var n:=64
	var last:=PackedVector3Array()
	var t0:=PackedVector3Array()
	for i in n:
		var west:=bidi and i>=n/2
		var j:=i-n/2 if west else i
		var row:=floori(j/3.0)
		var lane:=j%3-1
		var here:=Vector3((10+row*1.1) if west else (-6-row*1.1),0,lane*1.05)
		var dest:=Vector3((-10-row*1.1) if west else (12+row*1.1),0,lane*1.05)
		f.spawn(h(i),here)
		f.assign(h(i),"west" if west else "east",dest-Vector3(-22 if west else 22,0,0))
		last.append(here)
	var arrivals:=0
	var within:=0
	var outside:=0
	var max_step:=0.0
	var ticks:=0
	for tick in 1800:
		need(f.step(tick,DT).ok,"crowd step")
		arrivals=0
		within=0
		for i in n:
			var v:Dictionary=f.view(h(i)).value
			var p:Vector3=v.position
			if v.arrived: arrivals+=1
			if p.x>-.95 and p.x<4.9:
				within+=1
				if absf(p.z)>.422: outside+=1
			max_step=maxf(max_step,p.distance_to(last[i]))
			last[i]=p
		if tick==1499: t0=last.duplicate()
		ticks=tick+1
		if arrivals==n: break
	var unchanged:=0
	if t0.size()==n:
		for i in n:
			if t0[i].distance_to(last[i])<.001: unchanged+=1
	print("CHOKE bidi=",bidi," n=",n," arrived=",arrivals," ticks=",ticks," unchanged_final_300=",unchanged," still_in_gate=",within," outside=",outside," max_step=",max_step)
	need(arrivals==n and outside==0 and max_step<.114,"bottleneck "+str(bidi))
