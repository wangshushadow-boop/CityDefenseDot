"""Independent P1 Session/mission/saves acceptance in isolated Godot processes."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import threading


HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[4]
CASES = ("before_write", "partial_world", "before_marker", "after_marker", "cycles")


def visible_generation(slot):
    """Select complete generations independently of the GDScript recovery code."""
    for folder in (slot, slot / "backup"):
        manifest_path = folder / "manifest.json"
        if not manifest_path.is_file():
            continue
        manifest = json.loads(manifest_path.read_bytes())
        world = (folder / "world.bin").read_bytes()
        if hashlib.sha256(world).hexdigest() == manifest["checksum"]:
            return "primary" if folder == slot else "backup", manifest, json.loads(world)
    raise AssertionError("No generation has a matching manifest and payload")


def observe(cmd, cwd, env, timeout):
    with subprocess.Popen(cmd, cwd=cwd, env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                          text=True, encoding="utf-8", errors="replace") as child:
        deadline = threading.Timer(timeout, child.kill)
        deadline.start()
        lines = []
        try:
            for line in child.stdout:
                lines.append(line)
                if line.startswith(("SESSION_", "FAIL", "SCRIPT ERROR", "ERROR:")):
                    print(line.rstrip(), flush=True)
            return child.wait(), "".join(lines)
        finally:
            deadline.cancel()


def run_cases(engine, project, work, cases):
    env = dict(os.environ, APPDATA=str(work / "roaming"), LOCALAPPDATA=str(work / "local"))
    for key in ("APPDATA", "LOCALAPPDATA"):
        Path(env[key]).mkdir()
    (work / "slot-data").mkdir()
    for case in cases:
        actions = ("cycles",) if case == "cycles" else ("crash", "retry", "inspect")
        for action in actions:
            label = f"{case}/{action}"
            cmd = [str(engine), "--headless", "--path", str(project),
                   "--log-file", str(work / f"{case}-{action}.log"),
                   "--script", "res://qa_session.gd", "--", str(work / "slot-data"), case, action]
            status, log = observe(cmd, work, env, timeout=1200 if action == "cycles" else 90)
            print(f"PROCESS {label} exit={status}", flush=True)
            if any(marker in log for marker in ("SCRIPT ERROR", "ERROR:", "FAIL ")):
                raise AssertionError(f"{label} reported an error\n{log}")
            if action == "crash":
                # Windows may report successful self termination. Verify the point
                # was reached and that control did not return to the test harness.
                hit = (work / "slot-data" / (case + ".hit")).read_text().strip()
                if hit != case or "SESSION_END" in log:
                    raise AssertionError(f"{label}: crash point was not reached")
            elif status != 0 or f"SESSION_END {action} PASS" not in log:
                raise AssertionError(f"{label} failed\n{log}")
            origin, manifest, payload = visible_generation(work / "slot-data" / case)
            if action == "crash" and origin != ("backup" if case == "before_marker" else "primary"):
                raise AssertionError(f"{label} selected unexpected disk generation {origin}")
            expected = 50 if case == "cycles" else int(action != "crash" or case == "after_marker")
            snapshot = payload["snapshot"]
            inventory = snapshot["campaign"]["inventory"]["state"]
            coin = "currency:base:currency/copper"
            balances = [inventory["counts"][name][coin] for name in ("payer", "reserve")]
            receipts = snapshot["session"]["results"]
            counts = [len(inventory["ledger"]), len(receipts), len(payload["applied_results"])]
            if balances != [100 - expected, 1 + expected] or counts != [expected] * 3:
                raise AssertionError((label, balances, counts, expected))
            if case == "cycles":
                samples = [json.loads(line.split(" ", 1)[1]) for line in log.splitlines()
                           if line.startswith("SESSION_CYCLE ")]
                if [s["cycle"] for s in samples] != list(range(1, 51)):
                    raise AssertionError("incomplete Mission cycles")
                for stat in ("nodes", "orphans", "resources", "objects"):
                    values = [s[stat] for s in samples]
                    print(f"SERIES {stat} first={values[0]} last={values[-1]} "
                          f"range={min(values)}..{max(values)}")
                if any(s["orphans"] or any(s["engine"].values()) for s in samples):
                    raise AssertionError("orphan or outstanding engine scope after Mission exit")
            print(f"DISK {label} source={origin} commit={manifest['commit_id']} "
                  f"sha256={manifest['checksum']} balances={balances} results={len(receipts)}", flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", type=Path, required=True)
    parser.add_argument("--game", type=Path, default=ROOT / "game")
    parser.add_argument("--case", action="append", choices=CASES)
    args = parser.parse_args()
    engine = args.godot.resolve()
    version = subprocess.run([str(engine), "--version"], check=True, capture_output=True, text=True)
    print("ENGINE", version.stdout.strip(), flush=True)
    with tempfile.TemporaryDirectory(prefix="recollection-p1-session-") as tmp:
        work = Path(tmp)
        project = work / "project"
        shutil.copytree(args.game, project, ignore=shutil.ignore_patterns(".godot", "*.tmp"))
        shutil.copy2(HERE / "worker.gd", project / "qa_session.gd")
        for name in ("application/game_session.gd", "application/receipt_book.gd",
                     "infrastructure/persistence/save_service.gd", "tests/p1/application/fixture.gd", "qa_session.gd"):
            normalized = (project / name).read_bytes().replace(b"\r\n", b"\n")
            print(f"SOURCE {name} sha256={hashlib.sha256(normalized).hexdigest()}", flush=True)
        run_cases(engine, project, work, args.case or CASES)
    print("P1_SESSION_INTEGRATION PASS")


if __name__ == "__main__":
    try:
        main()
    except (AssertionError, OSError, subprocess.TimeoutExpired, ValueError) as error:
        print(str(error), file=sys.stderr)
        sys.exit(1)
