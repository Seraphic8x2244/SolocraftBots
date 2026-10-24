"""Source contracts for GUID-bound Sentinel provenance (not runtime behaviour)."""
import pathlib
import unittest

SOURCE = (pathlib.Path(__file__).resolve().parents[1] / "mechanics.lua").read_text()


class SentinelObservationContract(unittest.TestCase):
    def test_requires_engaged_exact_encounter_and_live_guid(self):
        body = SOURCE.split("function mechanics.ObserveSentinelAbility(", 1)[1].split(
            "function mechanics.GetSentinelAbilities(", 1)[0]
        self.assertIn('active.id ~= "aq40_sentinels"', body)
        self.assertIn('UnitName(unit) ~= "Anubisath Sentinel"', body)
        self.assertIn('guid = mechanics.NPCInstanceID(unit)', body)
        self.assertIn('not slot.dead and slot.instanceID == guid', body)

    def test_original_cannot_change_or_be_inferred_from_inheritance(self):
        body = SOURCE.split("function mechanics.ObserveSentinelAbility(", 1)[1].split(
            "function mechanics.GetSentinelAbilities(", 1)[0]
        self.assertIn('provenance ~= "original" and provenance ~= "inherited"', body)
        self.assertIn('state.original and state.original ~= ability', body)
        self.assertIn('if provenance == "original" then', body)
        self.assertIn('state.observed[ability] = true', body)

    def test_readout_defensively_copies_observations(self):
        body = SOURCE.split("function mechanics.GetSentinelAbilities(", 1)[1].split(
            "-- Dev-only Defender interval sampler.", 1)[0]
        self.assertIn('local observed = {}', body)
        self.assertIn('table.insert(observed, ability)', body)
        self.assertIn('priority = state and state.original', body)


if __name__ == "__main__":
    unittest.main()
