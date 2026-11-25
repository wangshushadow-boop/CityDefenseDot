extends "res://tests/p2/results/run.gd"
const Composition=preload("res://bootstrap/composition_root.gd")
const Config=preload("res://bootstrap/boot_config.gd")

func run() -> void:
	var loader:=Composition.new(root)
	var config:=Config.resolve([],DisplayServer.get_name(),{})
	if not require(loader.boot(config.value),"real P2 composition"):
		quit(1);return
	var opts:=F.options("field-boot-recovery")
	# Materialize a bona fide Results checkpoint matching the installed content.
	opts.content=loader._services.content
	durable=Store.new()
	core=Core.new("1234567890abcdef")
	engine=Adapter.new(root,true)
	var writer:=F.App.new(durable,func():return F.Camp.new(),fresh,F.authorize)
	if not require(writer.start_session("sandbox",opts),"new save") or not await start_field(battle("campaign"),100,writer):
		quit(1);return
	require(writer.step_fixed(1,[]),"begin field")
	require(rules.request_withdrawal(0,login),"first side withdraws")
	require(rules.request_withdrawal(2,login),"other side withdraws")
	require(writer.step_fixed(2,[]),"authoritative RULES")
	require(writer.finish_mission(rules.view().outcome),"persist real RESULTS")
	require(writer.close_session(),"drop writer")
	require(loader.load_world(opts.slot),"load via real desktop BOOT entry")
	var preview:=loader.pending_result()
	check(preview.ok and not loader.has_campaign_settlement(),"saved result remains readable before rule installation")
	var launcher: Control=load("res://bootstrap/desktop.gd").new()
	root.add_child(launcher)
	launcher.mount(loader)
	check(launcher._buttons.resume.visible and launcher._buttons.resume.disabled and launcher._status.text.contains("战役结算规则"),"launcher describes pending rule")
	launcher.free()
	var marker: Variant=durable.recover(opts.slot).value.manifest.commit_id
	check(not loader.resume_result().ok and durable.recover(opts.slot).value.manifest.commit_id==marker,"missing rule preserves checkpoint")
	require(loader.shutdown(),"release read-only save")
	var credited: Array=[]
	var award:=func(_spec,_result):
		credited.append(1)
		return R.ok([F.line("pool","purse",7)])
	var installed:=Composition.new(root,award)
	require(installed.boot(config.value),"boot with installed campaign rule")
	require(installed.load_world(opts.slot),"reopen verified checkpoint")
	check(installed.has_campaign_settlement() and installed.resume_result().ok and installed.session().query().value.state=="CampaignMap","installed rule resumes genuine result")
	check(credited.size()==1 and not installed.pending_result().ok,"one settlement")
	require(installed.shutdown(),"release recovered campaign")
	print("BOOT_RECOVERY checks=",checks," failures=",failed)
	quit(1 if failed else 0)
