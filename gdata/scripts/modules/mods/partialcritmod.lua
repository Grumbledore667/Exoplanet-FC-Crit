local stringx = require "pl.stringx"
local loadmodoptions = require "mods.modoptions"
local random = require "random"
local ItemsData    = require "itemsData"
local MinMaxChance =
{
    ["flaregun.gun"] =
    {
        MinHitChance = 2,
        MaxHitChance = 2,
        hits = 0,
        Type = "Melee",
    },
    ["abori_axe.wpn"] =
    {
        MinHitChance = 2,
        MaxHitChance = 2,
        hits = 0,
        Type = "Melee",
    },
    ["axe.wpn"] =
    {
        MinHitChance = 2,
        MaxHitChance = 2,
        hits = 0,
        Type = "Melee",
    },
    ["abori_knife.wpn"] =
    {
        MinHitChance = 2,
        MaxHitChance = 2,
        hits = 0,
        Type = "Melee",
    },
    ["abori_bat.wpn"] =
    {
        MinHitChance = 2,
        MaxHitChance = 2,
        hits = 0,
        Type = "Melee",
    },
    ["cannibal_spoon.wpn"] =
    {
        MinHitChance = 2,
        MaxHitChance = 2,
        hits = 0,
        Type = "Melee",
    },
    ["cleaver.wpn"] =
    {
        MinHitChance = 2,
        MaxHitChance = 2,
        hits = 0,
        Type = "Melee",
    },
    ["family_relic.wpn"] =
    {
        MinHitChance = 2,
        MaxHitChance = 2,
        hits = 0,
        Type = "Melee",
    },
    ["machete.wpn"] =
    {
        MinHitChance = 2,
        MaxHitChance = 2,
        hits = 0,
        Type = "Melee",
    },
    ["pickaxe.wpn"] =
    {
        MinHitChance = 2,
        MaxHitChance = 2,
        hits = 0,
        Type = "Melee",
    },
    ["pipe.wpn"] =
    {
        MinHitChance = 2,
        MaxHitChance = 2,
        hits = 0,
        Type = "Melee",
    },
    ["shovel.wpn"] =
    {
        MinHitChance = 2,
        MaxHitChance = 2,
        hits = 0,
        Type = "Melee",
    },
    ["wodden_bat.wpn"] =
    {
        MinHitChance = 2,
        MaxHitChance = 2,
        hits = 0,
        Type = "Melee",
    },
    ["sledgehammer.wpn"] =
    {
        MinHitChance = 2,
        MaxHitChance = 2,
        hits = 0,
        Type = "Melee",
    },
    ["hand_to_hand.wpn"] =
    {
        MinHitChance = 2,
        MaxHitChance = 5,
        hits = 0,
        Type = "Melee",
    },

    ["beacon_light.wpn"] =
    {
        MinHitChance = 2,
        MaxHitChance = 2,
        hits = 0,
        Type = "Melee",
    },

    ["alien_cactus_bat.wpn"] =
    {
        MinHitChance = 2,
        MaxHitChance = 2,
        hits = 0,
        Type = "Melee",
    },

    ["revolver.gun"] =
    {
        MinHitChance = 1,
        MaxHitChance = 0,
        hits = 0,
        Type = "Ranged",
    },
    ["scamp_22.gun"] =
    {
        MinHitChance = 1,
        MaxHitChance = 0,
        hits = 0,
        Type = "Ranged",
    },
    ["scamp_22_shock.gun"] =
    {
        MinHitChance = 5,
        MaxHitChance = 5,
        hits = 0,
        Type = "Ranged",
    },
    ["abori_gun_pistol.gun"] =
    {
        MinHitChance = 1,
        MaxHitChance = 0,
        hits = 0,
        Type = "Ranged",
    },
    ["abori_gun_rifle.gun"] =
    {
        MinHitChance = 1,
        MaxHitChance = 0,
        hits = 0,
        Type = "Ranged",
    },
    ["abori_gun_mortar.gun"] =
    {
        MinHitChance = 1,
        MaxHitChance = 0,
        hits = 0,
        Type = "Ranged",
    },
    ["shotgun.gun"] =
    {
        MinHitChance = 10,
        MaxHitChance = 10,
        hits = 0,
        Type = "Ranged",
    },
    ["howdah.gun"] =
    {
        MinHitChance = 10,
        MaxHitChance = 10,
        hits = 0,
        Type = "Ranged",
    },
    ["carbine.gun"] =
    {
        MinHitChance = 1,
        MaxHitChance = 0,
        hits = 0,
        Type = "Ranged",
    },
    ["kabarog_hsg.gun"] =
    {
        MinHitChance = 10,
        MaxHitChance = 10,
        hits = 0,
        Type = "Ranged",
    },
}

