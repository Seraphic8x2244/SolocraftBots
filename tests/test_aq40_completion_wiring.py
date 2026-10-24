"""AQ40 0.9.86 encounter wiring regression (source checks, NOT runtime tests)."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
ENC = (ROOT / "encounters.lua").read_text(encoding="utf-8")
MECH = (ROOT / "mechanics.lua").read_text(encoding="utf-8")
TOC = (ROOT / "SoloCraftBots.toc").read_text(encoding="utf-8")

class AQ40CompletionWiring(unittest.TestCase):
    def test_viscidus_toxin_bot_event_and_group_owner(self):
        visc = ENC.split("        viscidus = {", 1)[1].split("        huhuran = {", 1)[0]
        self.assertIn('pattern = "^(.+) is afflicted by Toxin%.$"', visc)
        self.assertIn('type = "viscidus_toxin"', visc)
        self.assertIn('function mechanics.ObserveViscidusToxin', MECH)
        self.assertIn('ResolveBoundLive(name, true, true)', MECH)
        self.assertIn('Now() + 8', MECH)
        self.assertIn('SCB_RequestCommand("come", route)', MECH)
        self.assertNotIn('TargetUnit(', MECH.split('local function RefreshToxinTracker()',1)[1].split('function mechanics.UpdatePresentationState',1)[0])

    def test_cthun_phase_two_native_and_glare(self):
        cthun = ENC.split("        cthun = {", 1)[1].split("        sentinels = {", 1)[0]
        for spell in ("Giant Claw Tentacle", "Giant Eye Tentacle"):
            self.assertIn(spell, cthun)
        self.assertIn("Eye of C'Thun dies.", cthun)
        self.assertIn('type = "cthun_phase2"', cthun)
        self.assertIn('type = "cthun_glare"', cthun)
        self.assertIn('type = "cthun_weakened"', cthun)
        self.assertIn('minDelay = 12', MECH)
        self.assertIn('minDelay = 42', MECH)
        self.assertIn('minDelay = 8', MECH)
        self.assertIn('minDelay = 38', MECH)
        self.assertIn('minDelay = 39', MECH)
        self.assertIn('ScheduleTimer("cthun-after-weakened", 45', MECH)

    def test_defender_learning_preserved_without_600_second_cooldown(self):
        defender = ENC.split("        defender = {", 1)[1]
        self.assertIn('repeatDelay = 40, resetOn = "finish"', defender)
        self.assertNotIn('repeatDelay = 600', defender)
        for token in ('SLASH_SCBDEFENDER1 = "/scbdefender"',
                      'bossModDefenderIntervals', 'RecordDefenderHit',
                      'message == "export"'):
            self.assertIn(token, MECH)
        self.assertIn("## Version: 0.9.86-dev", TOC)

if __name__ == "__main__":
    unittest.main()
