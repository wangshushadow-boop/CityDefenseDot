"""Validate the project's static dependency boundaries and MUST release evidence."""
import argparse
import csv
from graphlib import CycleError, TopologicalSorter
import json
from pathlib import Path
import posixpath
import re
import sys


ROOT = Path(__file__).resolve().parents[1]
CODE = {".gd", ".tscn", ".tres"}
TOKENS = re.compile(r'''(?s:""".*?"""|'{3}.*?'{3})|"(?:\\.|[^"\\\n])*"|'(?:\\.|[^'\\\n])*'|#[^\n]*|[A-Za-z_]\w*|[^\s]''')
CONST_STRING = re.compile(r'''(?m)^[ \t]*const\s+(\w+)\s*(?::\s*String\s*)?:?=[ \t]*("[^"\n]*"|'[^'\n]*')[ \t]*(?:\#[^\n]*)?$''')
FACADES = {
    "core/runtime.gd", "shared/definitions/registry.gd", "shared/inventory/inventory.gd",
    "shared/rules/numeric_policy.gd", "campaign/runtime.gd", "mission/runtime/runtime.gd",
    "application/game_session.gd", "infrastructure/content/compiler.gd",
    "infrastructure/engine/adapter.gd", "infrastructure/persistence/save_service.gd",
    "infrastructure/telemetry/diagnostics.gd",
}
SHARED = {"definitions", "inventory", "rules"}
PURE = {"contracts", "core", "campaign", "mission", "application"} | SHARED
ALLOWED = {
    "contracts": set(), "core": {"contracts"}, "definitions": {"contracts"},
    "inventory": {"contracts", "core", "definitions"}, "rules": {"contracts", "core", "definitions"},
    "campaign": {"contracts", "core"} | SHARED, "mission": {"contracts", "core"} | SHARED,
    "application": {"contracts", "core", "campaign", "mission"},
    "infrastructure": {"contracts", "core", "definitions"},
    "presentation": {"contracts", "application", "multiplayer", "infrastructure"},
    "multiplayer": {"contracts", "core", "application", "mission", "infrastructure"},
    "addons": {"contracts", "infrastructure"},
}


def group(path):
    parts = path.split("/")
    return parts[1] if parts[0] == "shared" and len(parts) > 1 else parts[0]


def module(path):
    parts = path.split("/")
    if len(parts) > 2 and parts[0] in {"campaign", "mission", "infrastructure", "shared", "presentation", "addons"}:
        return "/".join(parts[:2])
    return group(path)


def permitted(caller, target):
    if module(caller) == module(target):
        return True
    src, dst = group(caller), group(target)
    if src == dst and src in {"campaign", "mission", "infrastructure", "presentation"}:
        return "/ports/" in target or target in FACADES
    if dst not in ALLOWED and dst != "bootstrap":
        return False
    if src != "bootstrap" and dst not in ALLOWED.get(src, set()):
        return False
    return dst == "contracts" or target in FACADES or "/ports/" in target


def resource_refs(parts, is_script, pure, constants):
    if not is_script:
        i = 0
        while i < len(parts):
            if parts[i:i+2] == ["[", "ext_resource"]:
                while i < len(parts) and parts[i] != "]":
                    if parts[i] in {"path", "uid"} and parts[i+1:i+2] == ["="]:
                        yield parts[i+2].strip('"')
                    i += 1
            i += 1
        return
    for i, token in enumerate(parts):
        if token == "extends" and i + 1 < len(parts) and parts[i+1].startswith(('"', "'")):
            yield parts[i+1][1:-1]
        if token not in {"load", "preload", "load_threaded_request"} or parts[i+1:i+2] != ["("]:
            continue
        arg = parts[i+2] if i+2 < len(parts) else ""
        arg = constants.get(arg, arg)
        if arg.startswith(('"', "'")) and parts[i+3:i+4] in ([")"], [","]):
            yield arg[1:-1]
        elif pure:
            yield None


