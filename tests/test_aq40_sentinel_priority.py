"""AQ40 Sentinel original-ability priority declaration regression.

This does not assert that combat-log attribution or runtime sorting exists.
"""
import pathlib
import re
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]


class SentinelPriorityContract(unittest.TestCase):
    def test_approved_order_and_groups(self):
        source = (ROOT / "encounters.lua").read_text()
        section = source.split("        sentinels = {", 1)[1].split("        defender = {", 1)[0]
        expected = [
            ("Mortal Strike",),
            ("Mending",),
            ("Fire Reflect", "Arcane Reflect"),
            ("Frost Reflect", "Shadow Reflect"),
            ("Shadowbolt Volley", "Shadow Storm"),
            ("Knockback",),
            ("Mana Burn",),
            ("Thorns",),
            ("Thunderclap",),
        ]
        block = section.split("initialAbilityPriority = {", 1)[1].split("\n            },", 1)[0]
        matches = re.findall(r'\{ rank = (\d+), names = \{([^}]+)\} \}', block)
        self.assertEqual([int(rank) for rank, _ in matches], list(range(1, 10)))
        self.assertEqual([
            tuple(re.findall(r'"([^"]+)"', names)) for _, names in matches
        ], expected)

    def test_no_invented_sentinel_combat_rules(self):
        source = (ROOT / "encounters.lua").read_text()
        section = source.split("        sentinels = {", 1)[1].split("        defender = {", 1)[0]
        self.assertIn("abilities = {}, triggers = {}", section)
        self.assertNotIn("repeatDelay", section)
        self.assertNotIn("startRule", section)
        self.assertNotIn("finishRule", section)


if __name__ == "__main__":
    unittest.main()
