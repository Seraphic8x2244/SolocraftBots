"""Static contracts for positively attributed Defender pair state."""
import pathlib
import unittest

SOURCE = (pathlib.Path(__file__).resolve().parents[1] / "mechanics.lua").read_text()


class DefenderPairContract(unittest.TestCase):
    def test_only_approved_pairs(self):
        block = SOURCE.split("local defenderPairs = {", 1)[1].split("}", 1)[0]
        for item in ("meteor = 1", "plague = 1", "shadowstorm = 2",
                     "thunderclap = 2", "firearcane = 3", "frostshadow = 3"):
            self.assertIn(item, block)
        self.assertNotIn("enrage", block)
        self.assertNotIn("explode", block)

    def test_exact_guid_and_live_row_required(self):
        block = SOURCE.split("function mechanics.ObserveDefenderAbility(", 1)[1].split(
            "function mechanics.GetDefenderAbilities(", 1)[0]
        for item in ('active.id ~= "aq40.defender"',
                     'UnitName(unit) ~= "Anubisath Defender"',
                     'guid = mechanics.NPCInstanceID(unit)',
                     'not row.dead and row.instanceID == guid',
                     'selected[pair] and selected[pair] ~= ability'):
            self.assertIn(item, block)

    def test_readout_returns_copy(self):
        block = SOURCE.split("function mechanics.GetDefenderAbilities(", 1)[1].split(
            "-- Dev-only Defender interval sampler.", 1)[0]
        self.assertIn("local observedPairs = {}", block)
        self.assertIn("observedPairs[pair] = ability", block)


if __name__ == "__main__":
    unittest.main()
