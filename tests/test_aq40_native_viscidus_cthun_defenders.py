"""AQ40 native source contracts; runtime behaviour requires in-game testing."""
from pathlib import Path
import unittest

root = Path(__file__).resolve().parents[1]
source = (root / "encounters.lua").read_text(encoding="utf-8")
toc = (root / "SoloCraftBots.toc").read_text(encoding="utf-8")
mechanics = (root / "mechanics.lua").read_text(encoding="utf-8")
vis = source.split("        viscidus = {", 1)[1].split("        huhuran = {", 1)[0]
cthun = source.split("        cthun = {", 1)[1].split("        sentinels = {", 1)[0]
defender = source.split("        defender = {", 1)[1]

class NativeAQ40(unittest.TestCase):
    def test_viscidus_frost_damage_events(self):
        for name in ("CHAT_MSG_SPELL_SELF_DAMAGE", "CHAT_MSG_SPELL_PARTY_DAMAGE",
                     "CHAT_MSG_SPELL_FRIENDLYPLAYER_DAMAGE"):
            self.assertIn(name, vis)
        self.assertIn('pattern = "Viscidus.*Frost damage"', vis)
        self.assertIn('id = "frosthits"', vis)
    def test_viscidus_physical_both_sources(self):
        self.assertIn('pattern = "^You [hc][ir][ti].* Viscidus for "', vis)
        self.assertIn('pattern = " [hc][ir][ti].* Viscidus for "', vis)
        self.assertNotIn("berserk", vis.lower())
    def test_cthun_giant_birth_and_weaken_reference(self):
        self.assertIn("Giant Claw Tentacle begins to cast Birth.", cthun)
        self.assertIn("Giant Eye Tentacle begins to cast Birth.", cthun)
        self.assertIn('minDelay = 30, provenance = "predicted"', cthun)
        self.assertIn('minDelay = 8, provenance = "predicted"', mechanics)
        self.assertIn('contains = "is weakened!"', cthun)
    def test_defender_reflect_evidence_no_fake_cooldown(self):
        for spell in ("Moonfire", "Fireball", "Frostbolt", "Corruption"):
            self.assertIn(spell + " is reflected back by Anubisath Defender.", defender)
        self.assertIn('type = "ability_observed"', defender)
        self.assertNotIn("600", defender)
    def test_development_version(self):
        self.assertIn("## Version: 0.9.87-dev", toc)

if __name__ == "__main__":
    unittest.main()
