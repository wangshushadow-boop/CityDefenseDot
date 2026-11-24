"""Godot/Python canonical wire vectors for one small, typed ADR-012 message."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import runpy
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parent
REFERENCE = runpy.run_path(str(ROOT.parent / "P0-CONTRACTS-001" / "vectors.py"))
canonical = REFERENCE["canonical"]
decode = REFERENCE["decode"]
integer = REFERENCE["integer"]
LIMIT = 2**53 - 1


def check(ok, reason):
    if not ok:
        raise ValueError(reason)


def message(data):
    fields = decode(data)
    check(type(fields) is dict and fields.keys() == {"delta", "enabled", "label"}, "shape")
    integer(fields["delta"], -LIMIT, LIMIT)
    check(type(fields["enabled"]) is bool and type(fields["label"]) is str, "field types")
    check(all(32 <= ord(c) <= 126 or 0x4E00 <= ord(c) <= 0x9FFF or c == "é"
              for c in fields["label"]), "probe text repertoire")
    check(canonical(fields) == data, "noncanonical bytes")
    return fields


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", required=True, type=Path)
    args = parser.parse_args()
    good = {"label": '步兵é"\\', "enabled": True, "delta": LIMIT}
    wire = canonical(good)
    check(hashlib.sha256(wire).hexdigest() == "dd1908c7406d18b40ace6c22b59aaf18f45bed1981057a242a3b4c8c18019038",
          "Python-origin golden digest")

    def token(value):
        return wire.replace(str(LIMIT).encode(), value)

    valid = {"upper": wire, "lower": token(str(-LIMIT).encode()), "zero": token(b"0"),
             "false": canonical(good | {"enabled": False})}
    invalid = {
        "bool_for_number": token(b"true"), "integer_for_bool": wire.replace(b"true", b"1"),
        "float": token(b"1.0"), "exponent": token(b"1e0"), "negative_zero": token(b"-0"),
        "above_limit": token(b"9007199254740992"), "below_limit": token(b"-9007199254740992"),
        "rounded": token(b"9007199254740993"), "duplicate": wire.replace(b'{"delta":', b'{"delta":2,"delta":'),
        "decomposed": wire.replace("é".encode(), "e\u0301".encode()), "bom": b"\xef\xbb\xbf" + wire,
        "extra": wire.replace(b'{"delta":', b'{"a":0,"delta":'), "space": wire + b" ",
        "unsorted": json.dumps(good, ensure_ascii=False, separators=(",", ":")).encode(),
        "other_nfc": wire.replace("é".encode(), "ñ".encode()),
    }
    cases = valid | invalid
    with tempfile.TemporaryDirectory(prefix="recollection-codec-") as scratch:
        folder = Path(scratch)
        for name, data in cases.items():
            try:
                message(data)
            except ValueError:
                check(name in invalid, f"Python rejected {name}")
            else:
                check(name in valid, f"Python accepted {name}")
            (folder / (name + ".in")).write_bytes(data)
        env = os.environ | {"APPDATA": scratch, "LOCALAPPDATA": scratch}
        cmd = [str(args.godot.resolve()), "--headless", "--path", str(ROOT), "--log-file", str(folder / "engine.log"),
               "--script", "res://probe.gd", "--", scratch]
        proc = subprocess.run(cmd, env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                              encoding="utf-8", errors="replace", timeout=30)
        if proc.returncode or "SCRIPT ERROR:" in proc.stdout or "ERROR:" in proc.stdout:
            raise RuntimeError(proc.stdout)
        def payload(prefix):
            return next(line[len(prefix):] for line in proc.stdout.splitlines() if line.startswith(prefix))
        print("DEFAULT", payload("DEFAULT "))
        decisions = json.loads(payload("DECISIONS "))
        check(set(decisions) == {name + ".in" for name in cases}, "incomplete Godot decisions")
        for name, data in cases.items():
            digest = hashlib.sha256(data).hexdigest()
            check(decisions[name + ".in"] == (digest if name in valid else None), f"Godot decision for {name}")
            if name in valid:
                check((folder / (name + ".in.out")).read_bytes() == data, f"Godot round trip {name}")
        origin = (folder / "origin.json").read_bytes()
        check(message(origin) == {"label": "编队é", "enabled": False, "delta": -LIMIT}, "Godot origin")
        digest = hashlib.sha256(origin).hexdigest()
        check(payload("ORIGIN ") == digest, "Godot origin digest")
        check(digest == "fec87a118f1e3755d33a1f166e0212b1c3e151ce15d4001dd6bd4c2f0f93e536",
              "Godot-origin golden digest")
        print(f"CON_INTEROP_PASS python_to_godot={len(valid)} rejected_both={len(invalid)} godot_to_python=1"
              f" upper_sha256={hashlib.sha256(wire).hexdigest()} origin_sha256={digest}")


if __name__ == "__main__":
    main()
