"""Static regression contracts for AQ40 Chunk 2 HP infrastructure.

Run: python3 -m unittest discover -s tests
These source checks cannot replace Lua 5.0 compilation or in-game testing.
"""
from pathlib import Path
import unittest

SOURCE = (Path(__file__).resolve().parents[1] / "mechanics.lua").read_text()
TOC = (Path(__file__).resolve().parents[1] / "SoloCraftBots.toc").read_text()


class HPTrackerContract(unittest.TestCase):
    def test_identity_must_be_unique_instance(self):
        self.assertIn('function mechanics.NPCInstanceID(unit)', SOURCE)
        self.assertIn('id = UnitGUID(unit)', SOURCE)
        self.assertIn('id = mechanics.NPCInstanceID(unit)', SOURCE)
        self.assertIn('key .. ":" .. id', SOURCE)
        self.assertIn('return false, "instance already tracked"', SOURCE)

    def test_token_reuse_does_not_target_wrong_npc(self):
        self.assertIn('mechanics.NPCInstanceID(unit) == slot.instanceID', SOURCE)
        self.assertIn('slot.clickTarget', SOURCE)
        self.assertIn('and TargetUnit then TargetUnit(unit)', SOURCE)

    def test_death_requires_positive_evidence(self):
        self.assertIn('slot.dead and slot.hideOnDeath', SOURCE)
        self.assertIn('slot.frame.detail:SetText("DEAD")', SOURCE)
        self.assertIn('UnitIsDeadOrGhost(unit)', SOURCE)
        self.assertNotIn('not mechanics.NPCInstanceID(unit) then slot.dead', SOURCE)

    def test_existing_panel_owns_hp_rows(self):
        self.assertIn('for _, slot in ipairs(presentation.hp.pool)', SOURCE)
        self.assertIn('for _, slot in ipairs(presentation.aura.pool)', SOURCE)
        self.assertIn('for _, slot in ipairs(presentation.action.pool)', SOURCE)
        self.assertIn('or { "aura", "action", "hp" }', SOURCE)
        self.assertIn('function mechanics.UpdatePresentation(now)', SOURCE)

    def test_development_metadata_is_present(self):
        self.assertRegex(TOC, r'## Version: 0\.9\.\d+-dev')


if __name__ == "__main__":
    unittest.main()