local difficulty =
{
    ["Easy"] =
    {
        MinChance = 0,
        MaxChance = 40,
    },
    ["Normal"] =
    {
        MinChance = 0,
        MaxChance = 0,
    },
    ["DIE"] =
    {
        MinChance = 40,
        MaxChance = 0,
    },
}

local partialcritmod = {
    basevalue = 25,
    p = nil,
    randmin = 0,
    randbase = 100,
    diffvalue = nil,
    modenabled = nil,
    critenabled = nil,
    partialenabled = nil,
    randresult = nil,
    color = "",
    impactPos = nil,
}

function partialcritmod:playershot(item, bullets)
    settingdefaults()
    local minhit = 0
    local maxhit = 0
    local hits = 0
    if item and MinMaxChance[item] then
        minhit = MinMaxChance[item].MinHitChance
        maxhit = MinMaxChance[item].MaxHitChance
        hits = MinMaxChance[item].hits
    end
    if partialcritmod.modenabled == true then
        --partial hit
        if partialcritmod.randresult <= (partialcritmod.basevalue + partialcritmod.randmin + minhit) and partialcritmod.partialenabled == true then
            partialcritmod.randresult = nil
            local modifier = getGlobalParam("dmgOutgoingMultiplier") - (random.random(2,5)/10)
            partialcritmod.color = stringx.split(loadmodoptions:retrieveValue("grumbleshitmod.lua", "PartialHit Color"), "]")[1] .. "]"
            return modifier
        end
        --crit hit
        if partialcritmod.randresult >= (partialcritmod.randbase - partialcritmod.basevalue - partialcritmod.randmin - maxhit) and partialcritmod.critenabled == true then
            partialcritmod.randresult = nil
            local modifier = getGlobalParam("dmgOutgoingMultiplier") + (random.random(2,7)/10)
            partialcritmod.color = stringx.split(loadmodoptions:retrieveValue("grumbleshitmod.lua", "CritHit Color"), "]")[1] .. "]"
            return modifier
        end
    end
    partialcritmod.randresult = nil
    local modifier = getGlobalParam("dmgOutgoingMultiplier")
    partialcritmod.color = "[colour='FFFFFFFF']"
    return modifier
end

function partialcritmod:npcshot(item)
    settingdefaults()
    local minhit = 0
    local maxhit = 0
    if item and MinMaxChance[item] then
        minhit = MinMaxChance[item].MinHitChance
        maxhit = MinMaxChance[item].MaxHitChance
    else
        minhit = 2
        maxhit = 2
    end
    if partialcritmod.modenabled == true then
        if partialcritmod.randresult <= (partialcritmod.basevalue - partialcritmod.randmin - minhit) and partialcritmod.partialenabled == true then
            partialcritmod.randresult = nil
            local modifier = getGlobalParam("dmgOutgoingMultiplier") - (random.random(2,5)/10)
            return modifier
        end
        if partialcritmod.randresult >= (partialcritmod.randbase - partialcritmod.basevalue + partialcritmod.randmin + maxhit) and partialcritmod.critenabled == true then
            partialcritmod.randresult = nil
            local modifier = getGlobalParam("dmgOutgoingMultiplier") - (random.random(2,5)/10)
            return modifier
        end
        partialcritmod.randresult = nil
        local modifier = getGlobalParam("dmgOutgoingMultiplier")
        return modifier
    end

end

function partialcritmod:returnhits()
    local s = {}
    for k,v in pairs(MinMaxChance) do
        s[k] = v.hits
    end
    return s
end

function partialcritmod:addhit(item)
    if MinMaxChance[item] then
        MinMaxChance[item].hits = MinMaxChance[item].hits + 1
        local gun = getPlayer():getWeaponSlotItem()
        if returnWeaponType(item) ~= "Melee" then
            local currentaccuracy = ItemsData.getItemAccuracy(gun:getItemName())
            gun:setAccuracy(currentaccuracy + partialcritmod:AccuracyBonus(item))
        else
            --Preps for melee bonus
        end

    end
