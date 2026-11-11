-- Hunter Pet Codex - combat roles per pet family
-- Ratings are 0-100 and compare families within one game version. They're a
-- guide-based judgement (Icy Veins, Warcraft Tavern, Blizzard's Forever notes,
-- 2012-2026 pet utility tables), not simulated numbers.
--   dps     = damage / raid damage value
--   tank    = solo tanking and survivability
--   support = heals, battle res, Bloodlust, party buffs
-- note = what the family brings
local _, ns = ...

ns.ROLE_DATA = {}

------------------------------------------------------------------------
-- Mists of Pandaria Classic
-- Every pet can switch between Ferocity (damage), Tenacity (tank) and
-- Cunning (PvP), and all families do the same base damage. What sets a
-- family apart is the buff, debuff or special ability it brings.
------------------------------------------------------------------------
ns.ROLE_DATA.mop = {
    specNote = "Any pet can use Ferocity (DPS), Tenacity (tank) or Cunning (PvP), so the family's ability is what matters.",
    [1]   = { dps = 92, tank = 55, support = 70, note = "Furious Howl: 5% crit raid buff. Top pick for Marksmanship and Survival." },
    [2]   = { dps = 86, tank = 55, support = 65, note = "Roar of Courage: Mastery raid buff. Prowl." },
    [3]   = { dps = 70, tank = 55, support = 50, note = "Web: 5 sec root." },
    [4]   = { dps = 66, tank = 82, support = 60, note = "Demoralizing Roar: Weakened Blows, so enemies hit softer." },
    [5]   = { dps = 86, tank = 70, support = 55, note = "Gore: 4% physical damage taken debuff." },
    [6]   = { dps = 68, tank = 70, support = 45, note = "Ankle Crack: 50% slow." },
    [7]   = { dps = 66, tank = 80, support = 60, note = "Demoralizing Screech: Weakened Blows debuff." },
    [8]   = { dps = 66, tank = 72, support = 45, note = "Pin: 4 sec root." },
    [9]   = { dps = 68, tank = 74, support = 50, note = "Pummel: interrupt." },
    [11]  = { dps = 80, tank = 55, support = 55, note = "Tear Armor: Weakened Armor debuff." },
    [12]  = { dps = 80, tank = 60, support = 55, note = "Dust Cloud: Weakened Armor debuff." },
    [20]  = { dps = 68, tank = 72, support = 45, note = "Clench: 10 sec disarm." },
    [21]  = { dps = 60, tank = 96, support = 45, note = "Shell Shield: 50% damage reduction for 12 sec. Best solo tank." },
    [24]  = { dps = 68, tank = 55, support = 45, note = "Sonic Blast: 2 sec stun." },
    [25]  = { dps = 84, tank = 55, support = 70, note = "Cackling Howl: 10% haste raid buff." },
    [26]  = { dps = 68, tank = 55, support = 45, note = "Snatch: 10 sec disarm." },
    [27]  = { dps = 80, tank = 55, support = 55, note = "Lightning Breath: 5% magic damage taken debuff." },
    [30]  = { dps = 80, tank = 55, support = 55, note = "Fire Breath: 5% magic damage taken debuff." },
    [31]  = { dps = 86, tank = 60, support = 55, note = "Ravage: 4% physical damage taken debuff." },
    [32]  = { dps = 68, tank = 60, support = 45, note = "Time Warp: slow. Blinks to its target." },
    [33]  = { dps = 74, tank = 55, support = 70, note = "Spore Cloud: slower casting debuff. Spell haste buff." },
    [34]  = { dps = 68, tank = 55, support = 45, note = "Nether Shock: interrupt." },
    [35]  = { dps = 84, tank = 55, support = 70, note = "Serpent's Swiftness: 10% haste raid buff." },
    [37]  = { dps = 68, tank = 55, support = 45, note = "Serenity Dust: interrupt and silence." },
    [38]  = { dps = 74, tank = 55, support = 50, note = "Exotic. Froststorm Breath: AoE damage and slow." },
    [39]  = { dps = 88, tank = 60, support = 70, note = "Exotic. Terrifying Roar: crit buff. Monstrous Bite: Mortal Wounds." },
    [41]  = { dps = 70, tank = 86, support = 72, note = "Exotic. Qiraji Fortitude: Stamina raid buff. Strong tank." },
    [42]  = { dps = 84, tank = 84, support = 55, note = "Exotic. Acid Spit: physical damage taken debuff. Burrow Attack: AoE." },
    [43]  = { dps = 86, tank = 86, support = 55, note = "Exotic. Stampede: physical damage taken debuff, knockback." },
    [44]  = { dps = 68, tank = 55, support = 45, note = "Sting: 2 sec stun." },
    [45]  = { dps = 98, tank = 60, support = 95, note = "Exotic. Ancient Hysteria: Bloodlust. Lava Breath: slow casting. Top pick for Beast Mastery." },
    [46]  = { dps = 90, tank = 60, support = 100, note = "Exotic. Spirit Mend: heals you or the pet. Spirit Beast Blessing: Mastery buff. Best healer." },
    [50]  = { dps = 70, tank = 55, support = 55, note = "Tailspin: slower casting debuff." },
    [51]  = { dps = 68, tank = 55, support = 45, note = "Bad Manner: 4 sec blind." },
    [52]  = { dps = 68, tank = 55, support = 45, note = "Lock Jaw: 4 sec root." },
    [53]  = { dps = 60, tank = 94, support = 45, note = "Harden Carapace: 50% damage reduction for 12 sec." },
    [55]  = { dps = 74, tank = 88, support = 80, note = "Exotic. Embrace of the Shale Spider: 5% stats raid buff. Web Wrap stun." },
    [125] = { dps = 68, tank = 55, support = 50, note = "Lullaby: sleep." },
    [126] = { dps = 80, tank = 55, support = 78, note = "Exotic. Still Water: spell power and crit raid buff. Surface Trot: water walking." },
    [127] = { dps = 68, tank = 55, support = 45, note = "Paralyzing Quill: AoE incapacitate." },
    [128] = { dps = 86, tank = 82, support = 92, note = "Exotic. Eternal Guardian: battle res. Fearless Roar: crit buff." },
    [129] = { dps = 70, tank = 72, support = 50, note = "Trample: slower casting debuff." },
    [130] = { dps = 60, tank = 94, support = 45, note = "Stone Scales: 50% damage reduction for 12 sec. Petrifying Gaze: stun." },
    [138] = { dps = 70, tank = 78, support = 45, note = "Trample. Sturdy tank." },
}

