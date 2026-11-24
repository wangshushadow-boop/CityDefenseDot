"""Regression fixtures for P1 CI gates. Nothing here is exported in production packages."""
import csv
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[4]
GATES = ROOT / "ci/gates.py"


class Gates(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory(prefix="p1-ci-fixture-")
        self.addCleanup(temp.cleanup)
        self.root = Path(temp.name)

    def put(self, path, data):
        path = self.root / path
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(data, encoding="utf-8")
        return path

    def run_gate(self, name, expected, text):
        proc = subprocess.run([sys.executable, "-B", str(GATES), name, "--root", self.root],
                              capture_output=True, encoding="utf-8")
        self.assertEqual(proc.returncode, expected, proc.stdout + proc.stderr)
        self.assertIn(text, proc.stdout)

    def test_dependency_edges(self):
        self.put("game/presentation/ui/widget.gd", "class_name MenuWidget\nextends Node\n")
        self.put("game/presentation/ui/widget.gd.uid", "uid://ciwidget\n")
        path = "game/campaign/runtime.gd"
        self.put(path, 'extends RefCounted\n# MenuWidget.new()\nconst LABEL = "historical.gd"\n')
        self.run_gate("dependencies", 0, "PASS")
        for expr in ('preload("res://presentation/ui/widget.gd")', 'load("../presentation/ui/widget.gd")',
                     'load("uid://ciwidget")', "MenuWidget.new()"):
            with self.subTest(expr=expr):
                self.put(path, f"extends RefCounted\nfunc enter():\n\treturn {expr}\n")
                self.run_gate("dependencies", 1, "campaign/runtime.gd -> presentation/ui/widget.gd")
        self.put(path, 'extends RefCounted\nconst LIVE = preload("uid://unknown")\n')
        self.run_gate("dependencies", 1, "unresolved resource uid://unknown")
        self.put(path, 'extends RefCounted\nconst LOC: String = "res://presentation/ui/" + "widget.gd"\nconst LIVE = preload(LOC)\n')
        self.run_gate("dependencies", 1, "computed resource load")
        self.put("game/campaign/world/ports/view.gd", "extends RefCounted\n")
        self.put("game/campaign/party/read.gd", 'extends "res://campaign/world/ports/view.gd"\n')
        self.put(path, "extends RefCounted\n")
        self.run_gate("dependencies", 0, "PASS")
        self.put(path, 'extends "other.gd"\n')
        self.put("game/campaign/other.gd", 'extends "runtime.gd"\n')
        self.run_gate("dependencies", 1, "files cycle")
        self.put(path, "extends RefCounted\n")
        self.put("game/campaign/bad.tscn", '[gd_scene format=3]\n[ext_resource type="Script" path="res://presentation/ui/widget.gd" id="1"]')
        self.run_gate("dependencies", 1, "campaign/bad.tscn -> presentation/ui/widget.gd")

    def csv(self, name, row):
        dest = self.put("docs/testing/" + name, "")
        with dest.open("w", encoding="utf-8", newline="") as output:
            writer = csv.DictWriter(output, fieldnames=list(row))
            writer.writeheader()
            writer.writerow(row)

    def test_release_fail_closed(self):
        self.put("development/planning/task_graph.json", json.dumps({"packages":[
            {"id":"GATE-P7","requirement_ids":["RQ-01"]}]}))
        self.csv("requirements_trace.csv", {"requirement_id":"RQ-01","scope":"MUST","test_ids":"T-X-01",
                 "implementation_status":"VERIFIED","owner":"tester","test_status":"PASS","evidence":"evidence.txt"})
        row = {"test_id":"T-X-01", "status":"PASS", "evidence":"test.json"}
        self.csv("test_cases.csv", row)
        self.put("evidence.txt", "RQ-01 PASS\n")
        self.put("test.json", json.dumps({"results":[{"id":"T-X-01","status":"PASS"}]}))
        matrix = []
        for i in range(1,17):
            name = f"AT-{i:02}"
            self.put(f"docs/testing/{name}.txt", name + " PASS\n")
            matrix.append(f"| {name} | step | outcome | RQ-01 | PASS [log]({name}.txt) |")
        matrix.append("| AT-17 | extension | outside base release | EXT | NOT_RUN |")
        self.put("docs/testing/acceptance_matrix.md", "\n".join(matrix))
        self.run_gate("release", 0, "release PASS")
        self.csv("test_cases.csv", row | {"status":"FAIL"})
        self.run_gate("release", 1, "RQ-01/T-X-01")
        self.csv("test_cases.csv", row)
        for body in ("", "  ", "T-X-01 FAIL\n", "T-OTHER PASS\n", "T-X-01 PASS\nT-X-01 FAIL\n",
                     "T-X-01 PASS\nPROCESS headless exit=1\n"):
            with self.subTest(body=body):
                self.put("proof.txt", body)
                self.csv("test_cases.csv", row | {"evidence":"proof.txt"})
                self.run_gate("release", 1, "RQ-01/T-X-01")
        self.csv("test_cases.csv", row | {"evidence":"absent.json"})
        self.run_gate("release", 1, "RQ-01/T-X-01")
        self.csv("test_cases.csv", row)
        self.put("test.json", json.dumps({"id":"T-X-01","status":"PASS","exit_code":1}))
        self.run_gate("release", 1, "RQ-01/T-X-01")
        self.put("test.json", json.dumps({"id":"T-X-01","status":"PASS","exit_code":0}))
        self.put("docs/testing/AT-10.txt", "AT-10-SLICE PASS")
        self.run_gate("release", 1, "AT-10: unavailable scenario evidence")
        self.put("docs/testing/AT-10.txt", "AT-10 PASS")
        self.put("docs/testing/acceptance_matrix.md", "\n".join(matrix[1:]))
        self.run_gate("release", 1, "AT-01: full scenario missing")


if __name__ == "__main__":
    unittest.main(verbosity=2)
