#!/usr/bin/env python3
"""Check committed Git diff against an execution task allow/exclude list.
Example: python3 development/check_diff.py TASK.json BASE CANDIDATE --repo /path/worktree
This is a review aid, not a filesystem permission sandbox. Does not check uncommitted edits.
"""
import argparse, json, subprocess, sys
from pathlib import Path, PurePosixPath

def match(path, scope): return path.startswith(scope) if scope.endswith('/') else path==scope

def safe(scope):
    p=PurePosixPath(scope)
    return bool(scope) and not p.is_absolute() and '..' not in p.parts and '\\' not in scope and ':' not in scope and scope.rstrip('/')==p.as_posix() and p.as_posix()!='.'

def main():
    p=argparse.ArgumentParser(description=__doc__); p.add_argument('task',type=Path); p.add_argument('base'); p.add_argument('candidate'); p.add_argument('--repo',type=Path,default=Path.cwd()); a=p.parse_args()
    t=json.loads(a.task.read_text(encoding='utf-8')); allow=t['allowed_paths']; exclude=t['excluded_paths']
    if not allow or not all(safe(x) for x in allow+exclude): raise ValueError('invalid allow/exclude paths')
    if t.get('base_commit') and t['base_commit']!=a.base: raise ValueError('base differs from task')
    # Resolve revisions first; do not treat user-supplied values as git flags.
    def rev(x): return subprocess.check_output(['git','-C',str(a.repo),'rev-parse','--verify','--end-of-options',x+'^{commit}'],text=True).strip()
    b,c=rev(a.base),rev(a.candidate)
    data=subprocess.check_output(['git','-C',str(a.repo),'diff','--name-only','-z','--no-renames',b,c,'--'])
    paths=[x.decode('utf-8','surrogateescape') for x in data.split(b'\0') if x]
    bad=[x for x in paths if not any(match(x,s) for s in allow) or any(match(x,s) for s in exclude)]
    for x in bad: print('DENIED:',repr(x))
    print(f'{"FAIL" if bad else "PASS"}: {len(paths)} changed paths, {len(bad)} outside authorization. Committed diff only.')
    return 1 if bad else 0

if __name__=='__main__':
    try: sys.exit(main())
    except (ValueError, KeyError, OSError, subprocess.CalledProcessError) as e: sys.exit(f'FAIL: {e}')
