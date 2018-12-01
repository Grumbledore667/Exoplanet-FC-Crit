--Mod Stuff
local stringx = require "pl.stringx"
local loadmodoptions = require "mods.modoptions"
local ItemsData = (require "itemsData")
local random = require "random"
local MinMaxChance =
{
   ["flaregun.gun"] =
   {
      	 MinHitChance = 2,
		 MaxHitChance = 2,
      
   },

   ["hand_to_hand.wpn"] =
   {
       MinHitChance = 2,
       MaxHitChance = 5,
	  
   },

   ["beacon_light.wpn"] =
   {
      	 MinHitChance = 2,
		 MaxHitChance = 2,
      
   },

   ["alien_cactus_bat.wpn"] =
   {
      	 MinHitChance = 2,
		 MaxHitChance = 2,
      
   },

   ["revolver.gun"] =
   {
      	 MinHitChance = 1,
		 MaxHitChance = 0,
      
   },
   ["scamp_22.gun"] =
   {
      	 MinHitChance = 1,
		 MaxHitChance = 0,
      
   },
   ["scamp_22_shock.gun"] =
   {
      	 MinHitChance = 5,
		 MaxHitChance = 5,
      
   },
   ["abori_gun_pistol.gun"] =
   {
      	 MinHitChance = 1,
		 MaxHitChance = 0,
      
   },
   ["abori_gun_rifle.gun"] =
   {
      	 MinHitChance = 1,
		 MaxHitChance = 0,
      
   },
   ["abori_gun_mortar.gun"] =
   {
      	 MinHitChance = 1,
		 MaxHitChance = 0,
      
   },
   ["shotgun.gun"] =
   {
      	 MinHitChance = 10,
		 MaxHitChance = 10,
      
   },
   ["howdah.gun"] =
   {
      	 MinHitChance = 10,
		 MaxHitChance = 10,
      
   },
   ["carbine.gun"] =
   {
      	 MinHitChance = 1,
		 MaxHitChance = 0,
      
   },
   ["kabarog_hsg.gun"] =
   {
      	 MinHitChance = 10,
		 MaxHitChance = 10,
 
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
}

function partialcritmod:playershot(item)
	settingdefaults()
	local minhit = 0
	local maxhit = 0
	if item then
	 minhit = MinMaxChance[item].MinHitChance
	 maxhit = MinMaxChance[item].MaxHitChance
	else
	 minhit = 0
	 maxhit = 0
	end
	if partialcritmod.modenabled == true then
	 --partial hit
	 if partialcritmod.randresult <= (partialcritmod.basevalue + partialcritmod.randmin + minhit) and partialcritmod.partialenabled == true then
       partialcritmod.randresult = nil
	   local modifier = getGlobalParam("dmgOutgoingMultiplier") - (random.random(2,5)/10)
	   partialcritmod.color = "[colour='FFFF0000']"
	   return modifier     		
	 end
	 --crit hit
	 if partialcritmod.randresult >= (partialcritmod.randbase - partialcritmod.basevalue - partialcritmod.randmin - maxhit) and partialcritmod.critenabled == true then
       partialcritmod.randresult = nil
	   local modifier = getGlobalParam("dmgOutgoingMultiplier") + (random.random(2,7)/10)
	   partialcritmod.color = "[colour='FF00FF00']"
       return modifier     		
     end
	end
<<<<<<< HEAD
	partialcritmod.randresult = nil
=======
	
>>>>>>> a08c0faae379b22631b6978bcb700c5d65339dd4
	local modifier = getGlobalParam("dmgOutgoingMultiplier")
	partialcritmod.color = "[colour='FFFFFFFF']"
	return modifier

end

function partialcritmod:npcshot(item)
	settingdefaults()
	local minhit = 0
	local maxhit = 0
	if item then
	 minhit = MinMaxChance[item].MinHitChance
	 maxhit = MinMaxChance[item].MaxHitChance
	else
	 minhit = 0
	 maxhit = 0
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

return partialcritmod

