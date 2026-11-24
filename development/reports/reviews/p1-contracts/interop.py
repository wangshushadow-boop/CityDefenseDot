"""Cross-check the P1 public schemas with Python and the project's Godot build.

python interop.py --godot <executable> [--project <game-directory>]
"""

import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile


def canonical(value):
    return json.dumps(value, ensure_ascii=False, sort_keys=True,
                      separators=(",", ":"), allow_nan=False).encode("utf-8")


def fixtures():
    uuid = "b48883c0-79fb-4cd3-96fe-43bb44dfddbb"
    encounter_id = "encounter/" + uuid
    max_integer = 2**53 - 1
    max_index = 2**32 - 1
    handle = {"index": max_index, "generation": max_index}
    error = {
        "code": "InvalidArgument", "message_key": "error.invalid_argument",
        "field": "first\0next", "detail": {"reason": "臺é😀"}, "retryable": False,
    }
    event = {
        "event_id": "ev1", "scope_id": "s", "revision": max_integer, "tick": 0,
        "type": "ev", "payload": {"text": "你好"},
    }
    move = {
        "actor_handle": handle, "desired_direction": [0, 0, 1],
        "speed_fraction": 500000, "stance": None,
    }
    side = {
        "team_key": 0, "faction_id": "base:faction/a", "commander_hero_id": "hero/" + uuid,
        "roster_allocations": [],
    }
    source = {
        "source_party_id": "party/" + uuid, "troop_def_id": "base:troop/guard",
        "hero_id": None, "count": 1, "source_slot_range": [max_index, max_index + 1],
        "loadout_snapshot_id": "stock",
    }
    slot = {
        "source_slot_id": max_index, "end_status": "not_spawned", "wounded": False,
        "captor_team_key": None, "xp": 0,
    }
    result = {
        "schema_version": 1, "result_id": "r", "encounter_id": encounter_id,
        "mission_id": "m", "reservation_revision": 12, "outcome": "victory",
        "duration_ticks": 30, "winner_team_keys": [0], "objective_results": [],
        "slot_outcomes": [slot], "loot_claims": [], "hero_outcomes": [], "siege_changes": None,
        "reward_intents": [], "stats": {},
    }
    result["integrity_hash"] = hashlib.sha256(canonical(result)).hexdigest()
    return {
        "AgentHandle": handle, "DomainError": error, "EventEnvelope": event,
        "CommandEnvelope": {
            "command_id": "c", "actor_ref": "actor", "scope_id": "s",
            "expected_revision": None, "issued_tick": None, "sequence": None,
            "payload": {"n": -max_integer, "name": "A\0B"},
        },
        "CommandReceipt": {
            "command_id": "c", "status": "failed", "committed_revision": None,
            "errors": [error], "view_changes": [],
        },
        "QueryEnvelope": {"scope_id": "s", "visibility_context": {}, "payload": {"query": "units"}},
        "ReadModel": {"scope_id": "s", "revision": 3, "tick": None,
                      "content_hash": "ab"*32, "data": {"a": [1, 2]}},
        "SnapshotStamp": {"scope_id": "s", "revision": 4, "tick": None, "nav_revision": 0},
        "ChangeSet": {"expected_versions": [], "operations": [], "invariant_checks": [],
                      "committed_events": [event]},
        "IntentBatch": {"mission_id": "m", "source_tick": 0, "control_revision": 7, "inputs": [move]},
        "MoveIntent": move,
        "LookIntent": {"actor_handle": handle, "yaw": -3141593, "pitch": -1},
        "AttackIntent": {"actor_handle": handle, "input_phase": "start", "direction": "up",
                         "weapon_slot": 1, "target_hint": None},
        "BlockIntent": {"actor_handle": handle, "direction": "left", "held": True},
        "EquipIntent": {"actor_handle": handle, "slot": 3, "item_ref": None},
        "InteractionIntent": {"actor_handle": handle, "target_ref": "test", "action": "interact"},
        "Side": side, "ReservedSource": source,
        "EncounterSpec": {
            "schema_version": 1, "encounter_id": encounter_id, "reservation_revision": 12,
            "mode": "campaign", "scene_def_id": "base:scene/field", "ruleset_id": "base:rule/field",
            "environment": {}, "rng_seed": "ffffffffffffffff", "sides": [side],
            "reserved_sources": [source], "battle_limit": 1, "deployment_constraints": {},
            "siege_snapshot": None,
        },
        "SlotOutcome": slot, "MissionResult": result,
        "FormationOrder": {
            "mission_id": "m", "order_id": "c", "issuer_id": "issuer", "client_sequence": 1,
            "issued_tick": 50, "formation_ids": [5, 10], "order_type": "move",
            "target_position": [-2**31, 0, 2**31 - 1], "target_formation_id": None, "parameters": {},
        },
        "Handshake": {"protocol_version": 1, "content_api_version": 1, "content_hash": "ab"*32},
        "SaveHeader": {"schema_version": 1, "game_minute": max_integer},
    }


def main():
    here = Path(__file__).resolve()
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", required=True, help="Godot console or headless executable")
    parser.add_argument("--project", type=Path, default=here.parents[4] / "game")
    args = parser.parse_args()
    cases = fixtures()
    with tempfile.TemporaryDirectory(prefix="p1-review-interop-") as path:
        project = Path(path)
        shutil.copytree(args.project / "contracts", project / "contracts")
        shutil.copyfile(here.with_name("verify.gd"), project / "verify.gd")
        (project / "project.godot").write_text("config_version=5\n", encoding="utf-8")
        inputs, outputs = project / "inputs", project / "outputs"
        inputs.mkdir()
        outputs.mkdir()
        for kind, value in cases.items():
            (inputs / (kind + ".json")).write_bytes(canonical(value))
        receipt = dict(cases["CommandReceipt"], view_changes="first\0second")
        (project / "invalid.json").write_bytes(canonical(receipt))
        run = subprocess.run(
            [args.godot, "--headless", "--log-file", str(project / "godot.log"), "--path",
             str(project), "--script", "res://verify.gd"],
            env=os.environ | {"APPDATA": path, "LOCALAPPDATA": path},
            capture_output=True, timeout=90,
        )
        output = (run.stdout + run.stderr).decode("utf-8", errors="replace")
        print(output.strip())
        if run.returncode or "ERROR:" in output or "P1_SCHEMA_INTEROP PASS" not in output:
            raise SystemExit(run.returncode or 1)
        for kind, expected in cases.items():
            raw = (outputs / (kind + ".json")).read_bytes()
            if raw != canonical(expected) or json.loads(raw) != expected:
                raise SystemExit("Godot output differs from Python fixture: " + kind)
        print(f"P1_SCHEMA_REVERSE PASS {len(cases)}/{len(cases)}")


if __name__ == "__main__":
    main()
