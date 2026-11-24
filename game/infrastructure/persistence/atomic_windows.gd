extends RefCounted
## Godot 4.7.2 for Windows deletes existing targets in DirAccess.rename.
## Embed the native adapter so packaged builds need no external scripts.
const R = preload("res://contracts/result.gd")
const PUBLISH := """
$ErrorActionPreference = 'Stop'
function MarkerHash($file) {
    if (![IO.File]::Exists($file)) { return '' }
    $hash = [Security.Cryptography.SHA256]::Create()
    try {
        return [BitConverter]::ToString($hash.ComputeHash([IO.File]::ReadAllBytes($file))).Replace('-', '').ToLowerInvariant()
    } finally { $hash.Dispose() }
}
function FlushFile($name) {
    $io = [IO.File]::Open($name, 'Open', 'ReadWrite', 'Read')
    try { $io.Flush($true) } finally { $io.Dispose() }
}
function Publish($from, $to) {
    FlushFile $from
    if ([IO.File]::Exists($to)) {
        # NullString passes a true null backup filename to ReplaceFileW.
        [IO.File]::Replace($from, $to, [System.Management.Automation.Language.NullString]::Value)
    } else {
        [IO.File]::Move($from, $to)
    }
}
$guard = $null
try {
    try { $guard = [IO.File]::Open([IO.Path]::Combine($cfg.dir,'publish.lock'),'OpenOrCreate','ReadWrite','None') }
    catch [IO.IOException] { exit 81 }
    $marker = [IO.Path]::Combine($cfg.dir,'manifest.json')
    $payload = [IO.Path]::Combine($cfg.dir,'world.bin')
    $backup = [IO.Path]::Combine($cfg.dir,'backup')
    $backupMarker = [IO.Path]::Combine($backup,'manifest.json')
    if ((MarkerHash $marker) -ne $cfg.primary -or (MarkerHash $backupMarker) -ne $cfg.backup) { exit 82 }
    if ($cfg.source -eq 'backup' -and (MarkerHash ([IO.Path]::Combine($backup,'world.bin'))) -ne $cfg.checksum) { exit 82 }
    if ($cfg.source -eq 'primary') {
        if ((MarkerHash $payload) -ne $cfg.checksum) { exit 82 }
        [void][IO.Directory]::CreateDirectory($backup)
        foreach ($name in @('world.bin','manifest.json')) {
            $copy = [IO.Path]::Combine($cfg.stage,'old-'+$name)
            [IO.File]::Copy([IO.Path]::Combine($cfg.dir,$name),$copy)
            Publish $copy ([IO.Path]::Combine($backup,$name))
        }
    }
    if ($cfg.fault -eq 'after_backup') { exit 85 }
    Publish ([IO.Path]::Combine($cfg.stage,'world.bin')) $payload
    if ($cfg.fault -eq 'before_marker') { exit 85 }
    Publish ([IO.Path]::Combine($cfg.stage,'manifest.json')) $marker
    if ($cfg.fault -eq 'after_marker') { exit 85 }
} catch {
    [Console]::Error.WriteLine($_.Exception.Message)
    exit 83
} finally { if ($guard) { $guard.Dispose() } }
exit 0
"""

static func publish(options: Dictionary) -> Dictionary:
	if OS.get_name() != "Windows":
		return R.fail("Unavailable","atomic_replace.platform")
	var encoded := Marshalls.raw_to_base64(JSON.stringify(options).to_utf8_buffer())
	var header := "$cfg=ConvertFrom-Json ([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('%s')))\n" % encoded
	var script := Marshalls.raw_to_base64((header + PUBLISH).to_utf16_buffer())
	var program := OS.get_environment("SystemRoot").path_join("System32/WindowsPowerShell/v1.0/powershell.exe")
	var output := []
	var status := OS.execute(program, ["-NoLogo","-NoProfile","-NonInteractive","-EncodedCommand",script],output,true)
	match status:
		0: return R.ok()
		82: return R.fail("StaleVersion","commit_id")
		81: return R.fail("Unavailable","publish.lock")
		85: return R.fail("Unavailable","fault." + options.fault)
	return R.fail("Unavailable","atomic_replace")
