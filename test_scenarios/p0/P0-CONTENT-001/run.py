"""Clean import, validate, compile, reject damaged content, then load the exported PCK."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

from fixture import build

ROOT = Path(__file__).resolve().parent


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", required=True, type=Path)
    args = parser.parse_args()
    executable = args.godot.resolve()
    with tempfile.TemporaryDirectory(prefix="recollection-content-") as scratch:
        scratch = Path(scratch)
        project = scratch / "source"
        project.mkdir()
        for name in ("project.godot", "export_presets.cfg", "verify.gd", "manifest.json"):
            shutil.copyfile(ROOT / name, project / name)
        build(project / "sample.gltf")
        fixture_hash = hashlib.sha256((project / "sample.gltf").read_bytes()).hexdigest()
        env = os.environ | {"APPDATA": str(scratch / "roaming"),
                            "LOCALAPPDATA": str(scratch / "local")}
        for key in ("APPDATA", "LOCALAPPDATA"):
            Path(env[key]).mkdir()

        def run(label, options, expected=0, marker=None, cwd=project):
            cmd = [str(executable), "--headless", "--log-file", str(scratch / "engine.log"),
                   *map(str, options)]
            proc = subprocess.run(cmd, cwd=cwd, env=env, stdout=subprocess.PIPE,
                                  stderr=subprocess.STDOUT, encoding="utf-8",
                                  errors="replace", timeout=90)
            log = proc.stdout
            print(f"{label}: exit={proc.returncode} {marker or ''}", flush=True)
            if (proc.returncode != expected or (marker and marker not in log)
                    or "SCRIPT ERROR:" in log or "ERROR:" in log):
                raise RuntimeError(f"{label} failed\n{log}")

        run("editor import", ["--editor", "--import"], marker="sample.gltf")
        definition = json.loads((project / "manifest.json").read_text(encoding="utf-8"))
        compiled = scratch / "compiled.bin"
        verify = ["--script", "res://verify.gd", "--"]
        run("source compile and reload", [*verify, "res://manifest.json", compiled],
            marker="CONTENT_OK")
        good_bytes = compiled.read_bytes()
        for key, value, reason in [
            ("scene", "res://missing.gltf", "reference"),
            ("usage", "", "provenance"),
            ("rigs", [definition["rigs"][0] | {"socket": "MissingGrip"}, definition["rigs"][1]], "socket"),
            ("rigs", [definition["rigs"][0] | {"socket": "Weapon*"}, definition["rigs"][1]], "socket"),
            ("rigs", [definition["rigs"][0]] * 2, "socket"),
            ("markers", ["MissingSpawn", "Gate_A"], "marker"),
            ("markers", ["Spawn_A", "Spawn_A"], "marker"),
            ("markers", ["Spawn_*", "Gate_A"], "marker"),
            ("action", definition["action"] | {"clip": "MissingClip"}, "clip"),
            ("action", definition["action"] | {"end_s": 2}, "window"),
            ("action", definition["action"] | {"start_s": 0.38}, "window"),
        ]:
            damaged = scratch / "invalid.json"
            damaged.write_text(json.dumps(definition | {key: value}), encoding="utf-8")
            run(f"reject {key}", [*verify, damaged, compiled], 2, f"CONTENT_REJECT {reason}")
            if compiled.read_bytes() != good_bytes:
                raise RuntimeError("Rejected definition replaced previous compiled bytes")

        pack = scratch / "content.pck"
        run("export pack", ["--export-pack", "ContentPack", pack])
        # Load without a source project or its import cache.
        packed_output = scratch / "packed.bin"
        run("packed resource compile and reload",
            ["--main-pack", pack, *verify, "res://manifest.json", packed_output],
            marker="CONTENT_OK", cwd=scratch)
        if packed_output.read_bytes() != good_bytes:
            raise RuntimeError("Packed and source definitions differ")
        print(f"CONTENT_PASS fixture_sha256={fixture_hash} compiled_bytes={len(good_bytes)} "
              f"pack_bytes={pack.stat().st_size}")


if __name__ == "__main__":
    main()

