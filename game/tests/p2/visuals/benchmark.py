"""Measure the production visual consumer against a fixed, explicitly synthetic projection."""
import argparse
import gzip
import hashlib
import json
import math
import os
from pathlib import Path
import statistics
import subprocess
import tempfile

PROJECT = Path(__file__).resolve().parents[3]


def percentile(values, fraction):
    return sorted(values)[math.ceil(len(values)*fraction)-1]


def summarize(samples):
    frames, ticks = samples["frames"], samples["ticks"]
    count = samples["people"]
    if [row[0] for row in ticks] != list(range(121, 481)) or len(frames) < 10:
        raise ValueError("missing sample range")
    if samples["renderer"] != "forward_plus" or samples["driver"] != "vulkan" or samples["vsync"] != 0:
        raise ValueError("render settings")
    if samples.get("shadow_size") != 2048 or samples.get("camera_fov") != 60 or samples["seed"] != 241124:
        raise ValueError("P0 lighting, camera or seed")
    if (samples["pixels"] != [1920,1080] or samples["in_frustum"] != count+count//5
            or samples["near_min"] == 0 or samples["far_min"] == 0):
        raise ValueError("population or viewport")
    times = [r[0]*.001 for r in frames]
    debts = [r[2]*.001-(r[0]-120)*1000/60 for r in ticks[59::60]]
    m = {"frames":len(times), "fps":1000/statistics.mean(times),
         "low_1pct_fps":1000/statistics.mean(sorted(times,reverse=True)[:math.ceil(len(times)*.01)]),
         "p50_ms":percentile(times,.50), "p95_ms":percentile(times,.95),
         "p99_ms":percentile(times,.99), "worst_ms":max(times),
         "tick_p95_ms":percentile([r[1]*.001 for r in ticks],.95),
         "viewport_cpu_p95_ms":percentile([r[1] for r in frames],.95),
         "viewport_gpu_p95_ms":percentile([r[2] for r in frames],.95),
         "max_draws":max(r[3] for r in frames),"max_renderer_vram_bytes":max(r[4] for r in frames),
         "debt_ms_per_second":debts}
    growing = debts[-1]>1000/30 and all(b>a for a,b in zip(debts[-4:-1],debts[-3:]))
    m["within_visual_budget"] = (m["fps"] >= (60 if count==500 else 30)
                                and m["p95_ms"] <= (20 if count==500 else 40)
                                and m["tick_p95_ms"] < 1000/60 and not growing
                                and m["viewport_gpu_p95_ms"]>0 and m["max_draws"]>0)
    return m


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", required=True, type=Path)
    parser.add_argument("--project", type=Path, default=PROJECT)
    parser.add_argument("--count", required=True, type=int, choices=[500,1000])
    parser.add_argument("--out", required=True, type=Path)
    parser.add_argument("--trials", type=int, choices=[1,3], default=3)
    args = parser.parse_args()
    dest = args.out.resolve()
    dest.mkdir(parents=True,exist_ok=False)
    results = []
    with tempfile.TemporaryDirectory(prefix="visual-trials-") as work:
        work = Path(work)
        env = os.environ.copy()
        for key in ("APPDATA","LOCALAPPDATA"):
            folder = work/key
            folder.mkdir()
            env[key] = str(folder)
        for trial in range(1,args.trials+1):
            raw = work / "samples.json"
            screenshot = dest/"field.png" if args.count==1000 and trial==1 else None
            cmd = [str(args.godot.resolve()),"--path",str(args.project.resolve()),"--resolution","1920x1080",
                   "--rendering-method","forward_plus","--rendering-driver","vulkan","--disable-vsync",
                   "--audio-driver","Dummy","--log-file",str(work/"engine.log"),"--script",
                   "res://tests/p2/visuals/graphics.gd","--",str(args.count),str(raw),str(screenshot or "")]
            p = subprocess.run(cmd,capture_output=True,text=True,encoding="utf-8",errors="replace",timeout=180,env=env)
            log = p.stdout+p.stderr
            if p.returncode or "VIS_GRAPHICS_OK" not in log or "ERROR:" in log:
                raise RuntimeError(f"Godot {p.returncode}: {log[-4000:]}")
            payload = raw.read_bytes()
            samples = json.loads(payload)
            name = f"trial-{trial}.json.gz"
            (dest/name).write_bytes(gzip.compress(payload,mtime=0))
            metrics = summarize(samples)
            results.append({"trial":trial,"engine_exit":p.returncode,"file":name,
                            "sha256_raw":hashlib.sha256(payload).hexdigest(), "stats":metrics,
                            "scene":{k:v for k,v in samples.items() if k not in ("frames","ticks")}})
            (dest/"summary.json").write_text(json.dumps(results,indent=2)+"\n",encoding="utf-8")
            print(f"{args.count}/{trial}: {metrics['fps']:.1f} FPS p95={metrics['p95_ms']:.2f}ms "
                  f"skinned={samples['near_min']} batched={samples['far_min']}",flush=True)
    return int(not all(r["stats"]["within_visual_budget"] for r in results))


if __name__ == "__main__":
    raise SystemExit(main())
