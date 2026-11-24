"""Exercise the normal Windows client after first-run audio/graphics initialization."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

sys.path.insert(0, str(Path(__file__).resolve().parents[4] / "ci"))
from build import boot_record


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", type=Path, required=True)
    inputs = parser.add_mutually_exclusive_group(required=True)
    inputs.add_argument("--project", type=Path)
    inputs.add_argument("--pack", type=Path)
    parser.add_argument("--trials", type=int, default=12)
    parser.add_argument("--evidence", type=Path, required=True)
    args = parser.parse_args()
    if args.trials < 1:
        parser.error("trials must be positive")
    source = ["--path", args.project.resolve()] if args.project else ["--main-pack", args.pack.resolve()]
    results = []
    for trial in range(1, args.trials + 1):
        with tempfile.TemporaryDirectory(prefix="recollection-cold-client-") as scratch:
            directory = Path(scratch)
            env = os.environ.copy()
            for key in ("APPDATA", "LOCALAPPDATA", "XDG_CONFIG_HOME", "XDG_DATA_HOME", "XDG_CACHE_HOME"):
                isolated = directory / key
                isolated.mkdir()
                env[key] = str(isolated)
            command = [args.godot.resolve(), "--windowed", "--resolution", "800x500", "--log-file",
                       directory / "godot.log", *source, "--", "--profile=client", "--p1-smoke"]
            try:
                run = subprocess.run(command, cwd=directory, env=env, capture_output=True, timeout=60)
                output = (run.stdout + run.stderr).decode("utf-8", "replace")
                row = {"trial": trial, "exit": run.returncode, "output": output}
                try:
                    row["boot"] = boot_record(output, "client")
                    row["pass"] = run.returncode == 0 and "SCRIPT ERROR" not in output and "ERROR:" not in output
                except ValueError:
                    row["pass"] = False
            except subprocess.TimeoutExpired:
                row = {"trial": trial, "exit": 124, "pass": False, "output": "timeout after 60 seconds"}
            results.append(row)
    args.evidence.parent.mkdir(parents=True, exist_ok=True)
    args.evidence.write_text(json.dumps(results, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"Windows client cold starts {sum(r['pass'] for r in results)}/{args.trials}")
    return 0 if all(row["pass"] for row in results) else 1


if __name__ == "__main__":
    sys.exit(main())
