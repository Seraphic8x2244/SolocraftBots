"""Native AQ40 Huhuran and Twins contract, independent of creature GUIDs."""
import pathlib
import unittest

S = (pathlib.Path(__file__).resolve().parents[1] / "encounters.lua").read_text()

class NativeBossEvents(unittest.TestCase):
    def test_huhuran(self):
        x = S.split("        huhuran = {", 1)[1].split("        twins = {", 1)[0]
        for phrase in ("You are afflicted by Noxious Poison.",
                       "Noxious Poison fades from you.",
                       "You are afflicted by Wyvern Sting.",
                       "Wyvern Sting fades from you.",
                       "Princess Huhuran gains Frenzy.",
                       "Frenzy fades from Princess Huhuran.",
                       "Princess Huhuran gains Berserk."):
            self.assertIn(phrase, x)
        self.assertNotIn("repeatDelay", x)

    def test_twins(self):
        x = S.split("        twins = {", 1)[1].split("        ouro = {", 1)[0]
        for phrase in ("gains Twin Teleport.", "You are afflicted by Blizzard.",
                       "Blizzard fades from you."):
            self.assertIn(phrase, x)
        self.assertNotIn("repeatDelay", x)

if __name__ == "__main__":
    unittest.main()
