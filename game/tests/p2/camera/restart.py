"""Start fresh Godot processes with an isolated local camera profile (T-CAM-02)."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import tempfile

PROJECT = Path(__file__).resolve().parents[3]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", type=Path, required=True)
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix="recollection-camera-") as folder:
        scratch = Path(folder)
        env = os.environ | {"RECOLLECTION_CAMERA_TEST": "isolated"}
        for key in ("APPDATA", "LOCALAPPDATA", "XDG_DATA_HOME", "XDG_CONFIG_HOME"):
            path = scratch/key
            path.mkdir()
            env[key] = str(path)

        def stage(name):
            run = subprocess.run([str(args.godot.resolve()), "--headless", "--path", str(PROJECT),
                                  "--log-file", str(scratch/f"{name}.log"), "--script",
                                  "res://tests/p2/camera/run.gd", "--", name],
                                 env=env, capture_output=True, text=True, encoding="utf-8",
                                 errors="replace", timeout=40)
            output = run.stdout + run.stderr
            markers = [line.removeprefix("CAMERA_RESULT ") for line in output.splitlines()
                       if line.startswith("CAMERA_RESULT ")]
            if run.returncode or len(markers)!=1 or "ERROR:" in output or "FAIL " in output:
                raise RuntimeError(f"{name} exit={run.returncode}\n{output}")
            result = json.loads(markers[0])
            if result["failures"] or result["checks"] <= 0 or result["stage"]!=name:
                raise RuntimeError(f"{name} invalid report: {result}")
            print(f"{name}: exit=0 {result['checks']} checks",flush=True)

        stage("write")
        matches = list(scratch.rglob("field-camera.json"))
        if len(matches)!=1:
            raise RuntimeError(f"expected one settings file, found {len(matches)}")
        settings = matches[0]
        valid = settings.read_bytes()
        if json.loads(valid) != {"fov_mdeg": 91750, "shake": False}:
            raise RuntimeError("persisted preference mismatch")
        stage("read")
        settings.write_bytes(b'{"fov_mdeg":91750,"shake":"false"}')
        stage("damaged")
        settings.write_bytes(valid)
        stage("read")
    print("T-CAM-02 PASS across 4 fresh processes")


if __name__=="__main__":
    main()