------------------------------------------------------------------------
-- WoW: Forever
-- Families are Offensive, Balanced or Defensive (Blizzard: offensive =
-- more damage, less tanking), and each has one unique ability. Pets scale
-- with your gear. Forever is in beta, so expect tuning changes.
------------------------------------------------------------------------
ns.ROLE_DATA.forever = {
    specNote = "Offensive families hit harder, Defensive families tank better, Balanced sit in between.",
    [1]  = { dps = 76, tank = 66, support = 88, type = "Balanced",  note = "Furious Howl: raises your party's melee attack power." },
    [2]  = { dps = 95, tank = 40, support = 40, type = "Offensive", note = "Prowl: stealth opener with bonus damage. Top damage." },
    [3]  = { dps = 86, tank = 40, support = 45, type = "Offensive", note = "Web: root plus damage over time." },
    [4]  = { dps = 58, tank = 92, support = 40, type = "Defensive", note = "Swipe: hits 3 targets, so it holds threat on packs." },
    [5]  = { dps = 60, tank = 86, support = 40, type = "Defensive", note = "Charge: closes the gap, roots and boosts its next attack." },
    [6]  = { dps = 58, tank = 82, support = 55, type = "Defensive", note = "Dismember: 50% healing reduction on the target." },
    [7]  = { dps = 72, tank = 70, support = 70, type = "Balanced",  note = "Demoralizing Screech: AoE damage and lowers enemy attack power." },
    [8]  = { dps = 56, tank = 84, support = 40, type = "Defensive", note = "Pinch: damage and slow." },
    [9]  = { dps = 60, tank = 90, support = 40, type = "Defensive", note = "Thunderstomp: AoE damage for multi-target threat." },
    [11] = { dps = 92, tank = 40, support = 40, type = "Offensive", note = "Savage Rend: bleed over time." },
    [12] = { dps = 58, tank = 82, support = 65, type = "Defensive", note = "Dust Cloud: lowers the target's armor." },
    [20] = { dps = 64, tank = 80, support = 40, type = "Defensive", note = "Scorpid Poison: stacking damage over time." },
    [21] = { dps = 52, tank = 98, support = 40, type = "Defensive", note = "Shell Shield: big damage reduction for 12 sec. Best tank." },
    [24] = { dps = 86, tank = 40, support = 55, type = "Offensive", note = "Sonic Blast: damage and slows spellcasting." },
    [25] = { dps = 74, tank = 66, support = 45, type = "Balanced",  note = "Tendon Rip: slow plus bleed." },
    [26] = { dps = 86, tank = 40, support = 50, type = "Offensive", note = "Mine!: damage and disarm." },
    [27] = { dps = 92, tank = 40, support = 40, type = "Offensive", note = "Lightning Breath: 20-yard ranged attack." },
    [45] = { dps = 90, tank = 40, support = 40, type = "Offensive", note = "Lava Breath." },
    [50] = { dps = 88, tank = 45, support = 40, type = "Offensive", note = "Trickster's Dance: more dodge and attack speed for 12 sec. New in Forever." },
}

