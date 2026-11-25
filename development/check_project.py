#!/usr/bin/env python3
"""Project document/plan integrity checks. Python 3.11+, standard library only.
No game builds, tests, agents or state changes are performed.
"""
import argparse, csv, hashlib, json, re, subprocess, sys, tomllib
from pathlib import Path, PurePosixPath
ROOT=Path(__file__).resolve().parents[1]

def require(ok, msg):
    if not ok: raise ValueError(msg)

def load(rel):
    return json.loads((ROOT/rel).read_text(encoding='utf-8'))

def rows(rel):
    with (ROOT/rel).open(encoding='utf-8-sig', newline='') as f: return list(csv.DictReader(f))

def safe_rel(s):
    p=PurePosixPath(s)
    return bool(s) and not p.is_absolute() and not ('..' in p.parts or '\\' in s or ':' in s) and s.rstrip('/')==p.as_posix() and p.as_posix()!='.'

def match(path, root):
    return path.startswith(root) if root.endswith('/') else path==root

def acyclic(byid):
    visiting=set(); visited=set()
    def visit(i):
        require(i in byid, f'unknown dependency {i}')
        require(i not in visiting, f'dependency cycle at {i}')
        if i in visited: return
        visiting.add(i)
        for d in byid[i]['depends_on']: visit(d)
        visiting.remove(i); visited.add(i)
    for i in byid: visit(i)

