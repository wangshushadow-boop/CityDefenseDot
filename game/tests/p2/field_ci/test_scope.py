"""Check construction access to concrete field implementations."""
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[4] / "ci"))
from gates import permitted


class FieldConstruction(unittest.TestCase):
    def test_only_the_composition_root_connects_the_two_implementations(self):
        for name in ("field_mission", "field_brains"):
            target = f"mission/runtime/{name}.gd"
            self.assertTrue(permitted("bootstrap/composition_root.gd", target))
            for caller in ("bootstrap/desktop.gd", "presentation/ui/hud.gd", "application/game_session.gd"):
                self.assertFalse(permitted(caller, target))
        self.assertFalse(permitted("bootstrap/composition_root.gd", "mission/runtime/field_pipeline.gd"))


if __name__ == "__main__":
    unittest.main()
