"""Executable ADR-012 examples. Each validator covers only the fields in its vector."""
import hashlib
import json
import math
import re
import unittest
import unicodedata
from decimal import Decimal, ROUND_HALF_UP
from uuid import UUID


MAX_EXACT = 2**53 - 1
MAX_U32 = 2**32 - 1
UID = "b48883c0-79fb-4cd3-96fe-43bb44dfddbb"
HASH_VECTOR = b'{"game_minute":12,"schema_version":1}'


def require(ok, error="InvalidArgument"):
    if not ok:
        raise ValueError(error)


def integer(value, lower=0, upper=MAX_EXACT):
    require(type(value) is int and lower <= value <= upper)
    return value


def typed_id(value, kind):
    scope, sep, raw = value.partition("/")
    require(scope == kind and sep == "/")
    parsed = UUID(raw)
    require(str(parsed) == raw and parsed.version == 4)
    return parsed


def canonical(value):
    def validate(item):
        if isinstance(item, (dict, list)):
            if isinstance(item, dict):
                for key in item:
                    require(isinstance(key, str) and bool(key) and key.isascii() and key.isprintable())
            for child in (item.values() if isinstance(item, dict) else item):
                validate(child)
        elif isinstance(item, str):
            require(unicodedata.is_normalized("NFC", item))
        elif type(item) is int:
            integer(item, -MAX_EXACT)
        else:
            require(item is None or type(item) is bool)
    validate(value)
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode("utf-8")


def decode(data):
    def unique(pairs):
        require(len(pairs) == len(dict(pairs)))
        return dict(pairs)
    obj = json.loads(data.decode("utf-8"), object_pairs_hook=unique)
    canonical(obj)  # Apply the same value constraints to incoming JSON.
    return obj


def result_hash(result):
    covered = {k: v for k, v in result.items() if k != "integrity_hash"}
    return hashlib.sha256(canonical(covered)).hexdigest()


def millimeters(meters):
    require(meters.is_finite())
    quantized = (meters * 1000).to_integral_value(rounding=ROUND_HALF_UP)
    return integer(int(quantized), -(2**31), 2**31 - 1)


def resolve_agent(mission, index, generation, current_mission, generations):
    integer(index, 0, MAX_U32)
    integer(generation, 1, MAX_U32)
    require(mission == current_mission and generations.get(index) == generation, "NotFound")


def check_result(encounter, result):
    require(result["schema_version"] == encounter["schema_version"] == 1, "StaleVersion")
    typed_id(encounter["encounter_id"], "encounter")
    require(result["encounter_id"] == encounter["encounter_id"], "NotFound")
    require(result["reservation_revision"] == encounter["reservation_revision"], "StaleVersion")
    require(result["integrity_hash"] == result_hash(result), "Conflict")
    intervals = []
    for source in encounter["reserved_sources"]:
        start, stop = source["source_slot_range"]
        integer(start, 0, MAX_U32)
        integer(stop, 1, MAX_U32 + 1)
        require(integer(source["count"], 1) == stop - start)
        require(source["hero_id"] is None or source["count"] == 1)
        intervals.append((start, stop))
    intervals.sort()
    require(all(first[1] <= second[0] for first, second in zip(intervals, intervals[1:])), "Conflict")
    outcomes = result["slot_outcomes"]
    reported = [integer(x["source_slot_id"], 0, MAX_U32) for x in outcomes]
    require(len(reported) == sum(stop - start for start, stop in intervals), "Conflict")
    reported.sort()
    offset = 0
    for start, stop in intervals:
        for slot in range(start, stop):
            require(reported[offset] == slot, "Conflict")
            offset += 1
    for entry in outcomes:
        require(entry["end_status"] in ("alive", "wounded", "dead", "captured", "withdrawn", "not_spawned"))
        require(entry["end_status"] != "not_spawned" or (entry["xp"] == 0 and entry["wounded"] is False))


def check_order(order, mission, issuer, owned, current_tick):
    require(order["mission_id"] == mission, "NotFound")
    require(order["issuer_id"] == issuer, "Unauthorized")
    forms = order["formation_ids"]
    require(bool(forms) and len(forms) == len(set(forms)))
    require(set(forms) <= owned, "Unauthorized")
    require(integer(order["issued_tick"]) <= current_tick, "StaleVersion")


def migrate_sample(record):
    """Two synthetic save header versions with one renamed field. Pure transform."""
    version = integer(record["schema_version"])
    if version == 0:
        require(record.keys() == {"schema_version", "minutes"})
        return {"schema_version": 1, "game_minute": integer(record["minutes"])}
    require(version == 1, "StaleVersion")
    require(record.keys() == {"schema_version", "game_minute"})
    return {"schema_version": 1, "game_minute": integer(record["game_minute"])}


def negotiate(expected, remote):
    for field in ("protocol_version", "content_api_version", "content_hash"):
        require(remote[field] == expected[field], "StaleVersion")


def replay_receipt(command, principal, committed):
    """Lookup after authentication. None means this ID has no committed command."""
    require(command["actor_ref"] == principal, "Unauthorized")
    key = (command["scope_id"], principal, command["command_id"])
    if key not in committed:
        return None
    original, receipt = committed[key]
    require(original == canonical(command), "Conflict")
    return receipt


