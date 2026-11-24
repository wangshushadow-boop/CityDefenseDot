"""Verify the Windows publisher in a PCK-only game, including special characters in the save path."""
import argparse
import os
from pathlib import Path
import subprocess
import tempfile

PACKER = """extends SceneTree
func _initialize():
	var args=OS.get_cmdline_user_args()
	var pack=PCKPacker.new()
	assert(pack.pck_start(args[0])==OK)
	assert(pack.add_file("res://project.godot",ProjectSettings.globalize_path("res://project.godot"))==OK)
	for item in args.slice(2):
		assert(pack.add_file("res://"+item,args[1].path_join(item))==OK)
	assert(pack.flush()==OK)
	quit()
"""


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--godot", required=True)
    parser.add_argument("--path", default="game", type=Path)
    args = parser.parse_args()
    game = args.path.resolve()
    files = ["tests/p1/persistence/worker.gd"]
    for folder in ["contracts", "infrastructure/persistence"]:
        files.extend(p.relative_to(game).as_posix() for p in (game / folder).rglob("*.gd"))
    with tempfile.TemporaryDirectory() as temp:
        isolated = Path(temp)
        builder = isolated / "packer"
        builder.mkdir()
        (builder / "project.godot").write_text("config_version=5\n", encoding="utf8")
        (builder / "pack.gd").write_text(PACKER, encoding="utf8")
        env = os.environ | {"APPDATA": temp, "LOCALAPPDATA": temp}

        def run(parts, expected=None):
            result = subprocess.run([args.godot, "--headless", *parts], cwd=isolated, env=env,
                                    capture_output=True, timeout=30)
            output = (result.stdout + result.stderr).decode("utf8", errors="replace")
            if result.returncode or "ERROR:" in output or (expected and expected not in output):
                raise SystemExit(output)

        pack = str(isolated / "game.pck")
        run(["--path", str(builder), "--log-file", str(isolated / "pack.log"), "--script",
             "res://pack.gd", "--", pack, str(game), *files])
        for action in ["seed", "retry", "read"]:
            run(["--main-pack", pack, "--log-file", str(isolated / "game.log"), "--script",
                 "res://tests/p1/persistence/worker.gd", "--", str(isolated / "档 槽 ' one"),
                 "pkg", action, "1"], f"PERSIST_WORKER {action} PASS")
        print("PERSIST_PCK_STANDALONE PASS")


if __name__ == "__main__":
    main()
