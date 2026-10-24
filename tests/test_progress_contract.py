"""Static regression contract for AQ40 Chunk 4 generic progress templates.

Run with: python -m unittest discover -s tests -p 'test_*_contract.py'
Source assertions are not Lua compiler or in-game runtime validation.
"""
from pathlib import Path
import unittest

SOURCE = (Path(__file__).resolve().parents[1] / "mechanics.lua").read_text()
BWL = (Path(__file__).resolve().parents[1] / "encounters.lua").read_text()


class ProgressContract(unittest.TestCase):
    def test_existing_owner_and_timer(self):
        self.assertIn("mechanics.ScheduleTimer(\"stage-ready:\" .. id", SOURCE)
        self.assertIn("mechanics.UpdatePresentation()", SOURCE)
        self.assertIn("mechanics.UpdateTimers(now)", SOURCE)
        self.assertNotIn('SetScript("OnUpdate"', SOURCE)
        self.assertNotIn('RegisterEvent(', SOURCE)

    def test_counted_hits_are_only_observed(self):
        self.assertIn("function mechanics.ObserveCounterHit(id, occurrenceId, expectedGeneration)", SOURCE)
        self.assertIn("state.count = state.count + 1", SOURCE)
        self.assertIn('return false, "duplicate observation"', SOURCE)
        self.assertIn("details and details.observationId", SOURCE)
        self.assertIn("maximumKind = state.spec.maximumKind or \"reference\"", SOURCE)
        self.assertIn('state.spec.maximumKind == "observed" and "" or "~"', SOURCE)

    def test_counter_declarations_reject_missing_and_invalid_ids(self):
        self.assertIn("local function CheckCounter(c, seen)", SOURCE)
        self.assertIn("not IsFiniteNumber(c.maximum)", SOURCE)
        self.assertIn("c.maximum ~= math.floor(c.maximum)", SOURCE)
        self.assertIn("counterIds[d.counters[i].id] = true", SOURCE)
        self.assertIn('return false, "counter not declared"', SOURCE)

    def test_counter_reset_requires_explicit_evidence(self):
        self.assertIn("function mechanics.ResetCounter(id, expectedGeneration)", SOURCE)
        self.assertIn("state.count, state.seen = 0, {}", SOURCE)
        self.assertIn('elseif effect.type == "counter_reset" then', SOURCE)
        self.assertIn("mechanics.ResetCounter(effect.id, active.generation)", SOURCE)
        self.assertIn('or rule.effects[j].type == "counter_reset"', SOURCE)

    def test_stages_only_change_on_positive_observation(self):
        self.assertIn('elseif effect.type == "timer_stage" then', SOURCE)
        self.assertIn("mechanics.SetTimerStage(effect.id, effect, active.generation)", SOURCE)
        self.assertIn("stage.ready = true", SOURCE)
        self.assertIn("active.stageTimers[id] == stage", SOURCE)
        self.assertIn('return false, "stale encounter"', SOURCE)
        self.assertIn('state.maximumAt > state.minimumAt', SOURCE)
        # No timer expiry can select another stage or fabricate an emote.
        stage_slice = SOURCE.split("function mechanics.SetTimerStage(", 1)[1].split(
            "function mechanics.GetTimerStage(", 1)[0]
        self.assertNotIn("DispatchEvent(", stage_slice)
        self.assertNotIn("SetTimerStage(", stage_slice[1:])

    def test_thresholds_fail_closed_and_do_not_claim_boss_spells(self):
        self.assertIn("function mechanics.ObserveHPThreshold(", SOURCE)
        self.assertIn("mechanics.NPCInstanceID(unit)", SOURCE)
        self.assertIn('return false, "different npc instance"', SOURCE)
        self.assertIn("state.baselinePct, state.baselineAt = pct, now", SOURCE)
        self.assertIn('frame.detail:SetText("?")', SOURCE)
        self.assertIn("(pct - state.threshold) * elapsed / loss", SOURCE)
        self.assertIn('frame.detail:SetText(string.format("%.0f%% HP"', SOURCE)

    def test_lifecycle_and_bwl_compatibility(self):
        self.assertIn("return mechanics.InitializeCounters(active.generation)", SOURCE)
        self.assertIn("slot.progressKind, slot.progressState = nil, nil", SOURCE)
        self.assertIn("RenderAbilityBar(slot, now)", SOURCE)
        self.assertIn("SCB_RequestCommand(commandStep.command, commandStep.scope)", SOURCE)
        self.assertIn('mechanics.ShowTrackedAura("seen:"', SOURCE)
        self.assertIn("bwl = {", BWL)
        self.assertNotIn("aq40 = {", BWL)

    def test_no_unrequested_encounter_or_widget_owner(self):
        self.assertIn('AcquirePresentation("timer", "counter:" .. spec.id)', SOURCE)
        self.assertIn('AcquirePresentation("timer", "stage:" .. id)', SOURCE)
        self.assertIn('AcquirePresentation("timer", "threshold:" .. key)', SOURCE)
        self.assertNotIn("phase_timer", SOURCE)
        self.assertNotIn("AQ40", BWL)


if __name__ == "__main__":
    unittest.main()
