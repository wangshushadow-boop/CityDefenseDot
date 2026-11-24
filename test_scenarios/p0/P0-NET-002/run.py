"""Measure synthetic ENet connections against the P0-001 authority in a separate process."""
import argparse
import hashlib
import json
import math
from pathlib import Path
import shutil
import socket
import struct
import subprocess
import tempfile
import time

HERE = Path(__file__).resolve().parent
BASE = HERE.parent / "P0-NET-001"
STEP = 1_000_000 / 30


def parse(log, tag):
    lines = log.read_text(encoding="utf8", errors="replace").splitlines()
    records = [json.loads(line[len(tag):]) for line in lines if line.startswith(tag)]
    if len(records) != 1 or any("ERROR:" in line or "P0_FAILURE " in line for line in lines):
        raise RuntimeError(f"invalid {tag} in {log.name}: " + "\n".join(lines[-8:])[:1800])
    return records[0]


def judge(n, s, d, h):
    known = ["0/hit", "1/guard", "2/shield", "3/release", "4/expired", "5/future",
             "6/hit", "6/duplicate", "7/hit", "8/unbound"]
    positions = s["final_positions"]
    digest = hashlib.sha256(struct.pack(f"<{len(positions)}i", *positions)).hexdigest()
    costs, debt = s["cost_us"], s["debt_us"]
    p95 = sorted(costs)[math.ceil(.95 * len(costs)) - 1]
    streak = longest = 0
    for sample in debt:
        streak = streak + 1 if sample >= STEP else 0
        longest = max(longest, streak)
    seats = d["seats"]
    checks = {
        "distinct_real_connections": s["process_id"] != d["pid"] and len(set(d["peer_ids"])) == n == s["connected"],
        "all_seats_mapped": sorted(c["seat"] for c in seats) == list(range(n)),
        "actual_inputs": all(100 <= v <= 120 for v in s["accepted"]) and positions[:n] == s["accepted"],
        "actual_snapshots": all(c["snapshots"] >= 50 for c in seats) and len(positions) == n + 64,
        "active_ai_positions": min(positions[n:]) > 0,
        "all_peers_converged": all(c["closed"] and c["digest"] == digest and c["final_tick"] == s["final_tick"]
                                    for c in seats) and s["matching_acks"] == n,
        "invalids_rejected": s["duplicate"] >= n and s["stale"] >= n and
                             s["unauthorized"] == n and s["applied_twice"] == s["invalid"] == s["early_disconnects"] == 0,
        "traffic_observed": min(h["enet_tx_packets"], h["enet_rx_packets"], s["enet_sent_bytes"],
                                s["enet_received_bytes"]) > 0 and all(c["sent"] > 0 and c["received"] > 0 for c in seats),
        "headroom": p95 < STEP and longest < 15 and debt[-1] < 2 * STEP,
        "history_results_per_peer": h["results"] == {case: n for case in known} and len(h["outcomes_by_seat"]) == n
                                    and all(row == dict.fromkeys(known, 1) for row in h["outcomes_by_seat"]),
        "historical_melee_changes_ruling": h["counterfactuals"] == n,
        "projectile_hits_current_pose": h["forward_hits"] == n,
        "bounded_ring": h["samples_retained"] == 7,
    }
    window = s["traffic_window_ms"] / 1000
    return {"checks": checks, "tick_p95_us": p95, "max_debt_us": max(debt), "end_debt_us": debt[-1],
            "longest_overdue": longest, "enet_tx_Bps": round(s["enet_sent_bytes"] / window),
            "enet_rx_Bps": round(s["enet_received_bytes"] / window)}


def run(godot, n, project):
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as s:
        s.bind(("127.0.0.1", 0))
        port = s.getsockname()[1]
    peers = []
    try:
        for role in ("server", "driver"):
            out = project / f"{n}-{role}.txt"
            cmd = [godot, "--headless", "--path", str(project), "--log-file", str(out.with_suffix(".log")),
                   "--script", f"res://{role}.gd", "--", role, str(port), str(n), "loop"]
            with out.open("wb") as log:
                p = subprocess.Popen(cmd, stdout=log, stderr=subprocess.STDOUT)
            peers.append((p, out))
            if role == "server":
                end = time.monotonic() + 10
                while "P0_LISTENING" not in out.read_text(encoding="utf8", errors="replace"):
                    if time.monotonic() > end or p.poll() is not None:
                        raise RuntimeError("listen failed")
                    time.sleep(.05)
        for p, _ in peers:
            if p.wait(timeout=20) != 0:
                raise RuntimeError("peer exited non-zero")
        server = parse(peers[0][1], "P0_RESULT ")
        history = parse(peers[0][1], "P0_HISTORY ")
        driver = parse(peers[1][1], "P0_DRIVER ")
    except Exception:
        for p, log in peers:
            if p.poll() is None:
                p.kill()
            p.wait()
            print(log.read_text(encoding="utf8", errors="replace")[-2600:], flush=True)
        raise
    result = judge(n, server, driver, history)
    failed = [key for key, passed in result["checks"].items() if not passed]
    print(f"{n} peers P95 = {result['tick_p95_us']} us; failed={failed}", flush=True)
    return {"connections": n, "exit_codes": [p.returncode for p, _ in peers], "summary": result,
            "server": server, "history": history, "driver": driver}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--godot", required=True)
    ap.add_argument("--count", type=int, choices=(2, 64, 128), action="append")
    ap.add_argument("--output", type=Path)
    args = ap.parse_args()
    cache = HERE / ".godot"
    cache.mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory(dir=cache) as directory:
        project = Path(directory)
        # Reuse the tested P0-001 wire format and authority; no production install.
        for source in (BASE / "project.godot", BASE / "probe.gd", HERE / "server.gd", HERE / "driver.gd"):
            shutil.copyfile(source, project / source.name)
        results = [run(args.godot, n, project) for n in args.count or (64, 128)]
    if args.output:
        args.output.write_text(json.dumps(results, separators=(",", ":")) + "\n", encoding="utf8")
    return int(any(not all(r["summary"]["checks"].values()) for r in results))


if __name__ == "__main__":
    raise SystemExit(main())