def dependencies(game):
    paths = sorted(p for p in game.rglob("*") if p.suffix in CODE and
                   not any(n.startswith(".") or n == "tests" for n in p.relative_to(game).parts))
    tokens = {}
    constants = {}
    names = {}
    uids = {}
    issues = []
    for path in paths:
        key = path.relative_to(game).as_posix()
        # GDScript comments and strings must not manufacture class references.
        source = path.read_text("utf-8-sig")
        constants[key] = dict(CONST_STRING.findall(source))
        parts = [t for t in TOKENS.findall(source) if not t.startswith("#")]
        tokens[key] = parts
        sidecar = Path(str(path) + ".uid")
        header = re.search(r'\buid="(uid://[a-z0-9]+)"', source.partition("\n")[0]) if path.suffix != ".gd" else None
        uid = sidecar.read_text("utf-8-sig").strip() if sidecar.is_file() else header[1] if header else None
        if uid:
            if uid in uids:
                issues.append(f"{key}: duplicate resource UID {uid}")
            uids[uid] = key
        if "class_name" in parts:
            pos = parts.index("class_name")
            if pos + 1 < len(parts):
                name = parts[pos + 1]
                if name in names:
                    issues.append(f"{key}: duplicate global class {name}")
                names[name] = key
    graph = {p: set() for p in tokens}
    for path, parts in tokens.items():
        targets = set()
        for i, token in enumerate(parts):
            if token in names and names[token] != path:
                targets.add(names[token])
            elif group(path) in PURE and token == "extends" and parts[i+1:i+2] in (["Node"], ["Node2D"], ["Node3D"], ["Control"]):
                issues.append(f"{path}: domain extends scene node {parts[i+1]}")
        for ref in resource_refs(parts, path.endswith(".gd"), group(path) in PURE, constants[path]):
            if ref is None:
                issues.append(f"{path}: computed resource load in a domain")
            elif ref.startswith("uid://"):
                if ref not in uids:
                    issues.append(f"{path}: unresolved resource {ref}")
                else:
                    targets.add(uids[ref])
            elif Path(ref).suffix in CODE:
                targets.add(posixpath.normpath(ref[6:] if ref.startswith("res://") else
                                               posixpath.join(posixpath.dirname(path), ref)))
        for target in targets:
            if target not in graph:
                issues.append(f"{path} -> {target}: missing or outside production resources")
                continue
            graph[path].add(target)
            if not permitted(path, target):
                issues.append(f"{path} -> {target}: forbidden static dependency")
    if not graph:
        issues.append("no production code to check")
    modules = {module(p): set() for p in graph}
    for path, targets in graph.items():
        modules[module(path)].update(module(t) for t in targets if module(t) != module(path))
    for label, edges in (("files", graph), ("modules", modules)):
        try:
            tuple(TopologicalSorter(edges).static_order())
        except CycleError as error:
            issues.append(f"{label} cycle: " + " -> ".join(error.args[1]))
    return issues


def rows(path):
    with path.open(encoding="utf-8-sig", newline="") as stream:
        return list(csv.DictReader(stream))


def mentions_pass(path, expected):
    if path.suffix.lower() == ".json":
        try:
            data = json.loads(path.read_bytes())
        except (ValueError, UnicodeError):
            return False
        items = data.get("results", [data]) if isinstance(data, dict) else data
        if not isinstance(items, list) or isinstance(data, dict) and not successful(data):
            return False
        matched = [row for row in items if isinstance(row, dict)
                   and expected in [row.get(key) for key in ("id", "test_id", "requirement_id", "scenario_id")]]
        return bool(matched) and all(row.get("status") == "PASS" and successful(row) for row in matched)
    if path.suffix.lower() not in {".log", ".md", ".txt"}:
        return False
    ident = re.escape(expected)
    text = path.read_text("utf-8-sig", errors="replace")
    exits = re.findall(r"\b(?:exit(?:_code)?|returncode|rc)[ \t]*[=:]?[ \t]*(-?\d+)\b", text, re.I)
    if any(int(code) != 0 for code in exits):
        return False
    if re.search(rf"^(?:FAIL(?:\s|$)|SCRIPT ERROR|ERROR:|{ident}\s+(?:FAIL|NOT_RUN|BLOCKED|PARTIAL)\b)", text, re.M):
        return False
    return bool(re.search(rf"^(?:{ident}[ \t]+PASS|PASS[ \t]+{ident})[ \t]*$", text, re.M))


