"""Dev-only automatic Anubisath Defender sampling and Huhuran threshold source contract."""
from pathlib import Path
import unittest
root = Path(__file__).resolve().parents[1]
mechanics = (root / "mechanics.lua").read_text(encoding="utf-8")
encounters = (root / "encounters.lua").read_text(encoding="utf-8")
toc = (root / "SoloCraftBots.toc").read_text(encoding="utf-8")

class DefenderAutoRecorder(unittest.TestCase):
    def test_dev_defaults_on_and_explicit_off_works(self):
        self.assertIn('db.bossModDefenderRecord == false', mechanics)
        self.assertIn('db.bossModDefenderRecord = false', mechanics)
        self.assertIn('db.bossModDefenderRecord = true', mechanics)
        self.assertIn('(db.bossModDefenderRecord ~= false and "ON" or "OFF")', mechanics)
        self.assertIn('string.find(version, "%-dev$")', mechanics)
        self.assertIn('SLASH_SCBDEFENDER1 = "/scbdefender"', mechanics)
        self.assertIn('message ~= "export"', mechanics)
        self.assertIn('db.bossModDefenderIntervals', mechanics)
        self.assertIn('table.getn(samples) > 200', mechanics)

    def test_abilities_and_threshold(self):
        for key in ('meteor', 'plague', 'shadowstorm', 'thunderclap'):
            self.assertIn('ability = "' + key + '"', encounters)
        h = encounters.split("        huhuran = {",1)[1].split("        twins = {",1)[0]
        self.assertIn('label = "Berserk (30% HP)"', h)
        self.assertIn('threshold = 0.30', h)
        self.assertIn('(pct - state.threshold) * elapsed / loss', mechanics)
        self.assertIn('## Version: 0.9.87-dev', toc)

if __name__ == "__main__":
    unittest.main()
