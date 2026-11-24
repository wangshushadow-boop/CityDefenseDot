"""Run three identical rendered trials and retain all wall-clock/tick samples (Windows)."""
import argparse
import ctypes
from ctypes import wintypes
import gzip
import hashlib
import json
import math
from pathlib import Path
import statistics
import subprocess
import tempfile
import time

PROJECT = Path(__file__).resolve().parent
FPS_TARGET = {500: 60, 1000: 30}
P95_TARGET = {500: 20, 1000: 40}


class MemoryCounters(ctypes.Structure):
    _fields_ = [(key, wintypes.DWORD) for key in ("cb", "faults")] + [
        (key, ctypes.c_size_t) for key in (
            "peak_working_set", "working_set", "peak_paged_pool", "paged_pool",
            "peak_nonpaged_pool", "nonpaged_pool", "pagefile", "peak_pagefile",
        )
    ]


def peak_rss(pid_file):
    if not pid_file.is_file():
        return 0
    pid = pid_file.read_text().strip()
    if not pid:
        return 0
    kernel = ctypes.WinDLL("kernel32", use_last_error=True)
    kernel.OpenProcess.restype = wintypes.HANDLE
    kernel.CloseHandle.argtypes = [wintypes.HANDLE]
    psapi = ctypes.WinDLL("psapi", use_last_error=True)
    psapi.GetProcessMemoryInfo.argtypes = [wintypes.HANDLE, ctypes.POINTER(MemoryCounters), wintypes.DWORD]
    handle = kernel.OpenProcess(0x410, False, int(pid))
    if not handle:
        return 0
    counters = MemoryCounters()
    counters.cb = ctypes.sizeof(counters)
    try:
        if psapi.GetProcessMemoryInfo(handle, ctypes.byref(counters), counters.cb):
            return counters.peak_working_set
        return 0
    finally:
        kernel.CloseHandle(handle)


def quantile(values, q):
    return sorted(values)[math.ceil(len(values) * q) - 1]


def summarize(data, rss):
    frames, ticks = data["frames"], data["ticks"]
    if not frames or len(ticks) != 360 or ticks[0][0] != 121 or ticks[-1][0] != 480:
        raise ValueError("missing fixed sampling window")
    frame_ms = [row[0] / 1000 for row in frames]
    tick_ms = [row[1] / 1000 for row in ticks]
    last_debts = [(row[2] / 1000 - (row[0] - 120) * 1000 / 60) for row in ticks[59::60]]
    growing = last_debts[-1] > 1000 / 30 and all(
        b > a for a, b in zip(last_debts[-4:-1], last_debts[-3:])
    )
    # Three successively growing 1-second samples with >2 ticks of end debt.
    n = data["count"]
    metrics = {
        "frame_samples": len(frames),
        "fps": 1000 / statistics.mean(frame_ms),
        "low_1pct_fps": 1000 / statistics.mean(sorted(frame_ms, reverse=True)[:math.ceil(len(frames) * .01)]),
        "frame_p50_ms": quantile(frame_ms, .50), "frame_p95_ms": quantile(frame_ms, .95),
        "frame_p99_ms": quantile(frame_ms, .99), "frame_worst_ms": max(frame_ms),
        "tick_p95_ms": quantile(tick_ms, .95), "wall_debt_ms_each_second": last_debts,
        "sustained_backlog": growing, "viewport_render_cpu_p95_ms": quantile([r[1] for r in frames], .95),
        "viewport_gpu_p95_ms": quantile([r[2] for r in frames], .95),
        "draw_calls_peak": max(r[3] for r in frames), "primitives_peak": max(r[4] for r in frames),
        "renderer_video_bytes_peak": max(r[5] for r in frames), "rss_bytes_process_peak": rss,
    }
    errors = []
    if (data["display"].lower() == "headless" or data["pixels"] != [1920, 1080]
            or data["vsync"] != 0 or data["renderer"] != "forward_plus" or data["driver"] != "vulkan"):
        errors.append("render configuration")
    if (data["peak_arrows"] <= 0 or min(data["activity"]) <= 0 or data["moved_units"] <= 0
            or metrics["draw_calls_peak"] <= 0 or metrics["primitives_peak"] <= 0):
        errors.append("mixed field activity")
    if min(rss, metrics["viewport_gpu_p95_ms"], metrics["renderer_video_bytes_peak"]) <= 0:
        errors.append("missing profile measurements")
    if metrics["fps"] < FPS_TARGET[n] or metrics["frame_p95_ms"] > P95_TARGET[n]:
        errors.append("frame time")
    if metrics["tick_p95_ms"] >= 1000 / 60 or growing:
        errors.append("simulation tick")
    if rss > 10_000_000_000:
        errors.append("RSS")
    if n == 500 and metrics["viewport_gpu_p95_ms"] > 16.7:
        errors.append("GPU 60 fps budget")
    return metrics, errors


