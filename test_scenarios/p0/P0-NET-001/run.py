"""Run isolated Godot ENet peers. No packages or external endpoint required."""
import argparse
from contextlib import ExitStack
import json
import math
from pathlib import Path
import socket
import subprocess
import tempfile
import time

HERE = Path(__file__).resolve().parent
STEP_US = 1_000_000 / 30


def percentile(samples, quantile):
    return sorted(samples)[math.ceil(len(samples) * quantile) - 1]


def check(server, clients, expected, fault):
    costs, debt = server["cost_us"], server["debt_us"]
    final = server["final_positions"]
    p95 = percentile(costs, 0.95)
    # At least half a second continuously a tick behind is a sustained backlog.
    longest = run = 0
    for sample in debt:
        run = run + 1 if sample >= STEP_US else 0
        longest = max(longest, run)
    participants = [server, *clients]
    checks = {
        "independent_processes": len({p["process_id"] for p in participants}) == expected + 1,
        "connected": server["connected"] == len(clients) == expected,
        "distinct_seats": sorted(c["actor"] for c in clients) == list(range(expected)),
        "fixed_simulation": len(costs) == len(debt) == server["final_tick"] >= 136,
        "active_entities": len(final) == server["entities"] == 64 + expected and min(final[expected:]) > 0,
        "applied_once": server["applied_twice"] == 0 and final[:expected] == server["accepted"],
        "input_load": all(60 <= count <= 120 for count in server["accepted"]),
        "all_input_delivered_in_control": fault or server["accepted"] == [120] * expected,
        "reject_duplicate": server["duplicate"] >= expected,
        "reject_stale": server["stale"] >= expected,
        "reject_other_actor": server["unauthorized"] == 3 * expected,
        "no_bad_packets": server["invalid"] == 0,
        "snapshots_applied": all(c["snapshots_applied"] >= 35 and c["ack_age_ms"] for c in clients),
        "final_convergence": all(c["final_positions"] == final and c["final_tick"] == server["final_tick"]
                                 for c in clients) and server["matching_acks"] == expected,
        "observed_bytes": all(p["sent_app_bytes"] > 0 and p["received_app_bytes"] > 0 and
                              p["enet_sent_bytes"] > 0 and p["enet_received_bytes"] > 0 for p in participants),
        "no_disconnects": sum(p["early_disconnects"] for p in participants) == 0,
        "injected_both_legs": all((p["dropped"] > 0 and p["reorder_holds"] > 0) if fault
                                  else p["dropped"] == p["reorder_holds"] == 0 for p in participants),
        "primary_reordering_observed": not fault or server["primary_reordered"] > 0,
        "snapshot_reordering_observed": not fault or all(c["old_snapshots"] > 0 for c in clients),
        "tick_budget": p95 < STEP_US,
        "no_sustained_backlog": longest < 15 and debt[-1] < 2 * STEP_US,
    }
    duration = server["traffic_window_ms"] / 1000
    return {
        "checks": checks, "tick_p95_us": p95, "max_debt_us": max(debt),
        "end_debt_us": debt[-1], "longest_overdue_ticks": longest,
        "server_enet_tx_Bps": round(server["enet_sent_bytes"] / duration, 1),
        "server_enet_rx_Bps": round(server["enet_received_bytes"] / duration, 1),
        "server_app_tx_Bps": round(server["sent_app_bytes"] / duration, 1),
        "server_app_rx_Bps": round(server["received_app_bytes"] / duration, 1),
        "snapshot_ack_age_p95_ms": [percentile(c["ack_age_ms"], 0.95) for c in clients],
    }


def run_case(godot, count, mode, scratch):
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as port_probe:
        port_probe.bind(("127.0.0.1", 0))
        port = port_probe.getsockname()[1]
    peers = []
    with ExitStack() as stack:
        def launch(role, number):
            path = scratch / f"{mode}-{count}-{role}-{number}.txt"
            log = stack.enter_context(path.open("wb"))
            cmd = [godot, "--headless", "--log-file", str(path.with_suffix(".log")),
                   "--path", str(HERE), "--script", "res://probe.gd", "--",
                   role, str(port), str(count), mode]
            process = subprocess.Popen(cmd, stdout=log, stderr=subprocess.STDOUT)
            peers.append((process, path))
            return process, path

        server, output = launch("server", 0)
        try:
            deadline = time.monotonic() + 12
            while "P0_LISTENING" not in output.read_text(encoding="utf-8", errors="replace"):
                if server.poll() is not None or time.monotonic() > deadline:
                    raise RuntimeError("ENet server failed to start")
                time.sleep(0.05)
            for slot in range(count):
                launch("client", slot)
            deadline = time.monotonic() + 22
            for process, _ in peers:
                process.wait(timeout=max(0.1, deadline - time.monotonic()))
            records = []
            for process, path in peers:
                lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
                rows = [json.loads(line.removeprefix("P0_RESULT ")) for line in lines if line.startswith("P0_RESULT ")]
                if process.returncode or len(rows) != 1 or any("ERROR:" in line for line in lines):
                    raise RuntimeError(f"invalid result from {path.name}")
                records.append(rows[0])
        except Exception:
            for process, _ in peers:
                if process.poll() is None:
                    process.kill()
                process.wait()
            for _, path in peers:
                print(path.name, path.read_text(encoding="utf-8", errors="replace")[:2000], flush=True)
            raise
    stats = check(records[0], records[1:], count, mode == "fault")
    failed = [name for name, passed in stats["checks"].items() if not passed]
    print(f"{mode} x{count}: tick p95 {stats['tick_p95_us']} us; failed={failed}", flush=True)
    return {"mode": mode, "client_count": count, "exit_codes": [p.returncode for p, _ in peers],
            "summary": stats, "server": records[0], "clients": records[1:]}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--godot", required=True)
    parser.add_argument("--output", type=Path, help="Save per-process measurements and acceptance results")
    args = parser.parse_args()
    cache = HERE / ".godot"
    cache.mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory(dir=cache) as temp:
        cases = [run_case(args.godot, count, mode, Path(temp))
                 for count in (1, 4) for mode in ("loop", "fault")]
    if args.output:
        args.output.write_text(json.dumps(cases, separators=(",", ":")) + "\n", encoding="utf-8")
    return int(any(not all(case["summary"]["checks"].values()) for case in cases))


if __name__ == "__main__":
    raise SystemExit(main())