def successful(row):
    return row.get("status", "PASS") == "PASS" and all(
        type(row[key]) is int and row[key] == 0 for key in ("exit_code", "returncode") if key in row)


def evidence(root, field, expected):
    for item in field.split(";"):
        path = (root / item.strip()).resolve()
        if not path.is_relative_to(root) or not path.is_file() or not mentions_pass(path, expected):
            return False
    return True


def end_to_end(root):
    matrix = root / "docs/testing/acceptance_matrix.md"
    required = {f"AT-{number:02}" for number in range(1, 17)}
    seen = set()
    issues = []
    for line in matrix.read_text("utf-8-sig").splitlines():
        cells = [cell.strip() for cell in line.strip().strip("|").split("|")]
        if not cells or cells[0] not in required:
            continue
        name = cells[0]
        if name in seen:
            issues.append(f"{name}: duplicate full scenario")
        seen.add(name)
        status = cells[4] if len(cells) > 4 else ""
        links = re.findall(r"\[[^\]]*\]\(([^)]+)\)", " ".join(cells[4:]))
        if not re.fullmatch(r"PASS(?:\s+\[.*)?", status) or not links:
            issues.append(f"{name}: complete scenario PASS and linked evidence required")
        elif not all(evidence(root, str(matrix.parent / link), name) for link in links):
            issues.append(f"{name}: unavailable scenario evidence")
    return issues + [f"{item}: full scenario missing" for item in sorted(required - seen)]


def release(root):
    root = root.resolve()
    testing = root / "docs/testing"
    matrix = rows(testing / "requirements_trace.csv")
    cases = rows(testing / "test_cases.csv")
    tests = {r["test_id"]: r for r in cases}
    graph = json.loads((root / "development/planning/task_graph.json").read_text("utf-8"))
    required = set(next(p["requirement_ids"] for p in graph["packages"] if p["id"] == "GATE-P7"))
    must = [r for r in matrix if r["scope"] == "MUST"]
    issues = []
    if not required or len(tests) != len(cases) or len(required) != len(must) or required != {r["requirement_id"] for r in must}:
        issues.append("MUST matrix missing, duplicated or different from GATE-P7")
    for record in must:
        rid = record["requirement_id"]
        if (record["implementation_status"] not in {"VERIFIED", "IMPLEMENTED"} or record["test_status"] != "PASS"
                or not record["owner"].strip() or not evidence(root, record["evidence"], rid)):
            issues.append(f"{rid}: implementation, responsible owner, PASS and evidence required")
        for tid in record["test_ids"].split(";"):
            case = tests.get(tid.strip())
            if not case or case["status"] != "PASS" or not evidence(root, case["evidence"], tid.strip()):
                issues.append(f"{rid}/{tid}: missing, not PASS, or test evidence unavailable")
    return issues + end_to_end(root)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("gate", choices=["dependencies", "release"])
    parser.add_argument("--root", type=Path, default=ROOT)
    args = parser.parse_args()
    issues = dependencies(args.root / "game") if args.gate == "dependencies" else release(args.root)
    for issue in issues:
        print(issue)
    print(f"{args.gate} {'FAIL' if issues else 'PASS'} issues={len(issues)}")
    return int(bool(issues))


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (ValueError, KeyError, StopIteration, OSError) as error:
        sys.exit(f"gate failed: {error}")
