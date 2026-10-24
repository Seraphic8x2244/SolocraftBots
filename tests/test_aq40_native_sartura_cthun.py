"""Native-only AQ40 positive event contract without GUID assumptions."""
import pathlib
import unittest

SRC = (pathlib.Path(__file__).resolve().parents[1] / "encounters.lua").read_text()

class NativeObservations(unittest.TestCase):
    def test_sartura_whirlwind_fade_and_enrage(self):
        x = SRC.split("        sartura = {", 1)[1].split("        fankriss = {", 1)[0]
        self.assertIn("Whirlwind fades from Battleguard Sartura.", x)
        self.assertIn("Battleguard Sartura gains Enrage", x)
        self.assertNotIn("repeatDelay", x)

    def test_cthun_true_event_not_guessed_duration(self):
        x = SRC.split("        cthun = {", 1)[1].split("        sentinels = {", 1)[0]
        self.assertEqual(x.count("triggers = {"), 1)
        for message in ("is weakened!", "Giant Claw Tentacle begins to cast Birth.",
                        "Giant Eye Tentacle begins to cast Birth."):
            self.assertIn(message, x)
        self.assertNotIn("timer_stage", x)

if __name__ == "__main__":
    unittest.main()