end

function partialcritmod:hits(item)
    return MinMaxChance[item].hits
end

function partialcritmod:loadhits(key, value)
    MinMaxChance[key].hits = value
end

function partialcritmod:nextLevel(level)
    local exponent = 1.5
    local baseXP = 10
    return math.floor(baseXP * (level ^ exponent))
end

function partialcritmod:currentWPNLevel(hits)
    local i = 1
    while(hits >= partialcritmod:nextLevel(i)) do
        i = i + 1
    end
    return i-1
end

function partialcritmod:AccuracyBonus(item)
    local bonus = 0
    if MinMaxChance[item] then
        if partialcritmod:currentWPNLevel(MinMaxChance[item].hits) > 0 then
            bonus = 0.0001 * partialcritmod:currentWPNLevel(MinMaxChance[item].hits)
        end
    end
    return bonus
end

function partialcritmod:StaminaBonus(item)
    local bonus = 0
    if MinMaxChance[item] then
        local currentWPNLevel = partialcritmod:currentWPNLevel(MinMaxChance[item].hits)
        if currentWPNLevel > 0 then
            bonus = currentWPNLevel * 0.1
            partialcritmod:extLogOut("StaminaBonus: ", bonus)
            if bonus >= 4 then
                bonus = 4
            end
        end
    end
    return bonus
end

function partialcritmod:itemInfoBaseStats(item)
    local baseStats = ""
    if ItemsData.isItemWeapon(item) then
        local nextLevel = xpToNextLvL(item)
        baseStats = string.format("%s%s%d%s%d%s", "-------------Usage Stats-------------\n","WeaponLVL: ", partialcritmod:currentWPNLevel(partialcritmod:hits(item)),"\nXp to next Level: ", nextLevel, gameplayUI.whiteTag)
    end
    return baseStats
end

function partialcritmod:wpnInfoStats(item)
    local wpnStats = ""
    if ItemsData.isItemWeapon(item) then
        if returnWeaponType(item) ~= "Melee" then
            wpnStats = string.format("%s%s%.4f%s","\nAccuracyBonus: -", gameplayUI.damageColorTags.physical, partialcritmod:AccuracyBonus(item), gameplayUI.whiteTag)
        else
            wpnStats = string.format("%s%s%.4f%s","\nStamina Reduction: -", gameplayUI.damageColorTags.physical, partialcritmod:AccuracyBonus(item), gameplayUI.whiteTag)
        end
    end
    return wpnStats
end

function returnWeaponType(item)
    return MinMaxChance[item].Type
end

function xpToNextLvL(itemName)
    local xpRequired = partialcritmod:nextLevel(partialcritmod:currentWPNLevel(partialcritmod:hits(itemName))+1)-partialcritmod:hits(itemName)
    return xpRequired
end

function settingdefaults()
    partialcritmod.diffvalue = stringx.split(loadmodoptions:retrieveValue("grumbleshitmod.lua", "Difficulty"), "]")[2]
    partialcritmod.modenabled = loadmodoptions:retrieveValue("grumbleshitmod.lua", "Activate/Deactivate Mod")
    partialcritmod.critenabled = loadmodoptions:retrieveValue("grumbleshitmod.lua", "Use Critical hit")
    partialcritmod.partialenabled = loadmodoptions:retrieveValue("grumbleshitmod.lua", "Use Partial hit")
    partialcritmod.p = getPlayer()
    local currentstam = partialcritmod.p:getStatPercent( "stamina" )
    if currentstam > currentstam * 0.75 then
        partialcritmod.randmin = 0
    elseif currentstam <= currentstam * 0.75 then
        partialcritmod.randmin = 5
    elseif currentstam <= currentstam * 0.5 then
        partialcritmod.randmin = 10
    elseif currentstam <= currentstam * 0.25 then
        partialcritmod.randmin = 20
    end
    partialcritmod.randresult = random.random(0 + difficulty[partialcritmod.diffvalue].MaxChance, partialcritmod.randbase - difficulty[partialcritmod.diffvalue].MinChance)

end

function partialcritmod:extLogOut(logname, logvalue)
    log("-------------------------ModLog-------------------------\n\n\n")
    log(logname..": "..logvalue.."\n\n\n")
    log("-------------------------EndLog-------------------------")
end

return partialcritmod

