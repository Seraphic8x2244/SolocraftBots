"""Sentinel marker/buff/provenance source contracts (not in-game validation)."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
MECH = (ROOT / "mechanics.lua").read_text()
DATA = (ROOT / "encounters.lua").read_text()

class SentinelProvenanceContract(unittest.TestCase):
    def test_native_marker_identity_without_guid_requirement(self):
        body = MECH.split("local function SentinelEntryFor(", 1)[1].split(
            "local function SentinelAbilityFromBuff(", 1)[0]
        self.assertIn("state.byMark[mark]", body)
        self.assertIn("state.byGuid[guid]", body)
        self.assertIn("GetRaidTargetIndex(snapshot.unit)", body)
        self.assertIn("SetRaidTarget(snapshot.unit, candidate)", body)
        self.assertIn("if not entry and not mark and not guid then return nil end", body)
        click = MECH.split('frame:SetScript("OnClick", function()', 1)[1]
        self.assertIn("if slot.sentinelMark then", click)
        self.assertIn("GetRaidTargetIndex(unit) == slot.sentinelMark", click)

    def test_four_attempt_rows_and_disengage_reset(self):
        self.assertIn("function mechanics.BeginSentinelAttempt(", MECH)
        self.assertIn("for i = 1, 4 do", MECH)
        self.assertIn('AcquirePresentation("hp", "sentinel:slot:" .. i)', MECH)
        self.assertIn("session.sentinelState = nil", MECH)
        self.assertIn("active.moduleState.attempt ~= state.attempt", MECH)

    def test_original_never_rewritten_by_inherited_aura(self):
        observe = MECH.split("local function SentinelRecordBuffs(", 1)[1].split(
            "function mechanics.ObserveSentinelSnapshot(", 1)[0]
        self.assertIn("state.messages == 0", observe)
        self.assertIn("not entry.abilities.original", observe)
        self.assertIn("SentinelPriority(ability)", observe)
        ability = MECH.split("function mechanics.ObserveSentinelAbility(", 1)[1].split(
            "function mechanics.GetSentinelAbilities(", 1)[0]
        self.assertIn('if provenance == "original" then', ability)
        self.assertIn('entry.abilities.original ~= ability', ability)
        self.assertIn("entry.abilities.observed[ability] = true", ability)

    def test_death_attribution_and_no_double_count(self):
        self.assertIn("math.max(corpses, state.messages)", MECH)
        self.assertIn("entry.lastPct <= 0.01", MECH)
        self.assertIn("if match and not ambiguous then SentinelMarkDead", MECH)
        self.assertIn("entry.abilities.inherited[fallen.abilities.original] = true", MECH)
        self.assertIn('mechanics.CheckModuleSleeper(active.generation)', MECH)

    def test_all_nine_ability_buffs_and_optional_extension(self):
        part = DATA.split("        sentinels = {", 1)[1].split("        defender = {", 1)[0]
        for spell in (2147, 21737, 812, 13022, 19595, 25777, 2834, 9347, 2148):
            self.assertIn(f"[{spell}]", part)
        self.assertIn('mechanics.ReadSentinelBuffName(unit, i)', MECH)
        self.assertIn('type(spellId) == "number"', MECH)
        self.assertIn("spellIds = {", part)
        self.assertIn("textures = {}", part)

if __name__ == "__main__":
    unittest.main()
