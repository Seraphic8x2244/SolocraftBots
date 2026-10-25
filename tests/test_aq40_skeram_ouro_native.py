"""Source contracts for AQ40 Skeram real-boss marking and Ouro native timers."""
import unittest
from pathlib import Path

root = Path(__file__).resolve().parents[1]
mechanics = (root / "mechanics.lua").read_text(encoding="utf-8")
encounters = (root / "encounters.lua").read_text(encoding="utf-8")
toc = (root / "SoloCraftBots.toc").read_text(encoding="utf-8")

class AQ40NativeMechanics(unittest.TestCase):
    def test_skeram_only_real_boss_marker(self):
        self.assertIn('local function AQ40SkeramMark()', mechanics)
        self.assertIn('UnitHealthMax(token) > minimum', mechanics)
        self.assertIn('UnitName(token) == "The Prophet Skeram"', mechanics)
        self.assertIn('SetRaidTarget(token, 6)', mechanics)
        self.assertIn('session.id == "aq40.skeram" then AQ40SkeramMark()', mechanics)
        self.assertNotIn('True Fulfillment', encounters.split('        skeram = {',1)[1].split('        bugtrio = {',1)[0])

    def test_ouro_submerge_emerge(self):
        self.assertIn('local function AQ40OuroSubmerge(now)', mechanics)
        self.assertIn('AQ40VisibleBoss("Ouro")', mechanics)
        self.assertIn('active.ouroPhase = "submerged"', mechanics)
        self.assertIn('label = "Next Emerge (reference)", minDelay = 27', mechanics)
        self.assertIn('session.id == "aq40.ouro" then AQ40OuroSubmerge(now)', mechanics)
        self.assertIn('active.ouroPhase = "emerged"', mechanics)
        self.assertIn('minDelay = 89', encounters)
        self.assertIn('contains = "Ground Rupture"', encounters)
        self.assertIn('## Version: 0.9.89-dev', toc)

if __name__ == "__main__":
    unittest.main()
