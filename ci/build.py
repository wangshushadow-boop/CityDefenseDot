"""Build and cold-start the P1 Windows client, dedicated server and base content from Git HEAD."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tarfile
import tempfile
import uuid
import zipfile

from gates import dependencies


ROOT = Path(__file__).resolve().parents[1]
BASE = Path("infrastructure/content/base")
PRESET = '''[preset.0]
name="Recollection"
platform="Windows Desktop"
runnable=true
custom_features="{target}"
export_filter="all_resources"
include_filter="*.json"
exclude_filter="*.md,*.py,tests/*"
script_export_mode=0
[preset.0.options]
binary_format/architecture="x86_64"
'''


def run(args, cwd, env, timeout=180):
    result = subprocess.run(args, cwd=cwd, env=env, capture_output=True, timeout=timeout)
    log = (result.stdout + result.stderr).decode("utf-8", "replace").replace("\r", "")
    if result.returncode or "ERROR:" in log or "SCRIPT ERROR" in log:
        raise ValueError(f"{Path(args[0]).name} {args[1:]} exit={result.returncode}\n{log}")
    return log


def godot(engine, args, cwd, env, desktop=False):
    flags = ["--windowed", "--resolution", "800x500"] if desktop else ["--headless"]
    return run([engine, *flags, "--log-file", str(cwd / "godot.log"), *args], cwd, env)


def boot(engine, where, env, options, profile):
    args = [*options, "--", f"--profile={profile}", "--p1-smoke"]
    log = godot(engine, args, where, env, desktop=profile == "client")
    return boot_record(log, profile)


def boot_record(log, profile):
    rows = [json.loads(line[8:]) for line in log.splitlines() if line.startswith("P1_BOOT ")]
    if len(rows) != 1:
        raise ValueError(f"expected one BOOT record for {profile}\n{log}")
    row = rows[0]
    if (row.get("profile") != profile or row.get("event") != "stopped" or row.get("exit_code") != 0
            or type(row.get("protocol_version")) is not int or not row.get("protocol_version")
            or not re.fullmatch(r"[a-f0-9]{64}", row.get("content_hash", ""))):
        raise ValueError(f"invalid BOOT record {row}")
    if profile in {"client", "headless"}:
        if (row.get("mission_tick") != 3 or row.get("presentation_loaded") != (profile == "client")
                or (row.get("display") == "headless") != (profile == "headless")
                or not re.fullmatch(r"[a-f0-9]{64}", row.get("state_hash", ""))):
            raise ValueError(f"wrong Mission or display profile {row}")
    return row


def json_bytes(data):
    return (json.dumps(data, indent=2, ensure_ascii=False) + "\n").encode("utf-8")


def check_runtime_pack(engine, stage, env, pck, stamp, script):
    packed = godot(engine, ["--main-pack", pck, "--script", script], stage, env)
    rows = [json.loads(line[11:]) for line in packed.splitlines() if line.startswith("PACK_STAMP ")]
    if rows != [stamp]:
        raise ValueError(f"packed metadata mismatch for {pck.name}: {packed}")


def build(engine, out):
    commit = subprocess.check_output(["git", "rev-parse", "--verify", "HEAD"], cwd=ROOT, text=True).strip()
    out = out.resolve()
    out.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="recollection-build-") as scratch, tempfile.TemporaryDirectory(dir=out) as publish:
        scratch = Path(scratch)
        stage = Path(publish)
        env = os.environ.copy()
        for key in ("APPDATA", "LOCALAPPDATA", "XDG_CONFIG_HOME", "XDG_DATA_HOME", "XDG_CACHE_HOME"):
            home = scratch / key
            home.mkdir()
            env[key] = str(home)
        for key in ("RECOLLECTION_PROFILE", "RECOLLECTION_LOG_LEVEL"):
            env.pop(key, None)
        archive = scratch / "sources.tar"
        subprocess.run(["git", "archive", "-o", archive, commit, "game", "ci", "development/state/project.json"],
                       cwd=ROOT, check=True)
        cold = scratch / "cold"
        cold.mkdir()
        with tempfile.TemporaryDirectory(dir=scratch, prefix="source-") as tree:
            tree = Path(tree)
            with tarfile.open(archive) as tar:
                tar.extractall(tree, filter="data")
            for file in ("build.py", "gates.py", "inspect_pack.gd"):
                at_commit = tree / "ci" / file
                if not at_commit.is_file() or (ROOT / "ci" / file).read_text("utf-8") != at_commit.read_text("utf-8"):
                    raise ValueError(f"build recipe ci/{file} differs from Git input {commit}")
            inspector = scratch / "inspect_pack.gd"
            shutil.copyfile(tree / "ci/inspect_pack.gd", inspector)
            game = tree / "game"
            expected = json.loads((tree / "development/state/project.json").read_bytes())["technical_stack"]["engine_version"]
            version = run([engine, "--version"], cold, env).strip()
            if version != expected:
                raise ValueError(f"engine mismatch: expected {expected}, got {version}")
            print(run([sys.executable, "-B", game / "tests/p1/ci/test_gates.py"], cold, env).strip(), flush=True)
            errors = dependencies(game)
            if errors:
                raise ValueError("\n".join(errors))
            print("T-CI-01 production dependency graph PASS", flush=True)
            evidence = stage / "domain-tests.json"
            # The suite exercises real production scripts outside the export image.
            output = run([sys.executable, "-B", game / "tests/p1/harness/suite.py", "--godot", engine,
                          "--game", game, "--build", commit, "--evidence", evidence], cold, env, timeout=900)
            print(output.strip(), flush=True)
            report = json.loads(evidence.read_bytes())
            ran = {row["suite"] for row in report["results"] if row["status"] == "PASS"}
            if not {"core", "definitions", "application", "bootstrap", "content", "persistence", "mission"} <= ran:
                raise ValueError("required production suites absent")
            # Delete only the staged test directory extracted from Git.
            shutil.rmtree(game / "tests")
            # Preserve committed text scene IDs and references. Auto-generated
            # binary scene IDs otherwise introduce entropy into equivalent PCKs.
            with (game / "project.godot").open("a", encoding="utf-8") as settings:
                settings.write("\n[editor]\nexport/convert_text_resources_to_binary=false\n")
            stamp = {"git_commit": commit, "engine_version": version, "language": "GDScript"}
            source = boot(engine, cold, env, ["--path", game], "tool")
            stamp.update(protocol_version=source["protocol_version"], content_hash=source["content_hash"])
            raw = game / BASE
            with zipfile.ZipFile(stage / "base.zip", "w", compression=zipfile.ZIP_DEFLATED) as content:
                def add_raw(name, data):
                    info = zipfile.ZipInfo(name)
                    info.create_system = 3
                    info.external_attr = 0o100644 << 16
                    content.writestr(info, data, compress_type=zipfile.ZIP_DEFLATED)
                add_raw("build.json", json_bytes(stamp | {"target": "base"}))
                for path in sorted(raw.rglob("*")):
                    if path.is_file() and not path.name.endswith((".md", ".uid", ".import")):
                        add_raw("base/" + path.relative_to(raw).as_posix(), path.read_bytes())
            for target in ("client", "server"):
                (game / "export_presets.cfg").write_text(PRESET.format(target=target), encoding="utf-8")
                (game / "build_info.json").write_bytes(json_bytes(stamp | {"target": target}))
                godot(engine, ["--editor", "--path", game, "--import"], cold, env)
                godot(engine, ["--path", game, "--export-pack", "Recollection", stage / (target + ".pck")], cold, env)
        # The source resource root is gone. Cold processes see only the exported files.
        smokes = {}
        for target, profile in (("client", "client"), ("server", "headless")):
            pack = stage / (target + ".pck")
            check_runtime_pack(engine, cold, env, pack, stamp | {"target": target}, inspector)
            smokes[target] = boot(engine, cold, env, ["--main-pack", pack], profile)
        if smokes["client"]["state_hash"] != smokes["server"]["state_hash"]:
            raise ValueError("client/server fixed-tick Mission states differ")
        with zipfile.ZipFile(stage / "base.zip") as zipped:
            if json.loads(zipped.read("build.json")) != stamp | {"target": "base"}:
                raise ValueError("base package build metadata mismatch")
            zipped.extractall(cold)
        log = godot(engine, ["--main-pack", stage / "server.pck", "--", "--profile=tool",
                             "--content-path=" + str(cold / "base")], cold, env)
        smokes["base"] = boot_record(log, "tool")
        if any(row["content_hash"] != stamp["content_hash"] or row["protocol_version"] != stamp["protocol_version"]
               for row in smokes.values()):
            raise ValueError("cold-start content/protocol mismatch")
        artifacts = {name: {"size": (stage / name).stat().st_size,
                            "sha256": hashlib.sha256((stage / name).read_bytes()).hexdigest()}
                     for name in ("client.pck", "server.pck", "base.zip", "domain-tests.json")}
        (stage / "manifest.json").write_bytes(json_bytes(stamp | {"channel": "development", "artifacts": artifacts, "smokes": smokes}))
        # Every successful invocation publishes a complete, distinct directory.
        destination = out / (commit[:12] + "-" + uuid.uuid4().hex[:12])
        stage.rename(destination)
    print("T-CI-03 PASS", destination / "manifest.json")
    return destination


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args()
    build(args.godot.resolve(), args.out)


if __name__ == "__main__":
    try:
        main()
    except (KeyError, ValueError, OSError, subprocess.SubprocessError) as error:
        sys.exit(f"build failed: {error}")
