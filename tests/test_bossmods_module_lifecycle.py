"""Static source contracts for Boss Mods Chunk 2. Not an in-game or compiler test."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
MECH = (ROOT / "mechanics.lua").read_text(encoding="utf-8")
DATA = (ROOT / "encounters.lua").read_text(encoding="utf-8")
TOC = (ROOT / "SoloCraftBots.toc").read_text(encoding="utf-8")


class ModuleLifecycleContract(unittest.TestCase):
    def test_one_owner_and_old_scan_remains(self):
        self.assertEqual(MECH.count("SoloCraftBotsBossModsEventFrame"), 1)
        self.assertIn("bossModsPollElapsed >= 0.4", MECH)
        self.assertIn('SCB_BossModsObserveTargets()', MECH)
        self.assertIn('SCB_BossModsGroupCombat()', MECH)
        self.assertIn('bossModsFrame:RegisterEvent("PLAYER_TARGET_CHANGED")', MECH)
        self.assertNotIn("SCB_BOSSMODS_ZONES", MECH)

    def test_raid_zone_wake_and_submodule_activation(self):
        for marker in ("ValidateModuleSpec", "moduleWaker", "passiveModules",
                       "combatModules", "requiredZone", "EnterRaidZone",
                       "WakeEncounter", "GetRaidModuleState",
                       "GetEncounterModuleState"):
            self.assertIn(marker, MECH)
        self.assertIn("engine.GetRequiredZones()", MECH)
        self.assertIn("active.moduleState.attempt = active.moduleState.attempt + 1", MECH)
        self.assertIn("sub.active, sub.retained = true, false", MECH)

    def test_sleeper_is_and_not_boss_death_alone(self):
        self.assertIn("function mechanics.CheckModuleSleeper(", MECH)
        self.assertIn("sleeper.npcdead or {}", MECH)
        self.assertIn("sleeper.trackerEmpty or {}", MECH)
        self.assertIn("moduleLifecycle.TrackerCount(session, tracker) > 0", MECH)
        self.assertIn("return mechanics.StopEncounter", MECH)
        self.assertIn("needed > 1 and source ~= \"message\"", MECH)

    def test_disengagement_resets_attempt_and_keeps_encounter(self):
        self.assertIn('engine.DisengageEncounter("raid disengaged", state.generation)', MECH)
        reset = MECH.split("function mechanics.DisengageEncounter(", 1)[1].split(
            "function mechanics.WakeEncounter(", 1)[0]
        self.assertIn("BeginPostBossCleanup(false)", reset)
        self.assertIn("state.deaths = {}", reset)
        self.assertIn("session.abilities, session.abilityOrder = nil, nil", reset)
        self.assertIn("session.engaged = false", reset)
        self.assertNotIn("StopEncounter(", reset)

    def test_retained_rows_actions_and_fade_dispatch(self):
        for marker in ("function moduleLifecycle.RetainsSlot(",
                       "actionKeyPrefix", "session.retainedActions = retained.action",
                       "retained.action[\"kick:\" .. slot.key] = true",
                       "moduleLifecycle.TrackerCount(session, cfg.id)",
                       "FinishPostBossCleanup()", "session.retainingEffects",
                       "session.retainedActions[actionKey]",
                       "mechanics.CheckModuleSleeper(session.generation)"):
            self.assertIn(marker, MECH)
        self.assertIn("session.retainingEffects and not session.engaged", MECH)
        self.assertIn("session.retainingEffects and aura.retainAfterBossDeath", MECH)

    def test_vael_uses_both_conditions_and_retention(self):
        vael = DATA.split("        vaelastrasz = {", 1)[1].split(
            "        broodlord = {", 1)[0]
        self.assertIn('moduleWaker = "Vaelastrasz the Corrupt"', vael)
        self.assertIn('trackerEmpty = "BurningAdrenalineTracker"', vael)
        self.assertIn('retainUntilResolved = true', vael)
        self.assertIn('count = 1', vael)
        self.assertIn('action = "kick"', vael)
        self.assertIn('retainAfterBossDeath = true', vael)
        self.assertIn('## Version: 0.9.91-dev', TOC)


if __name__ == "__main__":
    unittest.main()
