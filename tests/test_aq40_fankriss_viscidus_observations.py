"""Reference-backed AQ40 recipient aura observations; actions remain disabled."""
import pathlib
import unittest

SRC = (pathlib.Path(__file__).resolve().parents[1] / "encounters.lua").read_text()


class AQ40AuraObservations(unittest.TestCase):
    def test_fankriss_positive_gain_and_fade(self):
        x = SRC.split("        fankriss = {", 1)[1].split("        viscidus = {", 1)[0]
        for signal in ('You are afflicted by Entangle.',
                       '^(.+) is afflicted by Entangle%.$',
                       'Entangle fades from you.',
                       '^Entangle fades from (.+)%.$'):
            self.assertIn(signal, x)
        self.assertIn('target = "player"', x)
        self.assertIn('target = "capture"', x)
        self.assertNotIn('action = "come"', x)
        self.assertNotIn("duration = 8", x)

    def test_viscidus_self_toxin_only_without_guessed_bot(self):
        x = SRC.split("        viscidus = {", 1)[1].split("        huhuran = {", 1)[0]
        self.assertIn('You are afflicted by Toxin.', x)
        self.assertIn('Toxin fades from you.', x)
        self.assertIn('target = "player"', x)
        self.assertNotIn('target = "capture"', x)
        self.assertNotIn('action = "come"', x)
        self.assertNotIn("duration = 10", x)


if __name__ == "__main__":
    unittest.main()