def run_trial(godot, count, out, run):
    with tempfile.TemporaryDirectory(prefix="p0-mixed-") as tmp:
        work = Path(tmp)
        result = work / "samples.json"
        command = [str(godot), "--path", str(PROJECT), "--rendering-method", "forward_plus",
                   "--rendering-driver", "vulkan", "--resolution", "1920x1080", "--disable-vsync",
                   "--audio-driver", "Dummy", "--log-file", str(work / "engine.log"),
                   "--", str(count), str(result)]
        with (work / "console.txt").open("wb") as log:
            proc = subprocess.Popen(command, stdout=log, stderr=subprocess.STDOUT)
            largest_rss = 0
            deadline = time.monotonic() + 120
            while proc.poll() is None and time.monotonic() < deadline:
                largest_rss = max(largest_rss, peak_rss(result.with_suffix(".json.pid")))
                time.sleep(.25)
            if proc.poll() is None:
                subprocess.run(["taskkill", "/pid", str(proc.pid), "/t", "/f"], capture_output=True)
                proc.wait(timeout=10)
        console = (work / "console.txt").read_text(errors="replace", encoding="utf-8")
        if proc.returncode or "SCRIPT ERROR" in console or "ERROR:" in console or not result.is_file():
            raise RuntimeError(f"Godot exit {proc.returncode}\n{console[-3000:]}")
        raw = result.read_bytes()
    metrics, errors = summarize(json.loads(raw), largest_rss)
    data = json.loads(raw)
    raw_name = f"{count}-{run}.json.gz"
    (out / raw_name).write_bytes(gzip.compress(raw, mtime=0))
    for name in ("frames", "ticks"):
        del data[name]
    return {"trial": run, "raw_file": raw_name, "raw_sha256_uncompressed": hashlib.sha256(raw).hexdigest(),
            "godot_exit": proc.returncode, "input": data, "metrics": metrics, "failed_checks": errors}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", type=Path, required=True)
    parser.add_argument("--count", type=int, choices=FPS_TARGET, required=True)
    parser.add_argument("--out", type=Path, help="must be a fresh output directory")
    args = parser.parse_args()
    out = args.out or (Path.cwd() / "out" / f"P0-BATTLE-{args.count}-{time.time_ns()}")
    out.mkdir(parents=True, exist_ok=False)
    results = []
    for trial in range(1, 4):
        record = run_trial(args.godot.resolve(), args.count, out, trial)
        results.append(record)
        (out / "summary.json").write_text(json.dumps(results, indent=2), encoding="utf-8")
        print(f"{args.count} run {trial}: {record['metrics']['fps']:.1f} fps, "
              f"P95 {record['metrics']['frame_p95_ms']:.2f} ms, failed={record['failed_checks']}", flush=True)
    print(out)
    return int(any(row["failed_checks"] for row in results))


if __name__ == "__main__":
    raise SystemExit(main())
