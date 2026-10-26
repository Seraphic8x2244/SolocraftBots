"""Chunk 3 shared raid-target scanner source contract (not an in-game test)."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
MECH = (ROOT / "mechanics.lua").read_text(encoding="utf-8")
TOC = (ROOT / "SoloCraftBots.toc").read_text(encoding="utf-8")


def section(start, end):
    return MECH.split(start, 1)[1].split(end, 1)[0]


class RaidTargetScannerContract(unittest.TestCase):
    def test_one_event_owner_and_legacy_scan_retained(self):
        self.assertEqual(MECH.count('CreateFrame("Frame", "SoloCraftBotsBossModsEventFrame"'), 1)
        self.assertEqual(MECH.count('bossModsFrame:SetScript("OnUpdate"'), 1)
        self.assertIn("bossModsPollElapsed >= 0.4", MECH)
        self.assertIn("SCB_BossModsObserveTargets()", MECH)
        self.assertIn("engine.TickRaidTargetScanner(elapsed)", MECH)
        self.assertIn("## Version: 0.9.92-dev", TOC)

    def test_five_second_discovery_for_group_and_player_combat(self):
        onset = section("local function SCB_BossModsTrackCombatState(",
                        "local function SCB_BossModsInitialize(")
        self.assertIn('mechanics.RequestRaidTargetObservations("__combat_discovery"', onset)
        self.assertIn("duration = \"fixed\", seconds = 5", onset)
        self.assertIn("raidTargetScanner.inCombat = true", onset)
        self.assertIn("raidTargetScanner.inCombat = false", onset)
        self.assertIn("request.duration == \"combat\"", onset)
        self.assertIn("SCB_BossModsTrackCombatState(groupCombat)", MECH)
        self.assertIn('bossModsFrame:RegisterEvent("PLAYER_REGEN_DISABLED")', MECH)
        self.assertIn('event == "PLAYER_REGEN_DISABLED" and bossModsZoneActive', MECH)
        self.assertIn("SCB_BossModsTrackCombatState(true)", MECH)
        self.assertIn("raid.wakers[name]", MECH)
        self.assertIn("mechanics.WakeEncounter(bossModsZone, name,", MECH)

    def test_independent_fixed_and_combat_requests(self):
        register = section("function mechanics.RequestRaidTargetObservations(",
                           "function mechanics.CancelRaidTargetObservations(")
        for marker in ("options.observations", '"identity"', '"marker"', '"hp"',
                       '"buffs"', '"fixed"', '"combat"', "options.seconds",
                       "options.names", "options.encounter", "options.submodule",
                       "options.onObservation", "options.dispatchDeclaredHP",
                       "raidTargetScanner.requests[key] = {"):
            self.assertIn(marker, register)
        expiry = section("local function SCB_BossModsPruneScanRequests(",
                         "local function SCB_BossModsVisitScanToken(")
        for marker in ("for key, request in pairs(raidTargetScanner.requests)",
                       "now >= request.expiresAt", "request.zone ~= bossModsZone",
                       "active.generation ~= request.generation",
                       "active.moduleState.attempt ~= request.attempt",
                       "mechanics.IsSubmoduleActive",
                       "raidTargetScanner.requests[key] = nil"):
            self.assertIn(marker, expiry)
        self.assertIn("function mechanics.CancelRaidTargetObservations(key)", MECH)
        self.assertIn("function mechanics.ClearRaidTargetObservations()", MECH)

    def test_shared_visit_collects_once_and_fans_out(self):
        visit = section("local function SCB_BossModsVisitScanToken(",
                        "function mechanics.TickRaidTargetScanner(")
        for marker in ("UnitName(unit)", "selected = {}", "request.names[name]",
                       "request.observations.marker", "request.observations.hp",
                       "request.observations.buffs", "GetRaidTargetIndex(unit)",
                       "UnitHealth(unit)", "UnitHealthMax(unit)", "UnitBuff(unit, i)",
                       "mechanics.ObserveDeclaredUnits({ unit }, active.generation)",
                       "for _, subscriber in ipairs(selected)",
                       "subscriber.request.onObservation(snapshot)"):
            self.assertIn(marker, visit)
        self.assertEqual(visit.count("UnitBuff(unit, i)"), 1)
        self.assertEqual(visit.count("UnitHealth(unit)"), 1)
        self.assertEqual(visit.count("UnitHealthMax(unit)"), 1)

    def test_sweep_side_paths_and_idle_shutdown(self):
        tick = section("function mechanics.TickRaidTargetScanner(",
                       "local function SCB_BossModsTrackCombatState(")
        for marker in ("SCB_BossModsPruneScanRequests()",
                       "not next(raidTargetScanner.requests)",
                       "raidTargetScanner.elapsed = 0",
                       "raidTargetScanner.sideElapsed = 0",
                       "raidTargetScanner.elapsed >= 0.025",
                       'n > 0 and "raid" or "party"',
                       'SCB_BossModsVisitScanToken(base .. "target")',
                       'SCB_BossModsVisitScanToken(base .. "targettarget")',
                       'SCB_BossModsVisitScanToken("mouseover")',
                       'SCB_BossModsVisitScanToken("targettarget")',
                       'SCB_BossModsVisitScanToken("target")'):
            self.assertIn(marker, tick)
        self.assertIn("SCB_BossModsVisitScanToken(\"target\")",
                      section("local function SCB_BossModsPlayerTargetChanged(",
                              "local function SCB_BossModsGroupCombat("))
        self.assertIn("engine.ClearRaidTargetObservations()",
                      section("local function SCB_BossModsRefreshZone(",
                              "local function SCB_BossModsPlayerTargetChanged("))


if __name__ == "__main__":
    unittest.main()
