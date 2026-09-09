-- SoloCraft Bots - additional Vanilla role evidence.
-- Shield Slam is a high-signal Warrior tank ability and should count toward the
-- same three-observation confirmation threshold as the existing tank catalogue.

SoloCraftBots = SoloCraftBots or {}
local SCB = SoloCraftBots

local SCB_SHIELD_SLAM_SOURCE_PATTERNS = {
    "^(.-) begins to cast",
    "^(.-) casts",
    "^(.-)'s ",
    "^(.-) gains",
    "^(.-) deals",
    "^(.-) hits",
    "^(.-) heals",
    "^(.-) crits",
}

local function SCB_NormalizeShieldSlamName(name)
    local result, i, char
    if type(name) ~= "string" then return nil end
    result = ""
    for i = 1, string.len(name) do
        char = string.sub(name, i, i)
        if (char >= "a" and char <= "z") or (char >= "A" and char <= "Z")
            or (char >= "0" and char <= "9") or char == "*" then
            result = result .. string.lower(char)
        end
    end
    if result == "" then return nil end
    return result
end

local function SCB_ExtractShieldSlamSource(text)
    local i, _, _, name
    for i = 1, table.getn(SCB_SHIELD_SLAM_SOURCE_PATTERNS) do
        _, _, name = string.find(text, SCB_SHIELD_SLAM_SOURCE_PATTERNS[i])
        if name and name ~= "" then return name end
    end
    return nil
end

local function SCB_FindShieldSlamWarrior(sourceName)
    local wanted = SCB_NormalizeShieldSlamName(sourceName)
    local members = SCB_CollectGroupMembers and SCB_CollectGroupMembers() or {}
    local i, member, _, classFile
    if not wanted then return nil end

    for i = 1, table.getn(members) do
        member = members[i]
        if member and member.isBot and member.name
            and SCB_NormalizeShieldSlamName(member.name) == wanted then
            if UnitClass and member.unit then _, classFile = UnitClass(member.unit) end
            if classFile and string.lower(classFile) == "warrior" then
                return member.name
            end
            return nil
        end
    end
    return nil
end

local SCB_073PreviousHandleRoleCombatText = SCB_HandleRoleCombatText
if SCB_073PreviousHandleRoleCombatText then
    function SCB_HandleRoleCombatText(text, eventName)
        local handled = SCB_073PreviousHandleRoleCombatText(text, eventName)
        local source, name
        if handled then return true end
        if type(text) ~= "string" or not string.find(text, "Shield Slam", 1, true) then
            return false
        end

        source = SCB_ExtractShieldSlamSource(text)
        if not source then return false end
        name = SCB_FindShieldSlamWarrior(source)
        if not name or not SCB_AddBotRoleEvidence then return false end

        SCB_AddBotRoleEvidence(name, "warrior", "tank", "Shield Slam", eventName)
        return true
    end
end
