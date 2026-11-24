"""Import the source game in a clean profile, then exercise the deployed asset pack."""
import argparse
import os
from pathlib import Path
import shutil
import subprocess
import tempfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", required=True, type=Path)
    args = parser.parse_args()
    source = Path(__file__).resolve().parents[3]
    with tempfile.TemporaryDirectory(prefix="recollection-field-") as name:
        tmp = Path(name)
        project = tmp / "game"
        shutil.copytree(source, project, ignore=shutil.ignore_patterns(".godot", "__pycache__"))
        env = dict(os.environ, APPDATA=name, LOCALAPPDATA=name)
        for action, marker in [(["--editor", "--import"], None),
                               (["--script", "res://tests/p2/field_assets/run.gd"], "P2-FIELD-ASSETS PASS")]:
            run = subprocess.run([args.godot, "--headless", "--path", project, "--log-file",
                                  tmp / "engine.log", *action], cwd=project, env=env,
                                 capture_output=True, text=True, encoding="utf8", errors="replace", timeout=120)
            output = run.stdout + run.stderr
            print("Godot", *action, "exit", run.returncode)
            for line in output.splitlines():
                if any(s in line for s in ("Godot Engine", "FIELD_", "P2-FIELD", "ERROR", "FAIL")):
                    print(line)
            if run.returncode or "ERROR:" in output or (marker and marker not in output):
                return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
