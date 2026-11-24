"""Run independent P1 contract checks and the two project suites in a clean project."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import random
import shutil
import subprocess
import sys
import tempfile
import unicodedata


HERE = Path(__file__).resolve().parent
REPO = HERE.parents[4]
SUITES = {
    'QA-CANONICAL': ('probe.gd', 'QA_CANONICAL {count} candidates, mismatches=0'),
    'QA-SHAPES': ('shape_probe.gd', '0 failed'),
    'CON': ('tests/p1/contracts/run.gd', 'CON_CHECKS errors=0'),
    'PORTS': ('tests/p1/ports/run.gd', 'PASS P1-PORTS-V1'),
    'ORACLE': ('tests/p1/contracts/oracle.py', 'CON_ORACLE_REVERSE PASS'),
}


def wire(value):
    return json.dumps(value, separators=(',', ':'), ensure_ascii=False, sort_keys=True).encode()


def write_vectors(path):
    with path.open('w', encoding='ascii', newline='\n') as out:
        count = 0

        def case(label, raw, expected=None, strict=False):
            nonlocal count
            count += 1
            expected_hex = '-' if expected is None else expected.hex()
            digest = '-' if expected is None else hashlib.sha256(expected).hexdigest()
            print(label, raw.hex(), expected_hex, int(strict), digest, sep='\t', file=out)

        def text(label, value):
            data = wire(value)
            nfc = unicodedata.is_normalized('NFC', value)
            case(label, data, data if nfc else None, nfc)

        for code in range(0x110000):
            char = chr(code)
            sample_hangul = 0xac00 <= code <= 0xd7a3 and code % 17 == 0
            if unicodedata.decomposition(char) or unicodedata.combining(char) or sample_hangul:
                text(f'single-{code:x}', char)
                nfd = unicodedata.normalize('NFD', char)
                if nfd != char:
                    text(f'decomposed-{code:x}', nfd)
        randomizer = random.Random(241124)
        bases = list('AeÉàȩ숙漢字😀') + list(map(chr, range(0x1100, 0x1113)))
        marks = [chr(i) for i in range(0x110000) if unicodedata.combining(chr(i))]
        for index in range(1600):
            string = randomizer.choice(bases) + ''.join(randomizer.choices(marks, k=randomizer.randint(1, 6)))
            text(f'marks-{index}', string)
            text(f'NFC-marks-{index}', unicodedata.normalize('NFC', string))
        for value in ['', '\0', '\0a\0', '⃝\0\0é', 'abc😀漢字',
                      [True, None, -(2**53-1), 2**53-1, {'!': '\r\f\v\t\b\n\x7f\\"'}], [], {}]:
            data = wire(value)
            case('roundtrip', data, data, True)
        for raw in [b'{"x":1,"x":2}', b'{"x":1,"\\u0078":1}', b'1.0', b'1e0', b'01', b'NaN',
                    b'Infinity', b'9007199254740992', b'-9007199254740992', b'{"a":0,}', b'[0,]',
                    b'"\\ud800"', b'"\\udc00"', b'{"":0}', b'{"\\u0000":0}', b'null null',
                    b'{"a":true}\ntrash', b'"\\q"', b'"\\u0++1"', b'"\\u+000"', b'"e\\u0301"',
                    b'\xef\xbb\xbfnull', b'"\xe2\x82"', b'"\xc0\xaf"', b'"\xff"', b'"\xed\xa0\x80"', b'"\x00"']:
            case('reject', raw)
        for raw, value in [(b'-0', 0), (b'{"b":2, "a":1}', {'a': 1, 'b': 2}),
                           (b'"\\ud83d\\ude00"', '😀'), (b'"\\/"', '/'), (b' \r\ntrue', True)]:
            case('source-only', raw, wire(value))
        return count


def prepare(project, game, overlays):
    shutil.copy2(game / 'project.godot', project / 'project.godot')
    for source in [game, *overlays]:
        for group in ('contracts', 'tests/p1/contracts', 'tests/p1/ports'):
            folder = source / group
            if folder.is_dir():
                shutil.copytree(folder, project / group, dirs_exist_ok=True)
    for probe in ('probe.gd', 'shape_probe.gd'):
        shutil.copy2(HERE / probe, project / probe)
    return write_vectors(project / 'vectors.tsv')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot', required=True, help='Godot 4.7.2 Standard console executable')
    parser.add_argument('--game', type=Path, default=REPO / 'game')
    parser.add_argument('--overlay', action='append', type=Path, default=[], help='candidate game/ directory')
    parser.add_argument('--suite', action='append', choices=SUITES, help='default runs all suites')
    options = parser.parse_args()
    results = []
    with tempfile.TemporaryDirectory(prefix='p1-contract-qa-') as scratch:
        project = Path(scratch)
        count = prepare(project, options.game, options.overlay)
        print(f'Python UCD {unicodedata.unidata_version} | seed 241124 | {count} vectors', flush=True)
        env = os.environ | {'APPDATA': scratch, 'LOCALAPPDATA': scratch}
        for name in options.suite or SUITES:
            script, marker = SUITES[name]
            command = [options.godot, '--headless', '--log-file', str(project / 'godot.log'),
                       '--path', scratch, '--script', 'res://' + script]
            runner = 'Godot'
            if name == 'ORACLE':
                runner = 'Python'
                command = [sys.executable, '-X', 'utf8', str(project / script),
                           '--godot', options.godot, '--path', scratch]
            outcome = subprocess.run(command, capture_output=True, timeout=100, env=env)
            log = (outcome.stdout + outcome.stderr).decode('utf-8', 'replace')
            unexpected = 'ERROR:' in log or 'SCRIPT ERROR' in log
            passed = outcome.returncode == 0 and marker.format(count=count) in log and not unexpected
            results.append(passed)
            print(log.strip())
            print(f'{name} {runner} exit={outcome.returncode} | {"PASS" if passed else "FAIL"}', flush=True)
    return 0 if all(results) else 1


if __name__ == '__main__':
    raise SystemExit(main())
