"""Run independent Python Unicode/JSON/SHA-256 vectors against production GDScript."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import random
import subprocess
import tempfile
import unicodedata as ucd


def canonical(value):
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode()


def nfc_vectors():
    # Every scalar with a decomposition, including all algorithmic Hangul
    # syllables and all compatibility-only mappings; pair against its NFD.
    strings = set()
    marks = []
    for cp in range(0x110000):
        ch = chr(cp)
        if ucd.combining(ch):
            marks.append(ch)
        if ucd.decomposition(ch) or 0xAC00 <= cp <= 0xD7A3:
            strings.update((ch, ucd.normalize("NFD", ch)))
    randomizer = random.Random(20261124)
    strings.update(("\u1100\u1161", "\u1100\u1161\u11A8", "\u1E0A\u0323",
                    "\u0301\u0323", "\u0301\u0308", "A\u0308\u0301", "\U0001F680"))
    for _ in range(2400):
        starter = randomizer.choice(["", "A", "é", "가", "𝅗", "猫"])
        s = starter + "".join(randomizer.choices(marks, k=randomizer.randrange(1, 9)))
        strings.update((s, ucd.normalize("NFC", s)))
    return [[s, ucd.is_normalized("NFC", s)] for s in sorted(strings)]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--godot", required=True)
    parser.add_argument("--path", type=Path, default=Path(__file__).resolve().parents[3])
    args = parser.parse_args()
    native = {"list": ["", ""], "nul": "\0é\0\0猫\0", "integer": 2**53-1,
              "astral": "🚀", "controls": "\b\t\n\f\r"}
    values = [None, False, True, -(2**53-1), 2**53-1, "한글é🚀", "\0",
              "\0é\0\0猫\0", ["", ""], ["\0"], "\0" * 3,
              "".join(chr(n) for n in range(32)), {"a": ["é", None]}, native]
    wire = [[b.decode(), hashlib.sha256(b).hexdigest()] for b in map(canonical, values)]
    with tempfile.TemporaryDirectory() as workspace:
        temp = Path(workspace)
        corpus = temp / "corpus.json"
        # The fixture transports noncanonical Unicode verbatim to the test adapter.
        corpus.write_text(json.dumps({"nfc": nfc_vectors(), "wire": wire}, ensure_ascii=False),
                          encoding="utf-8")
        output = temp / "godot-output.json"
        env = os.environ | {"APPDATA": workspace, "LOCALAPPDATA": workspace}
        run = subprocess.run([args.godot, "--headless", "--path", str(args.path),
                              "--log-file", str(temp / "oracle.log"), "--script",
                              "res://tests/p1/contracts/oracle.gd", "--", str(corpus), str(output)],
                             env=env, capture_output=True, timeout=90)
        text = (run.stdout + run.stderr).decode("utf-8", errors="replace")
        print(text.strip())
        if run.returncode or "errors=0" not in text or "ERROR:" in text:
            raise SystemExit(1)
        if output.read_bytes() != canonical(native):
            raise SystemExit("Godot -> Python: byte mismatch")
        print(f"CON_ORACLE_REVERSE PASS SHA256={hashlib.sha256(output.read_bytes()).hexdigest()} UCD={ucd.unidata_version}")


if __name__ == "__main__":
    main()
