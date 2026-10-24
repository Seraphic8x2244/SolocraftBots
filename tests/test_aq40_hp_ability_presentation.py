"""AQ40 positive-observation HP presentation source regressions."""
import pathlib
import unittest

SRC = (pathlib.Path(__file__).resolve().parents[1] / "mechanics.lua").read_text()


class ObservedHPAbilityPresentation(unittest.TestCase):
    def test_sort_uses_original_only(self):
        layout = SRC.split("LayoutPresentation = function(kind)", 1)[1].split("-- Only width and row height", 1)[0]
        self.assertIn('active.id == "aq40.sentinels"', layout)
        self.assertIn("a.sentinelAbilities.priority", layout)
        self.assertIn("b.sentinelAbilities.priority", layout)
        self.assertIn("return order[a] < order[b]", layout)

    def test_sentinel_priority_from_original(self):
        body = SRC.split("function mechanics.ObserveSentinelAbility(", 1)[1].split(
            "function mechanics.GetSentinelAbilities(", 1)[0]
        self.assertIn("state.priority = state.original and SentinelPriority(state.original)", body)
        self.assertIn('LayoutPresentation("tracker")', body)

    def test_only_observed_abilities_shown(self):
        render = SRC.split("function mechanics.UpdatePresentation(now)", 1)[1]
        self.assertIn("pairs(slot.sentinelAbilities.observed)", render)
        self.assertIn("slot.defenderPairs[pair]", render)
        self.assertIn('table.concat(seen, ", ")', render)


if __name__ == "__main__":
    unittest.main()