ns.ROLE_DATA.unknown = { dps = 50, tank = 50, support = 40, note = "No combat data for this family yet." }

-- Roles a family counts as (used for filtering): rating 80+ or the best
-- role of a family that has no 80+ rating.
local ROLE_THRESHOLD = 80
function ns.FamilyRole(familyId)
    local set = ns.ROLE_DATA[ns.flavor] or ns.ROLE_DATA.mop
    return set[familyId] or ns.ROLE_DATA.unknown
end

function ns.LookRoles(look)
    local r = ns.FamilyRole(look.family)
    local roles = {}
    if r.dps >= ROLE_THRESHOLD then roles.dps = true end
    if r.tank >= ROLE_THRESHOLD then roles.tank = true end
    if r.support >= ROLE_THRESHOLD then roles.support = true end
    if not next(roles) then
        local best, bv = "dps", r.dps
        if r.tank > bv then best, bv = "tank", r.tank end
        if r.support > bv then best = "support" end
        roles[best] = true
    end
    return roles, r
end

ns.ROLE_INFO = {
    dps     = { label = "DPS",     color = "ff7f50", icon = "Interface\\Icons\\Ability_Hunter_BeastCall" },
    tank    = { label = "Tank",    color = "6fa8dc", icon = "Interface\\Icons\\Ability_Defend" },
    support = { label = "Support", color = "8fd16a", icon = "Interface\\Icons\\Spell_Nature_HealingTouch" },
}

function ns.RoleSummary(look, compact)
    local roles, r = ns.LookRoles(look)
    local parts = {}
    for _, key in ipairs({ "dps", "tank", "support" }) do
        local info = ns.ROLE_INFO[key]
        local val = r[key]
        local txt = ("%s %d"):format(info.label, val)
        if roles[key] then txt = ("|cff%s%s|r"):format(info.color, txt) else txt = "|cff888888" .. txt .. "|r" end
        parts[#parts + 1] = txt
    end
    return table.concat(parts, compact and " " or "  -  "), r
end
