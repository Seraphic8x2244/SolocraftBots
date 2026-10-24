"""Source contract for native C'Thun timer declarations (not runtime validation)."""
import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
TEXT = (ROOT / "encounters.lua").read_text(encoding="utf-8")
TOC = (ROOT / "SoloCraftBots.toc").read_text(encoding="utf-8")

class CthunNativeTimers(unittest.TestCase):
    def test_dark_glare_has_native_trigger_and_reference_clock(self):
        cthun = TEXT.split("        cthun = {", 1)[1].split("        sentinels = {", 1)[0]
        self.assertIn('firstDelay = 45, repeatDelay = 87', cthun)
        self.assertIn('resetOn = "start", castTime = 3', cthun)
        self.assertIn("Eye of C'Thun begins to cast Dark Glare.", cthun)

    def test_weakened_needs_native_emote(self):
        cthun = TEXT.split("        cthun = {", 1)[1].split("        sentinels = {", 1)[0]
        self.assertIn('event = "CHAT_MSG_MONSTER_EMOTE"', cthun)
        self.assertIn('contains = "is weakened!"', cthun)
        self.assertIn('duration = 45, provenance = "predicted"', cthun)

    def test_not_promoted_to_stable(self):
        self.assertIn("## Version: 0.9.87-dev", TOC)

if __name__ == "__main__":
    unittest.main()