def validate():
    subprocess.run([sys.executable,str(ROOT/'docs/architecture/check_mirror.py')],check=True)
    reg=load('docs/architecture/module_registry.json'); mods={m['id']:m for m in reg['modules']}
    require(reg['project']=='recollection','wrong project name')
    require(hashlib.sha256((ROOT/reg['original_source_archive']).read_bytes()).hexdigest()==reg['original_source_sha256'],'historical source archive modified')
    entries=reg['directory_entries']; entry_paths={e['code_path']:e for e in entries}
    for e in entries:
        p=ROOT/e['code_path']/'README.md'; require(p.is_file(), f'missing code navigation {p}')
        # Check the actual resolved navigation link, not only the file name.
        links=re.findall(r'\]\(([^\s)]+)\)',p.read_text(encoding='utf-8'))
        require(any((p.parent/l).resolve()==(ROOT/e['doc']).resolve() for l in links),'wrong code README link: '+e['code_path'])
    owners=load('development/planning/module_owners.json')['module_owners']; require(set(owners)==set(mods),'module ownership coverage mismatch')
    for mid,m in mods.items():
        o=owners[mid]; require(o['canonical_spec']==m['doc'] and o['allowed_module_roots']==m['code_paths'],f'owner paths mismatch {mid}')
        expected={e['code_path'] for e in entries for a in m['code_paths'] if e['code_path'].startswith(a) and e['code_path']!=a and e['module_id'] not in (mid,None)}
        require(set(o['excluded_independent_module_roots'])==expected, f'owner exclusions mismatch {mid}')
    testrows=rows('docs/testing/test_cases.csv'); testids={r['test_id']:r for r in testrows}
    reqrows=rows('docs/testing/requirements_trace.csv'); reqids={r['requirement_id']:r for r in reqrows}
    graph=load('development/planning/task_graph.json'); packages=graph['packages']; byid={p['id']:p for p in packages}
    require(len(byid)==len(packages),'duplicate package id')
    stages=[f'P{i}' for i in range(9)]
    gateids={f'GATE-{s}' for s in stages}
    require({p['id'] for p in packages if p['kind']=='GATE'}==gateids,'stage gate mismatch')
    for p in packages:
        require(p['stage'] in stages and p['kind'] in ('PACKAGE','GATE'),f'bad package type or stage {p["id"]}')
        require(p['scope'] and p['acceptance'],f'missing package scope/acceptance {p["id"]}')
        require(set(p['module_ids'])<=mods.keys(),f'unknown module in {p["id"]}')
        require(set(p['spec_paths'])=={mods[m]['doc'] for m in p['module_ids']},f'spec mismatch {p["id"]}')
        require(set(p['candidate_test_ids'])<=testids.keys(),f'unknown tests {p["id"]}')
        require(set(p['requirement_ids'])<=reqids.keys(),f'unknown requirements {p["id"]}')
        for dep in p['depends_on']:
            require(dep in byid and int(byid[dep]['stage'][1:])<=int(p['stage'][1:]),f'invalid/forward dependency {p["id"]}: {dep}')
    acyclic(byid)
    def ancestors(i):
        seen=set(); todo=list(byid[i]['depends_on'])
        while todo:
            d=todo.pop()
            if d not in seen: seen.add(d); todo.extend(byid[d]['depends_on'])
        return seen
    for s in stages:
        gid=f'GATE-{s}'; require({p['id'] for p in packages if p['stage']==s and p['kind']=='PACKAGE'}<=ancestors(gid),f'gate misses packages: {s}')
    for p in packages:
        if p['stage']!='P0': require(f'GATE-P{int(p["stage"][1:])-1}' in ancestors(p['id']),f'previous gate missing: {p["id"]}')
    require(set(mods)=={m for p in packages if p['kind']=='PACKAGE' and p['stage']!='P0' for m in p['module_ids']},'implementation packages do not cover all modules')
    require(set(byid['GATE-P7']['requirement_ids'])=={r['requirement_id'] for r in reqrows if r['scope']=='MUST'},'P7 MUST scope mismatch')
    require(set(byid['GATE-P8']['requirement_ids'])=={r['requirement_id'] for r in reqrows if r['scope']=='EXT'},'P8 EXT scope mismatch')
    # Execution task files can be added by coordinator. Templates are not active tasks.
    execs={}
    for path in sorted((ROOT/'development/planning/tasks').glob('*.json')):
        t=json.loads(path.read_text(encoding='utf-8')); i=t['id']; require(i not in byid and i not in execs and path.stem==i,f'bad execution ID {path.name}')
        require(t['kind']=='EXECUTION' and t['schema_version']==1,f'bad execution type {i}')
        parent=t['parent']; require(parent in byid and byid[parent]['kind']=='PACKAGE',f'unknown task parent {i}')
        require(t['stage']==byid[parent]['stage'],f'task stage mismatch {i}')
        mid=t['module_id']; require(mid is None or mid in byid[parent]['module_ids'],f'unknown task owner {i}')
        if mid is not None: require(t['spec']==mods[mid]['doc'],f'wrong canonical spec {i}')
        require(safe_rel(t['spec']) and (ROOT/t['spec']).is_file(),f'missing spec {i}')
        require(t['title'] and t['scope'] and t['acceptance'] and t['allowed_paths'],f'empty task scope/acceptance {i}')
        require(set(t['requirements'])<=reqids.keys() and set(t['acceptance_test_ids'])<=testids.keys(),f'unknown requirement/test {i}')
        require(t['contract_changes'] in ('forbidden','approved_adr'),f'bad contract policy {i}')
        for key in ('allowed_paths','excluded_paths'):
            require(all(safe_rel(x) for x in t[key]),f'unsafe paths {i}')
        if mid is not None:
            for a in t['allowed_paths']:
                # Module tasks may explicitly add a narrow test scope, their own design, or a report.
                # P0 isolated experimental paths are separate from production ownership.
                is_test = a.startswith('game/tests/') and a != 'game/tests/'
                is_experiment = t['stage']=='P0' and (a.startswith('test_scenarios/p0/') or a.startswith('native/benchmarks/p0/'))
                is_report = a.startswith('development/reports/') and a != 'development/reports/'
                is_own_doc = any(match(a, 'docs/systems/'+root) for root in owners[mid]['allowed_module_roots'])
                is_own_code = any(match(a, root) for root in owners[mid]['allowed_module_roots'])
                if is_own_code or is_own_doc:
                    code_a = a.removeprefix('docs/systems/') if is_own_doc else a
                    nearest = max((e for e in entries if match(code_a, e['code_path'])), key=lambda e:len(e['code_path']), default=None)
                    require(nearest and nearest['module_id']==mid, f'direct write into independent module: {a}: {i}')
                    if a.endswith('/'):
                        for e in entries:
                            b = ('docs/systems/' if is_own_doc else '')+e['code_path']
                            if b.startswith(a) and b!=a and e['module_id'] not in (mid,None):
                                require(any(match(b,x) for x in t['excluded_paths']),f'parent scope must exclude independent child {b}: {i}')
                else:
                    require(is_test or is_experiment or is_report, f'foreign or overbroad write scope {a}: {i}')
                for e in entries:
                    b=e['code_path']
                    if a.endswith('/') and b.startswith(a) and e['module_id'] not in (mid,None) and any(b.startswith(r) for r in owners[mid]['allowed_module_roots']):
                        require(any(match(b,x) for x in t['excluded_paths']),f'parent scope must exclude independent child {b}: {i}')
        else:
            for a in t['allowed_paths']:
                require((a.startswith('development/') and a not in ('development/','development/state/') and not a.startswith('development/state/')) or a.startswith('docs/architecture/decisions/') or (t['stage']=='P0' and (a.startswith('test_scenarios/p0/') or a.startswith('native/benchmarks/p0/'))), f'non-module task scope too broad: {a}: {i}')
        execs[i]=t
    full={**byid,**execs}; acyclic(full)
    for t in execs.values():
        parent=byid[t['parent']]
        seen=set(); todo=list(t['depends_on'])
        while todo:
            d=todo.pop()
            if d not in seen: seen.add(d); todo.extend(full[d]['depends_on'])
        require(set(parent['depends_on'])<=seen,f'package prerequisite mismatch {t["id"]}')
        require(t['parent'] not in seen,f'execution task cannot depend on its own package: {t["id"]}')
    state=load('development/state/tasks.json')['tasks']; require(set(state)==set(full),'task state coverage mismatch')
    # The owner allowed only the character work package to start against the archived P2 build.
    waiver=load('development/state/project.json').get('p3_authorization', {})
    def available(task, dependency):
        if state[dependency]['status']=='DONE': return True
        return (dependency=='GATE-P2' and (task=='P3-CHR' or execs.get(task,{}).get('parent')=='P3-CHR')
                and waiver.get('scope')=='P3-CHR' and waiver.get('waived_dependency')==dependency
                and waiver.get('by')=='项目负责人' and bool(waiver.get('decision'))
                and waiver.get('evidence')=='docs/architecture/decisions/ADR-016-character-slice.md'
                and (ROOT / waiver['evidence']).is_file())
    statuses={'PLANNED','READY','IN_PROGRESS','TESTING','REVIEW','INTEGRATING','DONE','BLOCKED'}
    for i,s in state.items():
        require(s['status'] in statuses,f'unknown task status {i}')
        p=full[i]
        if i in byid and p['kind']=='PACKAGE': require(set(s['child_ids'])=={k for k,t in execs.items() if t['parent']==i},f'child state mismatch {i}')
        if s['status'] in {'READY','IN_PROGRESS','TESTING','REVIEW','INTEGRATING','DONE'}:
            require(all(available(i,d) for d in p['depends_on']),f'active/done with unfinished dependency {i}')
            if i in execs:
                require(s.get('base_commit') and execs[i].get('base_commit')==s['base_commit'] and execs[i].get('worktree'),f'missing task base commit/worktree {i}')
        if s['status']=='DONE':
            require(s.get('evidence'),f'DONE missing evidence {i}')
            if p['kind']=='PACKAGE': require(s['child_ids'] and all(state[c]['status']=='DONE' for c in s['child_ids']),f'package DONE without completed children {i}')
            if p.get('approval_required'): require(s.get('approval'),f'DONE requires human approval {i}')
    project=load('development/state/project.json'); require(project['project']=='recollection','wrong state project')
    require(set(project['stage_status'])==set(stages),'stage state mismatch')
    require(project['active_stage'] is None or project['active_stage'] in stages,'unknown active stage')
    for s in stages:
        if project['stage_status'][s]=='DONE': require(state[f'GATE-{s}']['status']=='DONE',f'phase DONE without gate {s}')
    module_state=load('development/state/modules.json')['modules']; require(set(module_state)==set(mods),'module state coverage mismatch')
    for mid,v in module_state.items(): require(set(v['work_package_ids'])=={p['id'] for p in packages if p['kind']=='PACKAGE' and mid in p['module_ids']},f'wrong module task map {mid}')
    for lock in load('development/state/locks.json')['locks']:
        require(lock['task_id'] in execs,f'lock not execution task {lock["task_id"]}')
    for row in testrows:
        if row['status']=='PASS': require(row.get('evidence'),f'PASS missing evidence {row["test_id"]}')
    cfg=tomllib.loads((ROOT/'.codex/config.toml').read_text(encoding='utf-8')); require(cfg['agents']['enabled'] is True and cfg['agents']['max_concurrent_threads_per_session']>0,'bad Codex agent settings')
    roles={}
    for path in (ROOT/'.codex/agents').glob('*.toml'):
        a=tomllib.loads(path.read_text(encoding='utf-8')); require(all(a.get(k) for k in ('name','description','developer_instructions')),f'bad role TOML {path}')
        require(a['name'] not in roles,f'duplicate agent name {a["name"]}'); roles[a['name']]=a
    print(f'PASS: {len(entries)} code navigation directories; {len(mods)} owner boundaries; original archive integrity')
    print(f'PASS: {len(packages)} graph nodes ({len(packages)-len(gateids)} work packages + {len(gateids)} gates), acyclic, {len(execs)} registered execution tasks')
    print(f'PASS: module/requirement/test references, state records, {len(roles)} custom role TOML files parse')
    print('Structure checks only. Codex runtime, game code, real tests and performance NOT verified by this script.')
    return packages,state,project

def main():
    ap=argparse.ArgumentParser(description=__doc__); ap.add_argument('--ready',choices=[f'P{i}' for i in range(9)],help='list dependency-satisfied planning packages; not an authorization or execution')
    args=ap.parse_args(); packages,state,project=validate()
    if args.ready:
        phase=args.ready
        print(f'Planning candidates for {phase}; authorized stage = {project["active_stage"] or "NONE"}.')
        for p in packages:
            if p['stage']==phase and state[p['id']]['status'] in ('PLANNED','READY') and all(available(i,d) for d in p['depends_on']):
                print(f'  {p["id"]}: {p["title"]} ({p["kind"]})')
        print('Refine execution tasks, check actual permissions and obtain authorization before starting.')

if __name__=='__main__':
    try: main()
    except (ValueError, KeyError, OSError, subprocess.CalledProcessError) as e: sys.exit(f'FAIL: {e}')