class ContractVectors(unittest.TestCase):
    def test_canonical_round_trip_and_hash(self):
        incoming = b'{\n "schema_version":1, "game_minute":12 }'
        self.assertEqual(canonical(decode(incoming)), HASH_VECTOR)
        self.assertEqual(hashlib.sha256(HASH_VECTOR).hexdigest(), "bafa46fb93c768558e0945e9e95d714e0a4626a5e64bd66c31262526ed96b2f6")
        with self.assertRaisesRegex(ValueError, "InvalidArgument"):
            decode(b'{"a":1,"a":2}')
        for value in (3.14, math.inf, MAX_EXACT + 1, "e\u0301"):
            with self.subTest(value=value), self.assertRaises(ValueError):
                canonical({"a": value})

    def test_typed_identity_and_units(self):
        self.assertEqual(str(typed_id("party/" + UID, "party")), UID)
        with self.assertRaisesRegex(ValueError, "InvalidArgument"):
            typed_id("hero/" + UID, "party")
        for text, expected in [("-0.0005", -1), ("1.2345", 1235), ("0", 0)]:
            self.assertEqual(millimeters(Decimal(text)), expected)
        with self.assertRaises(ValueError):
            millimeters(Decimal("2147483.648"))
        self.assertNotEqual(canonical(None), canonical(0))
        with self.assertRaises(ValueError):
            integer(False)

    def test_generation_and_scope(self):
        resolve_agent("mission-A", 4, 2, "mission-A", {4: 2})
        for mission, generation in [("mission-A", 1), ("mission-B", 2)]:
            with self.assertRaisesRegex(ValueError, "NotFound"):
                resolve_agent(mission, 4, generation, "mission-A", {4: 2})

    def test_encounter_result(self):
        encounter = {"schema_version": 1, "encounter_id": "encounter/" + UID, "reservation_revision": 9,
                     "reserved_sources": [{"source_slot_range": [2, 4], "hero_id": None, "count": 2}]}
        rows = [{"source_slot_id": 2, "end_status": "withdrawn", "xp": 1, "wounded": True},
                {"source_slot_id": 3, "end_status": "not_spawned", "xp": 0, "wounded": False}]
        result = {"schema_version": 1, "encounter_id": encounter["encounter_id"], "reservation_revision": 9,
                  "slot_outcomes": rows}
        result["integrity_hash"] = result_hash(result)
        check_result(decode(canonical(encounter)), decode(canonical(result)))
        for update, error in [({"slot_outcomes": [rows[0], rows[0]]}, "Conflict"),
                              ({"slot_outcomes": rows[:1]}, "Conflict"),
                              ({"reservation_revision": 10}, "StaleVersion"),
                              ({"slot_outcomes": [rows[0], rows[1] | {"xp": 1}]}, "InvalidArgument")]:
            bad = result | update
            bad["integrity_hash"] = result_hash(bad)
            with self.subTest(update=update), self.assertRaisesRegex(ValueError, error):
                check_result(encounter, bad)
        with self.assertRaisesRegex(ValueError, "Conflict"):
            check_result(encounter, result | {"integrity_hash": "0" * 64})

    def test_formation_authority_and_tick(self):
        order = {"mission_id": "mission-A", "issuer_id": "player-A", "issued_tick": 7, "formation_ids": [1, 2]}
        def check(value):
            check_order(decode(canonical(value)), "mission-A", "player-A", {1, 2}, 7)
        check(order)
        for update, error in [({"issuer_id": "other"}, "Unauthorized"), ({"formation_ids": [3]}, "Unauthorized"),
                              ({"mission_id": "mission-B"}, "NotFound"), ({"issued_tick": 8}, "StaleVersion")]:
            with self.subTest(update=update), self.assertRaisesRegex(ValueError, error):
                check(order | update)

    def test_retry_after_commit(self):
        cmd = {"scope_id": "sample", "actor_ref": "issuer", "command_id": "one",
               "expected_revision": 2, "payload": {"count": 7}}
        receipt = {"command_id": "one", "status": "Ok", "committed_revision": 3,
                   "errors": [], "view_changes": []}
        committed = {("sample", "issuer", "one"): (canonical(cmd), receipt)}
        self.assertEqual(replay_receipt(decode(canonical(cmd)), "issuer", committed), receipt)
        with self.assertRaisesRegex(ValueError, "Conflict"):
            replay_receipt(cmd | {"payload": {"count": 8}}, "issuer", committed)
        with self.assertRaisesRegex(ValueError, "Unauthorized"):
            replay_receipt(cmd, "other", committed)
        self.assertIsNone(replay_receipt(cmd | {"command_id": "two"}, "issuer", committed))

    def test_migration_without_mutation(self):
        original = b'{"minutes":12,"schema_version":0}'
        decoded = decode(original)
        upgraded = migrate_sample(decoded)
        self.assertEqual(canonical(upgraded), HASH_VECTOR)
        self.assertEqual(canonical(decoded), original)
        self.assertEqual(migrate_sample(upgraded), upgraded)
        for record in [decoded | {"unknown_critical": 7}, decoded | {"schema_version": 2}, decoded | {"minutes": -1}]:
            with self.subTest(record=record), self.assertRaises(ValueError):
                migrate_sample(record)

    def test_content_and_wire_versions(self):
        expected = {"protocol_version": 1, "content_api_version": 1, "content_hash": "ab" * 32}
        negotiate(expected, decode(canonical(expected)))
        for key, value in [("protocol_version", 2), ("content_api_version", 2), ("content_hash", "00" * 32)]:
            with self.subTest(field=key), self.assertRaisesRegex(ValueError, "StaleVersion"):
                negotiate(expected, expected | {key: value})


if __name__ == "__main__":
    unittest.main(verbosity=2)
