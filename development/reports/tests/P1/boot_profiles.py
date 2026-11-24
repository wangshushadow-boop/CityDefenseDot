"""Replay the production entry point on Windows/Vulkan and headless in clean user directories."""
import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile


def replay(engine, game, pack, profile):
    with tempfile.TemporaryDirectory(prefix="recollection-boot-") as tmp:
        work = Path(tmp)
        data = work / "user"
        data.mkdir()
        env = dict(os.environ, APPDATA=str(data), LOCALAPPDATA=str(data))
        cmd = [engine, "--log-file", str(work / "engine.log")]
        if profile == "headless":
            cmd += ["--headless"]
        if pack:
            local = work / "recollection.pck"
            shutil.copyfile(pack, local)
            cmd += ["--main-pack", str(local)]
        else:
            cmd += ["--path", str(game)]
        proc = subprocess.run(cmd + ["--", "--p1-smoke"], cwd=work, env=env, timeout=90,
                              capture_output=True, text=True, encoding="utf-8", errors="replace")
        log = proc.stdout + proc.stderr
        print(log.rstrip(), flush=True)
        print(f"PROCESS {profile} exit={proc.returncode}", flush=True)
        if proc.returncode or "ERROR:" in log:
            raise RuntimeError(f"{profile} startup failed")
        records = [json.loads(s.removeprefix("P1_BOOT ")) for s in log.splitlines()
                   if s.startswith("P1_BOOT ")]
        if len(records) != 1:
            raise RuntimeError(f"{profile}: expected one startup result")
        report, = records
        if report["profile"] != profile or report["exit_code"] != 0 or report["mission_tick"] != 3:
            raise RuntimeError(f"{profile}: incomplete startup")
        if report.get("presentation_loaded") != (profile == "client") or report.get("event") != "stopped":
            raise RuntimeError(f"{profile}: profile did not release a matching presentation setup")
        if report.get("failed_module") or not report.get("release_order"):
            raise RuntimeError(f"{profile}: incomplete shutdown")
        return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", required=True, type=Path)
    parser.add_argument("--game", type=Path, default=Path("game"))
    parser.add_argument("--client-pack", type=Path)
    parser.add_argument("--server-pack", type=Path)
    args = parser.parse_args()
    if bool(args.client_pack) != bool(args.server_pack):
        parser.error("both profile packs must be supplied together")
    client, server = [replay(str(args.godot.resolve()), args.game.resolve(), pack, profile)
                      for profile, pack in (("client", args.client_pack), ("headless", args.server_pack))]
    for key in ("protocol_version", "content_hash", "mission_tick", "state_hash"):
        if not client[key] or client[key] != server[key]:
            raise RuntimeError(f"profile mismatch in {key}")
    for key in ("content_hash", "state_hash"):
        if len(client[key]) != 64 or any(c not in "0123456789abcdef" for c in client[key]):
            raise RuntimeError(f"invalid digest in {key}")
    print("P1_BOOT_PROFILES PASS", flush=True)


if __name__ == "__main__":
    main()
