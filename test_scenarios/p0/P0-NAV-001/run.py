"""Run the Godot dynamic-link and moving-crowd experiment."""
import argparse
import json
import os
import subprocess
import tempfile
from pathlib import Path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", required=True, type=Path)
    parser.add_argument("--output", type=Path, help="also save the measured JSON")
    args = parser.parse_args()
    project = Path(__file__).resolve().parent
    with tempfile.TemporaryDirectory(prefix="p0-nav-") as directory:
        command = [str(args.godot.resolve()), "--headless", "--log-file",
                   str(Path(directory) / "godot.log"), "--path", str(project),
                   "--script", "gate.gd"]
        environment = {**os.environ, "APPDATA": directory, "XDG_DATA_HOME": directory}
        result = subprocess.run(command, env=environment, capture_output=True, text=True,
                                encoding="utf-8", errors="replace", timeout=120)
    print(result.stdout, end="")
    print(result.stderr, end="")
    lines = [line.removeprefix("NAV_RESULT ") for line in result.stdout.splitlines()
             if line.startswith("NAV_RESULT ")]
    if len(lines) != 1 or "ERROR:" in (result.stdout + result.stderr):
        return result.returncode or 1
    evidence = json.loads(lines[0])
    if args.output:
        args.output.write_text(json.dumps(evidence, indent=2) + "\n", encoding="utf-8")
    return result.returncode or (0 if evidence["passed"] else 1)


if __name__ == "__main__":
    raise SystemExit(main())
