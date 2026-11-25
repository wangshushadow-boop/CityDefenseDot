extends RefCounted

# Battle terminology shared by the controls and their command receipts.
const WORDS := {
	"deployment":["野战 · 部署","Field deployment"], "battle":["野战 · 指挥","Field command"],
	"ended":["战果","Battle result"], "select":["选择编队","Formations"],
	"layout":["阵型","Formation"], "zone":["部署区","Deployment zone"], "target":["目标","Target"],
	"pick":["选择…","Choose…"], "mark":["预览部署","Place units"], "reset":["重置部署","Reset plan"],
	"deploy":["开战","Begin battle"], "hold":["坚守","Hold"], "charge":["冲锋","Charge"],
	"move":["移动","Move"], "set_layout":["变阵","Apply layout"], "delegate":["委派","Delegate"],
	"withdraw":["本方撤退","Withdraw our side"], "confirm":["确认撤退","Confirm withdrawal"],
	"cancel":["取消","Cancel"], "spectate":["观战","Spectate"], "leave":["返回","Return"],
	"line":["横列","Line"], "shield_wall":["盾墙","Shield wall"], "loose":["散阵","Loose"],
	"square":["方阵","Square"], "circle":["圆阵","Circle"], "wedge":["楔形","Wedge"], "column":["纵队","Column"],
	"ready":["在场","Ready"], "reserve":["预备","Reserve"], "routed":["溃逃","Routed"],
	"own":["本方","Own"], "other":["对方","Opposing"], "withdrawn":["已撤退","Withdrawn"],
	"hp":["体力","Health"], "ammo":["弹药","Ammo"], "morale":["士气","Morale"],
	"direction":["攻向","Direction"], "up":["上","Up"], "right":["右","Right"],
	"left":["左","Left"], "down":["下","Down"], "downed":["主将倒地","Commander down"],
	"settings":["显示设置","Display settings"], "large":["大字号","Larger type"],
	"contrast":["高对比","High contrast"], "captions":["字幕","Captions"], "rebind":["修改坚守键","Rebind hold"],
	"key":["请按新按键（Esc 取消）","Press a new key (Esc cancels)"], "language":["English","中文"],
	"controller":["返回战场控制 · F6","Resume field controls · F6"], "accepted":["已提交","Submitted"],
	"queued":["已排队","Queued"], "active":["执行中","Active"], "completed":["完成","Complete"],
	"denied":["拒绝","Denied"], "failed":["失败","Failed"], "cancelled":["已取消","Cancelled"],
	"victory":["获胜","Victory"], "defeat":["失利","Defeat"], "draw":["平局","Draw"],
	"winners":["胜方","Winners"], "slots":["兵员结局","Roster outcomes"],
	"fallen":["阵亡","Fallen"], "wounded":["负伤","Wounded"], "survived":["存活","Survived"],
	"killed":["阵亡","Killed"], "captured":["被俘","Captured"], "survivor":["生还","Survivor"],
	"authority":["可指挥","Controllable"], "readonly":["仅查看","View only"], "objective":["目标","Objective"],
	"point":["目标点（米）","Target point (m)"], "preview":["部署预览","Deployment preview"],
	"Unavailable":["暂时不可用","Unavailable"], "Unauthorized":["无指挥权限","Unauthorized"],
	"StaleVersion":["画面已过期","View expired"], "Conflict":["命令冲突","Conflict"],
	"InvalidArgument":["参数无效","Invalid argument"], "InvalidState":["当前不可操作","Unavailable in this state"],
	"NotFound":["找不到目标","Target missing"], "NoRoute":["无法到达","Unreachable"],
	"confirm_hint":["撤出本方所有剩余兵力？","Withdraw all remaining troops on your side?"],
	"orders":["命令","Orders"], "casualties":["伤亡","Casualties"],
	"Pending":["待处理","Pending"], "Accepted":["已受理","Accepted"], "Executing":["执行中","Executing"],
	"Completed":["完成","Complete"], "Failed":["失败","Failed"], "Active":["执行中","Active"],
	"Replaced":["已替换","Replaced"], "player_priority":["主将命令优先","Commander takes priority"],
	"control_revoked":["权限已变更","Control revoked"], "superseded":["命令已替换","Order replaced"],
	"expired":["已过期","Expired"], "unreachable":["无法到达","Unreachable"], "invalid_target":["目标无效","Invalid target"],
	"not_spawned":["未上场","Not deployed"], "alive":["生还","Alive"], "dead":["阵亡","Dead"], "escaped":["脱离","Escaped"],
	"direct":["直接控制","Direct control"]
}

static func word(key: Variant, language: String) -> String:
	var name := str(key)
	return WORDS[name][int(language == "en")] if WORDS.has(name) else name
