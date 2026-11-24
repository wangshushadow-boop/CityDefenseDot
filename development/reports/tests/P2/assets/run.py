"""Import the selected third-party GLBs without touching their source or the game's content."""
import argparse
import hashlib
import os
from pathlib import Path
import shutil
import subprocess
import tempfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", required=True, type=Path)
    parser.add_argument("--source", required=True, type=Path)
    parser.add_argument("--horse", type=Path, help="Optional Quaternius CC0 Horse GLB")
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix="recollection-p2-art-") as tmp:
        base = Path(tmp)
        project = base / "game"
        project.mkdir()
        (project / "project.godot").write_text("config_version=5\n", encoding="utf8")
        shutil.copyfile(Path(__file__).with_name("inspect.gd"), project / "inspect.gd")
        models = {name: args.source / (name + ".glb") for name in ("general", "spear_soldier", "crossbowman")}
        if args.horse is not None:
            models["horse"] = args.horse
        for name, src in models.items():
            target = project / (name + ".glb")
            shutil.copyfile(src, target)
            print(src.name, target.stat().st_size, hashlib.sha256(target.read_bytes()).hexdigest(), flush=True)
        env = os.environ | {"APPDATA": tmp, "LOCALAPPDATA": tmp}
        for flags in (["--editor", "--import"], ["--script", "res://inspect.gd"]):
            proc = subprocess.run([args.godot, "--headless", "--path", project, "--log-file",
                                   base / "godot.log", *flags], cwd=project, env=env,
                                  capture_output=True, text=True, encoding="utf8", errors="replace", timeout=120)
            log = proc.stdout + proc.stderr
            for line in log.splitlines():
                if "P2_ART" in line or "ERROR:" in line or line.startswith("Godot Engine"):
                    print(line, flush=True)
            print(flags[0], "exit", proc.returncode, flush=True)
            if proc.returncode or "ERROR:" in log or (flags[0] == "--script" and "P2_ART_IMPORT PASS" not in log):
                return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
