"""Run three rendered, authoritative field battles per population. Preserve failures and raw data."""
import argparse
import gzip
import hashlib
import importlib.util
import json
import math
import os
from pathlib import Path
import statistics
import subprocess
import tempfile
import time

# Reuse the P0 process RSS sampler and its nearest-rank percentile convention.
P0 = Path(__file__).resolve().parents[4] / "test_scenarios/p0/P0-BATTLE-001/run.py"
spec = importlib.util.spec_from_file_location("p0_field", P0)
p0 = importlib.util.module_from_spec(spec)
spec.loader.exec_module(p0)


def analyze(data, rss):
    ticks, frames, n = data["ticks"], data["frames"], data["count"]
    if not frames or len(ticks) != 360:
        return {}, ["incomplete sample window"]
    ms = [f[0] / 1000 for f in frames]
    sim = [t[1] / 1000 for t in ticks]
    debt = [t[2] / 1000 - (i + 1) * 1000 / 60 for i, t in enumerate(ticks) if (i + 1) % 60 == 0]
    backlog = debt[-1] > 1000 / 30 and all(b > a for a, b in zip(debt[-4:-1], debt[-3:]))
    draw_p95 = p0.quantile([f[2] for f in frames], .95)
    metrics = {
        "fps": 1000 / statistics.mean(ms),
        "low_1pct_fps": 1000 / statistics.mean(sorted(ms, reverse=True)[:math.ceil(len(ms) * .01)]),
        "frame_ms": {key: p0.quantile(ms, q) for key, q in [("p50", .50), ("p95", .95), ("p99", .99)]},
        "frame_worst_ms": max(ms), "simulation_p95_ms": p0.quantile(sim, .95),
        "render_cpu_p95_ms": p0.quantile([f[1] for f in frames], .95), "gpu_p95_ms": draw_p95,
        "draw_peak": max(f[3] for f in frames), "primitives_peak": max(f[4] for f in frames),
        "renderer_video_bytes_peak": max(f[5] for f in frames), "process_rss_peak_bytes": rss,
        "wall_debt_ms_each_second": debt, "sustained_backlog": backlog, "frame_samples":len(frames),
        "fixed_samples": len(sim), "near_peak": max(f[6] for f in frames),
        "far_peak": max(f[7] for f in frames), "submitted_mounts_peak": max(f[8] for f in frames),
        "submitted_projectiles_peak": max(f[9] for f in frames), "submitted_corpses_peak": max(f[10] for f in frames),
        "in_frustum_skinned_peak": max(f[12] for f in frames) if len(frames[0])>12 else None,
        "in_frustum_projectiles_peak": max(f[13] for f in frames) if len(frames[0])>13 else None,
        "projectiles_after_fixed_step_peak": max(t[7] for t in ticks) if len(ticks[0]) > 7 else None,
    }
    config = {"renderer": "forward_plus", "driver": "vulkan", "pixels": [1920,1080], "vsync": 0,
              "shadow_px": 2048, "msaa_samples": 2, "fov": 60, "seed": 241124}
    roles = {f"field:troop/{k}": n * pct // 100 for k, pct in
             [("infantry", 50), ("archer", 30), ("cavalry", 10), ("mounted_archer", 10)]}
    roles["mount"] = n // 5
    checks = {
        "configuration": all(data[k] == v for k,v in config.items()) and data["display"] != "headless",
        "authority_clock": all(t[0] == data["measure_from"] + i + 1 for i,t in enumerate(ticks)),
        "real_population": data["opening_roles"] == roles and data["max_humans"] == n,
        "mixed_action": (0 < data["contact_tick"] <= data["approach_ticks"] and data["hits"] > 0
                         and data["events"].get("projectile_launched",0) > 0 and metrics["submitted_mounts_peak"] > 0),
        "command_accepted": data["player_order"], "render_samples": draw_p95 > 0 and metrics["primitives_peak"] > 0,
        "visible_skinned_animation": bool(metrics["in_frustum_skinned_peak"]),
        "visible_projectile_flight": bool(metrics["in_frustum_projectiles_peak"]),
        "frame_budget": metrics["fps"] >= (60 if n==500 else 30) and metrics["frame_ms"]["p95"] <= (20 if n==500 else 40),
        "tick_budget": metrics["simulation_p95_ms"] < 1000/60,
        "no_sustained_backlog": not backlog, "process_rss": 0 < rss <= 10_000_000_000,
        "gpu_frame_budget": n != 500 or draw_p95 <= 16.7,
    }
    return metrics, [key for key, passed in checks.items() if not passed]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", type=Path, required=True)
    parser.add_argument("--project", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--count", nargs="+", type=int, choices=(500,1000), default=[500,1000])
    parser.add_argument("--trials", nargs="+", type=int, choices=(1,2,3), default=[1,2,3])
    parser.add_argument("--input-trace", choices=("together","flanks"), default="flanks")
    args = parser.parse_args()
    args.out.mkdir(parents=True, exist_ok=False)
    results = []
    for n in args.count:
        for trial in args.trials:
            name = f"{n}-{trial}"
            dest = args.out.resolve() / name
            dest.mkdir()
            raw = dest / "samples.json"
            command = [str(args.godot.resolve()), "--path", str(args.project.resolve()),
                       "--rendering-method", "forward_plus", "--rendering-driver", "vulkan",
                       "--resolution", "1920x1080", "--disable-vsync", "--log-file", str(dest/"engine.log"),
                       "--script", "res://tests/p2/field_benchmark/run.gd", "--", str(n), str(raw), args.input_trace]
            with tempfile.TemporaryDirectory(prefix="p2-bench-") as tmp, (dest/"console.log").open("wb") as log:
                env = dict(os.environ, APPDATA=tmp, LOCALAPPDATA=tmp)
                process = subprocess.Popen(command, stdout=log, stderr=subprocess.STDOUT, env=env)
                rss = 0
                deadline = time.monotonic() + 1800
                while process.poll() is None and time.monotonic() < deadline:
                    rss = max(rss, p0.peak_rss(raw.with_suffix(".json.pid")))
                    time.sleep(.25)
                timed_out = process.poll() is None
                if timed_out:
                    subprocess.run(["taskkill", "/PID", str(process.pid), "/T", "/F"], capture_output=True)
                code = process.wait()
            text = (dest/"console.log").read_text(encoding="utf-8", errors="replace")
            errors = []
            stats = {}
            data = {}
            if code or "ERROR:" in text or "FIELD_BENCHMARK ticks=" not in text:
                errors.append("engine or script error")
            if timed_out:
                errors.append("timeout")
            if raw.exists():
                blob = raw.read_bytes()
                (dest/"samples.json.gz").write_bytes(gzip.compress(blob,mtime=0))
                data = json.loads(blob)
                stats, failed = analyze(data, rss)
                errors.extend(failed)
                del data["ticks"], data["frames"]
                data["sha256_uncompressed"] = hashlib.sha256(blob).hexdigest()
            else:
                errors.append("missing raw samples")
            results.append({"count": n, "trial": trial, "engine_exit":code, "metrics":stats,
                            "field":data, "failed_checks":errors})
            (args.out/"summary.json").write_text(json.dumps(results,indent=2)+"\n",encoding="utf-8")
            print(f"{name}: {stats.get('fps',0):.2f} FPS; failed={errors}",flush=True)
    return int(any(r["failed_checks"] for r in results))


if __name__ == "__main__":
    raise SystemExit(main())
