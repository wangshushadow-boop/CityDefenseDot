#!/usr/bin/env python3
"""Verify documentation layout and traceability (stdlib only; not a game test).
Run from any directory: python3 docs/architecture/check_mirror.py
"""
import csv
import hashlib
import json
import re
from pathlib import Path, PurePosixPath

ROOT = Path(__file__).resolve().parents[2]
REGISTRY = ROOT / 'docs/architecture/module_registry.json'

def require(condition, message):
    if not condition:
        raise ValueError(message)

def read_csv(name):
    with (ROOT / 'docs/testing' / name).open(encoding='utf-8-sig', newline='') as f:
        return list(csv.DictReader(f))

def check():
    registry = json.loads(REGISTRY.read_text(encoding='utf-8'))
    mods = registry['modules']
    by_id = {m['id']: m for m in mods}
    require(len(by_id) == len(mods), 'duplicate module ID')
    require(len({m['doc'] for m in mods}) == len(mods), 'duplicate canonical SDD')
    require(hashlib.sha256((ROOT/'docs/game_design.md').read_bytes()).hexdigest() == registry['source_sha256'], 'source baseline hash mismatch: review baseline changes explicitly')
    entries = registry['directory_entries']
    by_path = {e['code_path']: e for e in entries}
    require(len(entries) == len(by_path), 'duplicate directory mapping')
    require(len({e['doc'] for e in entries}) == len(entries), 'duplicate directory entrypoint')
    for e in entries:
        path = e['code_path']
        p = PurePosixPath(path)
        require(not p.is_absolute() and '..' not in p.parts and path.endswith('/'), f'invalid code path: {path}')
        require(e['doc'] == f'docs/systems/{path}README.md', f'non-mirror document: {path}')
        require((ROOT/e['doc']).is_file(), f'missing document: {e["doc"]}')
        parent = str(p.parent)
        if parent != '.':
            require(parent+'/' in by_path, f'missing parent index: {parent}')
        require(e['kind'] in {'canonical','alias','inherited','index'}, f'invalid entry kind: {path}')
        if e['kind'] == 'index':
            require(e['module_id'] is None and e['canonical_doc'] is None, f'invalid group ownership: {path}')
        else:
            require(e['module_id'] in by_id, f'unknown owner: {path}')
            require(e['canonical_doc'] == by_id[e['module_id']]['doc'], f'bad owner document: {path}')
    require({e['doc'] for e in entries if e['kind']=='canonical'} == {m['doc'] for m in mods}, 'canonical entries do not match module list')
    for m in mods:
        paths, eps = m['code_paths'], m['entrypoints']
        require(len(paths)==len(eps)>0, f'bad entrypoint list: {m["id"]}')
        require(m['code']==paths[0] and m['doc']==eps[0], f'bad primary path: {m["id"]}')
        for i,(path,doc) in enumerate(zip(paths,eps)):
            require(path in by_path, f'missing module path: {path}')
            e=by_path[path]
            require(e['doc']==doc and e['module_id']==m['id'] and e['kind']==('canonical' if i==0 else 'alias'), f'module entry mismatch: {m["id"]}, {path}')
    expected = {e['doc'] for e in entries}|{'docs/systems/README.md'}
    actual = {p.relative_to(ROOT).as_posix() for p in (ROOT/'docs/systems').rglob('README.md')}
    require(expected == actual, f'unregistered or missing mirror README: {sorted(expected ^ actual)}')
    tests=read_csv('test_cases.csv')
    by_test={t['test_id']:t for t in tests}
    require(len(by_test)==len(tests), 'duplicate test ID')
    for t in tests:
        require(t['module'] in by_id, f'unknown test module: {t["test_id"]}')
        m=by_id[t['module']]
        require(t['document_path']==m['doc'] and t['code_paths']==';'.join(m['code_paths']), f'test path mismatch: {t["test_id"]}')
    trace=read_csv('requirements_trace.csv')
    require(len({r['requirement_id'] for r in trace})==len(trace), 'duplicate requirement ID')
    for r in trace:
        mid=r['modules'].split(';'); docs=r['document_paths'].split(';'); tids=r['test_ids'].split(';')
        require(all(m in by_id for m in mid), f'unknown module in requirement {r["requirement_id"]}')
        require(set(docs)=={by_id[m]['doc'] for m in mid}, f'document path mismatch: {r["requirement_id"]}')
        require(all(t in by_test and by_test[t]['module'] in mid for t in tids), f'unknown/mismatched test in requirement {r["requirement_id"]}')
    links=0
    for f in ROOT.rglob('*.md'):
        if f==ROOT/'docs/game_design.md':
            continue  # immutable input; it contains the original external references and examples
        for m in re.finditer(r'\]\(([^\s)]+)\)',f.read_text(encoding='utf-8')):
            target=m[1].split('#')[0]
            if not target or re.match(r'^[A-Za-z][A-Za-z0-9+.-]*:',target):
                continue
            require((f.parent/target).exists(), f'broken local link: {f.relative_to(ROOT)} -> {target}')
            links+=1
    print(f'PASS: {len(mods)} canonical SDDs, {len(entries)} directory mappings, {len(entries)-len(mods)} navigation/alias entries')
    print(f'PASS: {len(trace)} requirement rows, {len(tests)} test rows, {links} local Markdown link occurrences')
    print('PASS: source baseline SHA-256 and registry/trace consistency')
    print('Documentation checks only; no game implementation or test execution verified.')

if __name__=='__main__':
    try:
        check()
    except (ValueError, KeyError, OSError) as exc:
        raise SystemExit(f'FAIL: {exc}')
