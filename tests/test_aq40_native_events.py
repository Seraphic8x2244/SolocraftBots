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


if __name__ == "__main__":
    unittest.main()
