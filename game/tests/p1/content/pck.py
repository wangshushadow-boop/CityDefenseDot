"""Export the P1 base data to a PCK and exercise it after the source copy is gone."""
import argparse
import hashlib
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

GAME = Path(__file__).resolve().parents[3]
PRESET = """[preset.0]
name="Content"
platform="Windows Desktop"
runnable=true
export_filter="all_resources"
include_filter="*.json"
exclude_filter="*.md,*.py"
script_export_mode=0
[preset.0.options]
binary_format/architecture="x86_64"
"""


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", required=True)
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix="p1-content-") as temp:
        tmp = Path(temp)
        env = os.environ | {"APPDATA": temp, "LOCALAPPDATA": temp}
        isolated = tmp / "only-pack"
        isolated.mkdir()
        pack = isolated / "content.pck"

        def run(arguments, cwd):
            command = [args.godot, "--headless", "--log-file", str(tmp / "godot.log"), *map(str, arguments)]
            result = subprocess.run(command, cwd=cwd, env=env, capture_output=True, timeout=90)
            output = (result.stdout + result.stderr).decode("utf8", "replace")
            print(" ".join(map(str, arguments)), "exit", result.returncode)
            if result.returncode or "ERROR:" in output or "SCRIPT ERROR" in output:
                print(output)
                raise SystemExit(result.returncode or 1)
            return output

        with tempfile.TemporaryDirectory(dir=tmp) as source:
            src = Path(source)
            for name in ("contracts", "shared/definitions", "infrastructure/content", "tests/p1/content"):
                shutil.copytree(GAME / name, src / name)
            (src / "project.godot").write_text("config_version=5\n", encoding="utf8")
            (src / "export_presets.cfg").write_text(PRESET, encoding="utf8")
            run(["--editor", "--path", src, "--import"], src)
            run(["--path", src, "--export-pack", "Content", pack], src)
        output = run(["--main-pack", pack, "--script", "res://tests/p1/content/run.gd"], isolated)
        print(output)
        if "P1-CONTENT errors=0" not in output:
            raise SystemExit("PCK suite did not complete")
        print("P1-CONTENT-PCK PASS", pack.stat().st_size, hashlib.sha256(pack.read_bytes()).hexdigest())


if __name__ == "__main__":
    main()
