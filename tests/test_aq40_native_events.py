"""Regression for GUID-independent AQ40 observations and canonical IDs."""
import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
M = (ROOT / "mechanics.lua").read_text()
E = (ROOT / "encounters.lua").read_text()

class NativeAQ40(unittest.TestCase):
    def test_canonical_ids_match_registry(self):
        self.assertNotIn('"aq40_sentinels"', M)
        self.assertNotIn('"aq40_defender"', M)
        self.assertIn('active.id == "aq40.sentinels"', M)
        self.assertIn('active.id ~= "aq40.defender"', M)

    def test_native_viscidus_observed_emotes(self):
        viscidus = E.split("        viscidus = {", 1)[1].split("        huhuran = {", 1)[0]
        for text in (" begins to slow!", " is freezing up!", " is frozen solid!",
                     " begins to crack!", " looks ready to shatter!"):
            self.assertIn(text, viscidus)
        self.assertEqual(viscidus.count('event = "CHAT_MSG_RAID_BOSS_EMOTE"'), 5)
        self.assertNotIn("timer_stage", viscidus)
        self.assertNotIn("minimumAt", viscidus)

if __name__ == "__main__":
    unittest.main()
