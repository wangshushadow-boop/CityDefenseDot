"""Run P1 suites through their real Godot entry points and retain per-suite evidence."""
import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
import time

GAME = Path(__file__).resolve().parents[3]
PASS = re.compile(r"^(?:PASS\b|[\w./-]+ PASS\b)", re.MULTILINE)
FAIL = re.compile(r"^(?:FAIL\b|[\w./-]+ FAIL\b)", re.MULTILINE)


def run_suite(godot, game, suite, seed, timeout):
    started = time.monotonic()
    result = {"suite": suite, "seed": seed, "status": "NOT_RUN", "exit_code": None}
    entry = game / "tests" / "p1" / suite / "run.gd"
    if not re.fullmatch(r"[a-z][a-z0-9_-]*", suite) or not entry.is_file():
        return result | {"reason": "suite entry missing"}
    with tempfile.TemporaryDirectory(prefix="recollection-suite-") as scratch:
        env = os.environ | {"APPDATA": scratch, "LOCALAPPDATA": scratch,
                            "XDG_DATA_HOME": scratch, "XDG_CONFIG_HOME": scratch,
                            "XDG_CACHE_HOME": scratch}
        cmd = [godot, "--headless", "--log-file", str(Path(scratch) / "godot.log"),
               "--path", str(game), "--script", "res://tests/p1/" + suite + "/run.gd",
               "--", "--seed", str(seed)]
        try:
            proc = subprocess.run(cmd, env=env, capture_output=True, timeout=timeout)
        except (OSError, subprocess.TimeoutExpired) as error:
            return result | {"reason": str(error), "status": "FAIL"}
        log = (proc.stdout + proc.stderr).decode("utf-8", "replace").replace("\r", "").strip()
        ok = proc.returncode == 0 and PASS.search(log) and not FAIL.search(log)
        ok = ok and "ERROR:" not in log and "SCRIPT ERROR" not in log
        return result | {"status": "PASS" if ok else "FAIL", "exit_code": proc.returncode,
                         "seconds": round(time.monotonic() - started, 3), "output": log}


def self_test(godot):
    with tempfile.TemporaryDirectory(prefix="recollection-harness-") as scratch:
        base = Path(scratch)
        (base / "project.godot").write_text('config_version=5\n[application]\nconfig/name="harness"\n')
        actual = []
        for name, body in {"success": 'print("CASE PASS")\n\tquit(0)',
                           "broken": 'print("CASE FAIL")\n\tquit(1)',
                           "unmarked": 'print("no case result")\n\tquit(0)'}.items():
            destination = base / "tests/p1" / name / "run.gd"
            destination.parent.mkdir(parents=True)
            destination.write_text("extends SceneTree\nfunc _initialize():\n\t" + body + "\n")
            actual.append(run_suite(godot, base, name, 241124, 15))
        actual.append(run_suite(godot, base, "missing", 241124, 15))
        print(json.dumps(actual, ensure_ascii=False, indent=2))
        return 0 if [r["status"] for r in actual] == ["PASS", "FAIL", "FAIL", "NOT_RUN"] else 1


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", required=True)
    parser.add_argument("--game", type=Path, default=GAME)
    parser.add_argument("--suite", action="append", help="suite directory; repeat to select multiple")
    parser.add_argument("--seed", type=int, default=241124)
    parser.add_argument("--timeout", type=int, default=120)
    parser.add_argument("--build", default="working-tree")
    parser.add_argument("--evidence", type=Path)
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        return self_test(args.godot)
    game = args.game.resolve()
    suites = args.suite or sorted(p.parent.name for p in (game / "tests/p1").glob("*/run.gd"))
    rows = [run_suite(args.godot, game, name, args.seed, args.timeout) for name in suites]
    evidence = {"build": args.build, "seed": args.seed, "results": rows}
    if args.evidence:
        args.evidence.parent.mkdir(parents=True, exist_ok=True)
        args.evidence.write_text(json.dumps(evidence, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    for row in rows:
        print(row["suite"], row["status"], "exit", row["exit_code"])
        if row["status"] != "PASS":
            print(row.get("reason", row.get("output", "")))
    return 0 if rows and all(row["status"] == "PASS" for row in rows) else 1


if __name__ == "__main__":
    raise SystemExit(main())
