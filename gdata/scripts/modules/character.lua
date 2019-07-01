local oo = require "loop.multiple"
local clone = (require "loop.proto").clone
local _rootCharacter = (require "roots")._rootCharacter
local CStatusEffectsManager = require "statusEffectsManager"
local CSenseScheduler = (require "senseScheduler").CSenseScheduler
local CNotificationCenter = (require "notificationCenter").CNotificationCenter
local CEventManager = require "eventManager"
local CAnimationsManager = (require "animationsManager").CAnimationsManager
local CSoundManager = (require "soundManager").CSoundManager
local CInteractable = require "mixins.interactable"
local CDestroyable = require "mixins.destroyable"
--+++++++++++++++++++++++++++++++++++++++++ Mod +++++++++++++++++++++++++++++++++++++++++++++
local CritPartialMod  = require "mods.partialcritmod"
--+++++++++++++++++++++++++++++++++++++++++ /Mod ++++++++++++++++++++++++++++++++++++++++++++
local GuildAttitudes  = require "guildAttitudes"
local Attitudes       = GuildAttitudes.Attitudes
local getAttitude     = GuildAttitudes.getAttitude
local isValidGuild    = GuildAttitudes.isValidGuild

local ObjectsLabels = (require "objectsLabels")
local Appearance = (require "appearance")

local ai = require "ai"

local CInventories = { basic = require "inventoryBase",
                       player = require "inventoryPlayer",
                       slotted = require "inventorySlotted",
                       turret = require "inventoryTurret", }

local CCharacterStatModified = require "characterStatModified"
local CCharacterStatSimple = require "characterStatSimple"

local f = require "fun"
local partial = f.partial
local tablex = require "pl.tablex"
local hlp = require "helpers"

local isNaN = (require "global.debug").isNaN

---@class CCharacter : shCharacter
---@field parameters table<string, any>
---@field states table<string, boolean>
---@field animationsManager CAnimationsManager
---@field protected guild string
---@field protected attitudeToMainCharacter
---@field protected hasNoEnemiesOverride
local CCharacter = oo.class({
   disabled           = false,
   states             = nil,
   subscribersOnDeath = nil,
   spawnPos           = nil,
   triggers           = nil,
   immortality        = nil,
   dialogAnimationAllowed = true,
   spawnCorpseDummy = true,
   inventoryType      = "slotted",
   highlightingAllowed = false,

}, _rootCharacter, CInteractable, CDestroyable)

---First thing that gets called upon creation
--OnCreate():
--   loadDynamicParameters()
--   init()
--      loadParameters()
--         getDefaultParameters()
function CCharacter:OnCreate(params)
   self.safePosition = self:getPose():getPos()
   getmetatable(self)["__tostring"] = function(t) return t:getDescriptiveName() end

   if params then
      self:loadDynamicParameters(params)
   end
   CDestroyable.OnCreate(self)

   CInteractable.OnCreate(self)
   self.interactor:setRaycastRadius(300)
   self.interactor:setRaycastActive(false)

   if self.inventoryType then
      ---@type CInventoryBase | CInventorySlotted | CInventoryPlayer | CInventoryTurret
      self.inventory = CInventories[self.inventoryType]{}
      self.inventory:init(self)
      self:getInventory():subscribeOnChange(partial(self.OnInventoryChange, self))
      self:getInventory():subscribeOnChange(partial(self.OnItemEquip, self))
      self:getInventory():subscribeOnChange(partial(self.OnItemUnequip, self))
   end

   self:init()

   self:resetTarget()
   self:stopMove()

   self:setOrientationSpeed(self.parameters.orientationSpeed or 300)
end

---First parameters loading from installer/spawn
function CCharacter:loadDynamicParameters(params)
   if params.installer then
      self:setInstaller(params.installer)
   end
end

---Init components, setup timers and call loadParameters
function CCharacter:init()
   self.notificationCenter = CNotificationCenter{ owner = self }
   self.notificationCenter:init()

   self.eventManager = CEventManager()

   self.statusEffectsManager = CStatusEffectsManager{ owner = self }
   self.statusEffectsManager:init()

   self.animationsManager = CAnimationsManager{ owner = self }
   self.animationsManager:init()

   self.animations = self.animationsManager:getAnimations()

   self.soundManager = CSoundManager{owner=self}
   self.soundManager:init()

   self.senseScheduler = CSenseScheduler{ owner = self }
   self.senseScheduler:init()

   self.states             = {}
   self.blackboard         = {}
   self.subscribersOnDeath = {}
   self.spawnPos           = vec3Zero()
   self.triggers           = {}
   self.triggersVisited    = {}

   self:setGuild("GLD_PLAYER")
   self:setFeelVisible(true)

   self.killer = nil

   -- filter out all junk
   for param, val in pairs(self.parameters) do
      if val == "" then
         self.parameters[param] = nil
      end
   end
   self:loadParameters()

   self.defaultTimerFrequency = 1/10
   self:setupTimers(self.defaultTimerFrequency)

   self:setSpawnPos(self:getPose():getPos())

   self:initLookAtData()
end

---Second and main parameters loading
function CCharacter:loadParameters()
   self.parameters = clone(self:getDefaultParameters(), self.parameters)

   self:setHeadLookingAllowed(loadParam(self, "headLooking", true))
   self.headLookingLimits = {x=30, y=50, z=0}

   self.stats = {}
   self.regeneratingStats = {}
   local healthMax = loadParam(self, "healthMax", 100)
   local stats = {
      armor     = {baseValue = 0},
      healthMax = {baseValue = healthMax, min = 1},
      health    = {value = healthMax, min = 0, max = "healthMax", regen = 0},
   }
   self:initializeStats(stats)

   self.style = { body = {}, attachments = {}, textures = {} }
   self.hasNoEnemiesOverride = loadParam(self, "hasNoEnemiesOverride")
   self.attitudeToMainCharacter = loadParam(self, "attitudeToMainCharacter")
end

---Default parameters table "getter"
function CCharacter:getDefaultParameters()
   local parameters = {}
   parameters.orientationSpeed = 300
   parameters.maxLandingSpeed  = 750
   parameters.weaponSlotId     = 1
   parameters.zoneSize         = 1000 -- 10 meters

   parameters.viewDist         = 2000  -- 20 meters
   parameters.backViewDist     = 1000  -- 10 meters
   parameters.viewAngle        = 180

   parameters.attackDist       = 1000 -- 10 meters
   parameters.attackAngle      = 120

   return parameters
end

function CCharacter:initLookAtData()
   self.lookAtFactor = 0
   self.headBonePose = self:findBonePose("Head")

   if not self.headBonePose then
      self.headBonePose = self:findBonePose("head")
   end
end

function CCharacter:setupTimers(freq)
   self:stopTimers()

   self.senseScheduler.timer   = runTimer(freq, self.senseScheduler, self.senseScheduler.OnIdle, true)
end

function CCharacter:stopTimers()
   if self.senseScheduler.timer then
      self.senseScheduler.timer:stop()
      self.senseScheduler.timer = nil
   end
end

function CCharacter:createTree(path)
   self.BT = ai.utils.loadTree(path, self)
   self.BT:init()
   self.blackboard = {}
   self.BT:setBlackboard(self.blackboard)
end

function CCharacter:deleteBehaviorTree()
   if self.BT then
      self.BT:reset()
      self.BT = nil
   end
end

function CCharacter:requestBehaviorStart(name)
   if self.BT then
      self.BT:requestBehaviorStart(name)
   end
end

function CCharacter:requestBehaviorStop(name)
   if self.BT then
      self.BT:requestBehaviorStop(name)
   end
end

function CCharacter:getDescriptiveName()
   local name = self:getName()
   if not self:isManaged() then
      if self.installer then
         return string.format("'%s, spawn of %s'", self:getScriptClass(), self.installer:getName())
      end
   end
   return name
end

function CCharacter:isManaged()
   return self:getName() ~= "__unmanaged_npc" and self.installer == nil
end

function CCharacter:getOrientationGlobal()
   return getAnglesFromQuat(self:getPose():getRotQuat()).y
end

function CCharacter:setOrientationGlobal(angle)
   angle = angle or self:getOrientationGlobal()
   self:getPose():setRot({y=angle})
end

function CCharacter:setInstaller(obj)
   self.installer = obj
end

function CCharacter:getStatusEffectsManager()
   return self.statusEffectsManager
end

---@param item CItem
function CCharacter:applyItemEffects(item)
   local effects = item:getConsumeEffects()

   for _, effect in ipairs(effects) do
      self.statusEffectsManager:addStatusEffect(effect)
   end
end

function CCharacter:OnDestroy()
   CDestroyable.OnDestroy(self)
   self:stopSounds()
   self:stopTimers()
end

function CCharacter:OnLanding(landingSpeed)
   local deltaSpeed = (-landingSpeed) - self.parameters.maxLandingSpeed

   if deltaSpeed > 0 then
      self:hit(scaleValue(self:getStatCount("healthMax"), deltaSpeed, self.parameters.maxLandingSpeed))
   end

   self.eventManager:postEvent("OnLanding", landingSpeed)
   self.eventManager:postEvent("coroutineEvent", "OnLanding")

   self:animatedEvent("land")
   self:setState     ("inAir", false)
   self:setState     ("jumping", false)
end

function CCharacter:OnAir(dist)
   self:setState("inAir", true)
end

function CCharacter:OnSlideBegin()
end

function CCharacter:OnSlideEnd()
end

function CCharacter:OnStuckBegin()
   self:setState("isStuck", true)
end

function CCharacter:OnStuckEnd()
   self:setState("isStuck", false)
end

function CCharacter:OnTouchCharacter(obj)
   self:setState("isTouchingCharacter", true)
end

function CCharacter:OnUntouchCharacter(obj)
   self:setState("isTouchingCharacter", false)
end

function CCharacter:OnMoveAndOrientateStop()
   self.eventManager:postEvent("OnMoveAndOrientateStop")
end

-- when CCharacter hits params.target
function CCharacter:OnEnemyHit(params)
   self.eventManager:postEvent("OnEnemyHit", params)
   self.eventManager:postEvent("coroutineEvent", "OnEnemyHit")
end

function CCharacter:isDamageAllowed(charAttacker)
   if self.immortality == "immortal" or self.god_mode
      or (self.immortality == "protected" and charAttacker ~= getPlayer()) then
      return false
   end
   return true
end

function CCharacter:equipHatOnStart()
   for _, item in pairs(self:getInventory():getItems()) do
      if item:getAttireType() == "hat" then
         self:getInventory():equipSlotWithItem("hat", item:getId(), true)
         return
      end
   end
end

function CCharacter:equipAttireOnStart()
   local index = 0
   for _, item in pairs(self:getInventory():getItems()) do
      if index >= 4 then return end
      if item:getAttireType() == "top" and not self:getInventory():getSlotItem("top") then
         self:getInventory():equipSlotWithItem("top", item:getId(), true)
         index = index + 1
      elseif item:getAttireType() == "bottom" and not self:getInventory():getSlotItem("bottom") then
         self:getInventory():equipSlotWithItem("bottom", item:getId(), true)
         index = index + 1
      elseif item:getAttireType() == "shield" and not self:getInventory():getSlotItem("shield") then
         self:getInventory():equipSlotWithItem("shield", item:getId(), true)
         index = index + 1
      elseif item:getAttireType() == "gadget" and not self:getInventory():getSlotItem("gadget") then
         self:getInventory():equipSlotWithItem("gadget", item:getId(), true)
         index = index + 1
      end
   end
end

function CCharacter:hasShield()
   return self:getInventory():getSlotItem("shield") ~= nil
end

function CCharacter:getShieldItem()
   return self:getInventory():getSlotItem("shield")
end

function CCharacter:OnHit(params)
   -- impactor - damage source object (item)
   -- impactType - string (ranged, melee, explosion)
   -- impactPos - impact position
   -- impactForce - set by engine, can be changed
   -- impactRadius - set by engine, can be changed
   -- target - target object (character, rigid)
   -- targetType - target type (string) (character, rigid)
   -- interrupt - boolean, defaults to false. if set to true - stops hit event propagation

   local charAttacker, itemName, damageValue
   charAttacker = params.impactor:getObject()
   itemName = params.impactor:getItemName()
   damageValue = params.impactor:getDamage()

   local isPlayerAttacker = getPlayer() == charAttacker

   --TODO:FIXME: A projectile from a destroyed attacker won't hit and it probably should
   if not hlp.isOperable(charAttacker) or self:getState("dead") or not self:isDamageAllowed(charAttacker)
      or (self:isFriend(charAttacker) and not isPlayerAttacker and self ~= charAttacker.senseScheduler:getCurEnemy()) then
      params.interrupt = true
      return
   end

   -- TODO:FIXME: proper OnHit sequence refactor that allows items to have own additional
   -- logic, damage increase and reduction etc
   damageValue = damageValue * getGlobalParam("dmgMultiplier")
   if isPlayerAttacker then
      --+++++++++++++++++++++++++++++++++++++++++ Mod +++++++++++++++++++++++++++++++++++++++++++++
      local bulletsinshot = nil
      --check if melee or ranged
      if params.impactor.bulletsInShot == nil then
         bulletsinshot = 1
      else
         bulletsinshot = params.impactor.bulletsInShot
      end
      damageValue = damageValue * CritPartialMod:playershot(itemName, bulletsinshot)
      CritPartialMod:addhit(itemName)
      if CritPartialMod.color ~= "[colour='FFFFFFFF']" then
         CritPartialMod.impactPos = projectPointToScreen(params.impactPos)
         gameplayUI:showInfoTextEx(CritPartialMod.color .. tostring(round(damageValue, 0)), "hit", "")
      end
      --+++++++++++++++++++++++++++++++++++++++++ /Mod ++++++++++++++++++++++++++++++++++++++++++++
   elseif params.target == getPlayer() then
      --+++++++++++++++++++++++++++++++++++++++++ Mod +++++++++++++++++++++++++++++++++++++++++++++
      damageValue = damageValue * CritPartialMod:npcshot(itemName)
      --+++++++++++++++++++++++++++++++++++++++++ /Mod ++++++++++++++++++++++++++++++++++++++++++++
   end

   if self:getStatusEffectsManager():hasEffectName("scampShock") and itemName == "beacon_light.wpn" then
      damageValue = damageValue * 3
   end
   if self:hasShield() then
      local item = self:getShieldItem()
      damageValue = item:reduceDamage(damageValue)
   end

   if isPlayerAttacker then
      damageValue = damageValue * getGlobalParam("dmgOutgoingMultiplier")
      runTimer(0, nil, function()
         gameplayUI.hudUI:showEnemyStatus(self)
      end, false)
   end
   if charAttacker.OnEnemyHit then
      charAttacker:OnEnemyHit(params)
   end

   local angle = getTargetAngleFlat(self, params.impactPos)
   local direction
   if math.abs(angle) <= 45 then
      direction = "front"
   elseif angle > 45 and angle < 135 then
      direction = "left"
   elseif angle < -45 and angle > -135 then
      direction = "right"
   else
      direction = "back"
   end

   self:hit(math.floor(damageValue), charAttacker, direction)
   if self:getState("dead") == true then
      self.killer = charAttacker
   end

   self.senseScheduler:OnHit(charAttacker, itemName, damageValue)
end

function CCharacter:OnTriggerEnter(trigger)
   self.triggers[trigger] = true
   self.triggersVisited[trigger] = true

   if trigger.isEnabled and trigger:isEnabled() then
      self.eventManager:postEvent("OnTriggerEnter", trigger)
      self.eventManager:postEvent("coroutineEvent", {event="OnTriggerEnter",obj=trigger})
   end
end

function CCharacter:OnTriggerLeave(trigger)
   self.triggers[trigger] = nil

   if trigger.isEnabled and trigger:isEnabled() then
      self.eventManager:postEvent("OnTriggerLeave", trigger)
      self.eventManager:postEvent("coroutineEvent", {event="OnTriggerLeave",obj=trigger})
   end
end

function CCharacter:OnSenseBegin()
end

function CCharacter:OnSenseEnd()
end

function CCharacter:OnSenseInOther(char)
   self.senseScheduler:OnSenseInOther(char)
end

function CCharacter:OnSenseOutOther(char)
   self.senseScheduler:OnSenseOutOther(char)
end

function CCharacter:OnFeelIn(char)
   self.senseScheduler:OnFeelIn(char)
end

function CCharacter:OnFeelOut(char)
   self.senseScheduler:OnFeelOut(char)
end

function CCharacter:OnVisualIn(char)
   self.senseScheduler:OnVisualIn(char)
end

function CCharacter:OnVisualOut(char)
   self.senseScheduler:OnVisualOut(char)
end

function CCharacter:OnSleepBegin()
   self:setState("engineSleep", true)
   self:stopTimers()
   self.senseScheduler:refreshGuilds()
   if self.BT then
      self.BT:reset()
      --only AI can start proper animations after OnSleepEnd, do not stop animations on chars that don't have AI
      self.animationsManager:stopActionsAndCycles(0)
   end
end

function CCharacter:OnSleepEnd()
   self:setState("engineSleep", false)
   if not self:isDisabled() then
      self:setupTimers(self.defaultTimerFrequency)
      self.senseScheduler:refreshGuilds()
   end
end

function CCharacter:OnAnimationStop(animation)
   if self.animationsManager then
      self.animationsManager:OnAnimationStop(animation)
   end
end

function CCharacter:OnAnimationEventIn(animation, event)
   if self.animationsManager then
      self.animationsManager:OnAnimationEventIn(animation, event)
   end
end

function CCharacter:OnAnimationEventOut(animation, event)
   if self.animationsManager then
      self.animationsManager:OnAnimationEventOut(animation, event)
   end
end

function CCharacter:OnItemActivateSafe(item)
   if hlp.isOperable(item) then
      item:OnActivate()
   end
end

function CCharacter:OnItemDeactivateSafe(item)
   if hlp.isOperable(item) then
      item:OnDeactivate()
   end
end

function CCharacter:onStepEventIn()
   for trigger in pairs(self.triggers) do
      if trigger.metalSteps then
         self.soundManager:OnEventIn("step_metal")
         return
      end
   end
   self.soundManager:OnEventIn("step_dirt")
end

function CCharacter:isInTrigger(trigger)
   local obj = trigger

   if type(trigger) == "string" then
      obj = getObj(trigger)
   end

   return self.triggers[obj] == true
end

function CCharacter:isTriggerVisited(trigger)
   local obj = trigger

   if type(trigger) == "string" then
      obj = getObj(trigger)
   end

   return self.triggersVisited[obj] == true
end

function CCharacter:setImmortality(state)
   self.immortality = state
end

function CCharacter:setSpawnPos(pos)
   self.spawnPos = pos

   self.senseScheduler:setCurZone(self.spawnPos)
end

function CCharacter:getSpawnPos()
   return self.spawnPos
end

function CCharacter:setSpawn(spawner)
   self.spawn = spawner
end

function CCharacter:getSpawn()
   return self.spawn
end

-- items
function CCharacter:hasItem(itemName)
   return self:getInventory():getItemByName(itemName) ~= nil
end

function CCharacter:getItemLabel(itemName)
   local item = self:getInventory():getItemByName(itemName)

   if item then
      return item:getLabel()
   else
      return ""
   end
end

function CCharacter:getInteractType(char)
   if self:getState("dead") then
      return "container"
   else
      return "no_interaction"
   end
end

function CCharacter:isInteractionLingering(char)
   if self:getState("dead") then
      return true
   else
      return false
   end
end

function CCharacter:getInteractData(char)
   local data = {
      holster = false,
   }
   return data
end

function CCharacter:showInventory(state)
   gameplayUI.inventoryContainer:show(state)
end

function CCharacter:getWeaponSlot()
   return self.parameters.weaponSlotId
end

function CCharacter:getWeaponSlotItem()
   return self:getInventory():getSlotItem(self:getWeaponSlot())
end

function CCharacter:hasItemEquipped(itemName)
   return self:getItemEquippedSlot(itemName) ~= nil
end

function CCharacter:getItemEquippedSlot(itemName)
   for slotName, item in pairs(getMC():getInventory():getSlots()) do
      if item and item:getItemName() == itemName then
         return slotName
      end
   end
   return nil
end

function CCharacter:hasFaceCover()
   local hat = getMC():getInventory():getSlotItem("hat")
   local mask = getMC():getInventory():getSlotItem("mask")
   return (hat and hat:isFaceCover()) or (mask and mask:isFaceCover())
end

-- guilds
function CCharacter:setGuild(guild)
   if not isValidGuild(guild) then
      log(string.format("ERROR: %s tried setting invalid guild %s", self:getDescriptiveName(), tostring(guild)))
      log(debug.traceback())
      return
   end
   self.guild = guild

   self.senseScheduler:OnGuildChange()
end

---getInventory
---@return CInventorySlotted | CInventoryPlayer | CInventoryTurret
function CCharacter:getInventory()
   return self.inventory
end

function CCharacter:getGuild()
   return self.guild
end

---getAttitude
---@param char CCharacter
function CCharacter:getAttitude(char)
   if char == getMC() and self.attitudeToMainCharacter then
      return self.attitudeToMainCharacter
   end
   return getAttitude(self.guild, char:getGuild())
end

---setAttitudeToMainCharacter
---@param attitude string
function CCharacter:setAttitudeToMainCharacter(attitude)
   self.attitudeToMainCharacter = attitude and Attitudes[attitude]
   self.senseScheduler:refreshGuilds()
end

---getAttitudeToMainCharacter
function CCharacter:getAttitudeToMainCharacter()
   return self:getAttitude(getMC())
end

---resetAttitudeToMainCharacter
function CCharacter:resetAttitudeToMainCharacter()
   self.attitudeToMainCharacter = nil
   self.senseScheduler:refreshGuilds()
end

---setHasNoEnemiesOverride
---@param value boolean
function CCharacter:setHasNoEnemiesOverride(value)
   self.hasNoEnemiesOverride = value
   self.senseScheduler:OnGuildChange()
end

---isEnemy
---@param char CCharacter
---@return boolean
function CCharacter:isEnemy(char)
   return self:getAttitude(char) == Attitudes.ENEMY and not (self.hasNoEnemiesOverride or char.hasNoEnemiesOverride)
end

---isNeutral
---@param char CCharacter
---@return boolean
function CCharacter:isNeutral(char)
   return self:getAttitude(char) == Attitudes.NEUTRAL
end

---isIgnore
---@param char CCharacter
---@return boolean
function CCharacter:isIgnore(char)
   return self:getAttitude(char) == Attitudes.IGNORE
end

---isFriend
---@param char CCharacter
---@return boolean
function CCharacter:isFriend(char)
   return self:getAttitude(char) == Attitudes.FRIEND
end

function CCharacter:pushTowards(pos, force, duration, offset)
   local pushPos = vec3Sub(pos, self:getPose():getPos())
   if offset then pushPos = vec3Add(pushPos, offset) end
   self:push(pushPos, force, duration)
end

function CCharacter:pushFrom(pos, force, duration, offset)
   local pushPos = vec3Sub(self:getPose():getPos(), pos)
   if offset then pushPos = vec3Add(pushPos, offset) end
   self:push(pushPos, force, duration)
end

-- Sounds
function CCharacter:playActionSound(actionName)
   self.soundManager:playActionSound(actionName)
end

function CCharacter:playPrioritySound(actionName)
   self.soundManager:playPrioritySound(actionName)
end

function CCharacter:playSoundScheduled(soundName, channel)
   self.soundManager:playSoundScheduled(soundName, channel)
end


function CCharacter:setSoundParameters(sound, volume, speed, distance)
   if volume ~= nil then
      self:soundVolume(sound, volume)
   end
   if speed ~= nil then
      self:soundSpeed(sound, speed)
   end
   if distance ~= nil then
      self:soundDistance(sound, distance)
   end
end

-- Blackboard

function CCharacter:setBBVar(name, value)
   self.blackboard[name] = value
end

function CCharacter:getBBVar(name)
   return self.blackboard[name]
end

-- States

function CCharacter:setState(state, value)
   if self.states[state] ~= value then
      self.states[state] = value
      self.notificationCenter:postNotification("onChangeState")
      --log("setState = " .. state .. " = " .. tostring(value))
   end
end

function CCharacter:getState(state)
   if self.states[state] == nil then
      self.states[state] = false
   end

   return self.states[state]
end

-- target
function CCharacter:setTarget(target, offset)
   if target then
      self.target = target
      self:setLookTarget(target:getPose(), offset, 0)
   end
end

function CCharacter:getTarget()
   return self.target
end

function CCharacter:resetTarget()
   self.target = nil
   self:resetLookTarget()
end

function CCharacter:orientTo(obj)
   local angle = getTargetAngleDir(self, obj:getPose():getPos())
   self:setOrientation(angle)
   self:setOrientationSpeed(self.orientateSpeed or 120)

   if math.abs(angle) > 30 then
      if self.turnRightAnim then
         if angle < 0 then
            self.animationsManager:playAction(self.turnRightAnim)
         else
            self.animationsManager:playAction(self.turnLeftAnim)
         end
      end
   end
end

---Allows to deserialize min/max/regen stats before the stats that reference them
local function deserializeSort(a,b)
   return string.len(a) > string.len(b)
end

---@param statTable table
function CCharacter:initializeStats(statTable)
   local unpackParams = {"min", "max", "regen"}
   for statName, params in tablex.sort(statTable, deserializeSort) do
      if params.value then
         self.stats[statName] = CCharacterStatSimple{name = statName, value = params.value, owner = self}
         table.insert(self.regeneratingStats, self.stats[statName])
      elseif params.baseValue then
         self.stats[statName] = CCharacterStatModified{name = statName, baseValue = params.baseValue, owner = self}
      end
      --Unpack min/max/regen references or values
      for _, paramName in ipairs(unpackParams) do
         local paramValue = params[paramName]
         if type(paramValue) == "string" then
            self.stats[statName][paramName] = self.stats[paramValue]
         else
            self.stats[statName][paramName] = paramValue
         end
      end
   end
end

---@param statName string
---@return CCharacterStatBase
function CCharacter:getStatByName(statName)
   return statName and self.stats[statName]
end

---@param statName string
---@return boolean
function CCharacter:hasStatByName(statName)
   return self:getStatByName(statName) ~= nil
end

---@param statName string
---@param unclamped boolean if not to clamp the value during the call
---@return number
function CCharacter:getStatCount(statName, unclamped)
   if not self:hasStatByName(statName) then return end
   return self.stats[statName]:getValue(unclamped)
end

---@param statName string
---@return boolean
function CCharacter:isStatFull(statName)
   if not self:hasStatByName(statName) then return end
   return self.stats[statName]:getPercent() >= 100
end

---@param statName string
---@return number
function CCharacter:getStatPercent(statName)
   if not self:hasStatByName(statName) then return 0 end
   return self.stats[statName]:getPercent()
end

---@param statName string
---@return number
function CCharacter:getStatMin(statName)
   if not self:hasStatByName(statName) then return end
   return self.stats[statName]:getMin()
end

---@param statName string
---@return number
function CCharacter:getStatMax(statName)
   if not self:hasStatByName(statName) then return end
   return self.stats[statName]:getMax()
end

---@param statName string
---@return number
function CCharacter:getStatRegen(statName)
   if not self:hasStatByName(statName) then return end
   return self.stats[statName]:getRegen()
end
---@param statName string
---@param value number
function CCharacter:setStatCount(statName, value)
   if not self:hasStatByName(statName) then return end

   self.stats[statName]:setValue(value)
end

---@param statName string
---@param value number
function CCharacter:changeStatCount(statName, value)
   if not self:hasStatByName(statName) or not value then return end

   if self.god_mode and value > 0 or not self.god_mode then
      self.stats[statName]:changeValue(value)
   end
end

---Spend a required amount from a stat if it has enough or deplete it anyway
---@param statName string
---@param value number | string a number or string name of another stat, should be negative to actually reduce the amount
---@param deplete boolean
function CCharacter:spendStat(statName, value, deplete)
   if not self:hasStatByName(statName) or not value then return false end
   if type(value) == "string" then
      value = self.stats[value]:getValue()
   end
   if self.stats[statName]:getValue() >= -value or deplete then
      self:changeStatCount(statName, value)
      return true
   else
      return false
   end
end

---Serialize simple stats
function CCharacter:serializeStats()
   local stats = {}
   for statName, stat in pairs(self.stats) do
      if oo.isinstanceof(stat, CCharacterStatSimple) then
         stats[statName] = stat:getValue()
      end
   end
   return stats
end

function CCharacter:deserializeStats(statTable)
   for statName, value in pairs(statTable) do
      if self.stats[statName] and oo.isinstanceof(self.stats[statName], CCharacterStatSimple) then
         self.stats[statName].value = value
      end
   end
end

function CCharacter:subscribeOnDeath(func, obj)
   self.subscribersOnDeath[#self.subscribersOnDeath+1] = { ["func"] = func, ["obj"] = obj, }
end

---External animated damage function if damage is allowed and character is alive
function CCharacter:hit(damage, charAttacker, direction)
   if not self:isDamageAllowed(charAttacker) or self:getState("dead") then return end

   damage = self:recalculateDamage(damage, charAttacker, direction)

   if self:takeDamage(damage, charAttacker, direction) > 0 then
      if self:getStatCount("health") > 0 then
         self:animatedEvent("hit", direction)
      end
   end
end

---Affect damage numbers with armor and etc.
function CCharacter:recalculateDamage(damage, charAttacker, direction)
   local armor = self:getStatCount("armor")
   local armorCap = getGlobalParam("armorCap") or 60 --having max armor will completely block all damage
   damage = math.floor(damage - (damage*armor/armorCap) - (armor * 0.1))
   return damage
end

---Reduces HP if the character is alive
function CCharacter:takeDamage(damage, charAttacker, direction)
   if self:getState("dead") then return end

   if damage > 0 then
      self:changeStatCount("health", -damage)
   end

   return damage
end

function CCharacter:die__()
   self:animatedEvent ("die")
   self:setState      ("dead", true)
   self:setStatCount("health", 0)
   self:setHeadLookingAllowed(false)

   self:stopSounds()
   self.soundManager:stopSounds()
   self:stopMove()
   self:stopTimers()
   self:deleteBehaviorTree()
   if self.spawnCorpseDummy then
      self.corpseDummy = hlp.spawnCorpseDummy(self)
   end
end

function CCharacter:die()
   self:die__()

   self.soundManager:OnEventIn("death")
   for i=1,#self.subscribersOnDeath do
      self.subscribersOnDeath[i].func(self.subscribersOnDeath[i].obj, self)
   end
   if not self.installer
      or self.installer:getScriptClass() ~= "CSpawn" and self.installer:getScriptClass() ~= "CSmartSpawn" then
      questSystem:fireEvent("dead", self:getName(), self)
   end
end

function CCharacter:playDeathAnimation(animation)
   if not self:addAnimationEvent(animation, "end", 999, 999) then
      log(string.format("WARNING: %s %s %s couldn't create death animation event", self:getScriptClass(), self:getName(), self:getPrefabName()))
   end

   if self.corpseDummy then
      self.corpseDummy:setActive(false)
   end

   self.animationsManager:stopActionsAndCycles()
   self.animationsManager:playAction(animation, nil, nil, true)
   self.animationsManager:subscribeAnimationEventIn(animation, "end", function()
      if self:isInAir() then
         self.eventManager:subscribeToEvent("OnLanding", function()
            runTimerAdv(1, false, self.deactivateAfterDeath, self)
         end)
      else
         runTimerAdv(1, false, self.deactivateAfterDeath, self)
      end
   end)
end

function CCharacter:deactivateAfterDeath()
   self:setActive(false)
   if self.corpseDummy then
      self.corpseDummy:setActive(true)
   end
end

function CCharacter:stopMove()
   self:setStrafeSpeed(0)
   self:setMoveSpeed  (0)
end

function CCharacter:animatedMoveEvent(moveType, dirType)
   return not self:getState("dead")
end

function CCharacter:animatedEvent(eventType, direction)
   return not self:getState("dead")
end

function CCharacter:setStealth(value)
   self:setState("inStealth", value)
end

function CCharacter:getStealth()
   return self:getState("inStealth")
end

-- ---------------------------------------------------------------------------------------
-- Appearance
-- ---------------------------------------------------------------------------------------
function CCharacter:setupAppearance(styleName)
   if not styleName then return end

   local style = Appearance.getStyleFor(styleName, self) or Appearance.getDefaultStyleFor(self)
   self:setupStyle(style, styleName)
end

function CCharacter:setupStyle(style, styleName)
   if not style then return end
   self.styleName = styleName

   --clear prev attachments
   for _, attachment in pairs(self.style.attachments) do
      hlp.safeDestroyEntity(attachment.entity)
      attachment.entity = nil
   end

   self.style.body = tablex.deepcopy(style.body)
   self.style.textures = tablex.deepcopy(style.textures) or {}
   self.style.attachments = tablex.deepcopy(style.attachments) or {}

   self:updateAppearance()
end

function CCharacter:updateAppearance()
   --Setup submeshes
   local body = {}
   for i=1,#self.style.body do
      for j=1,#self.style.body[i] do
         body[#body+1] = self.style.body[i][j]
      end
   end
   self:setVisibleMeshesOnly(body)

   self:setupMeshTextures()

   self:setupAttachments()
end

function CCharacter:setupMeshTextures()
   if self.style.textures then
      for meshName,textureName in pairs(self.style.textures) do
         hlp.setTextureAndNormalMap(self, 0, textureName, meshName)
      end
   end
end

function CCharacter:setupAttachments()
   local destroyHair = false
   for _, attachment in pairs(self.style.attachments) do
      self:setupAttachment(attachment)
      if attachment.name:find("hat") or attachment.name:find("turban") or attachment.name:find("mask") or attachment.name:find("helmet") then
         destroyHair = true
      end
   end
   if destroyHair then
      self:destroyHair()
   end
end

function CCharacter:setupAttachment(attachment)
   local entity = attachment.entity or getScene():createEntity(attachment.name, "")
   entity:getPose():setParent(self:getBonePose(attachment.bone))
   entity:getPose():resetLocalPose()
   if self:isDisabled() then
      entity:setVisible(false)
   end
   if attachment.pos then
      entity:getPose():setLocalPos(attachment.pos)
   end
   if attachment.rot then
      entity:getPose():setLocalRot(attachment.rot)
   end
   if attachment.scale then
      entity:getPose():setLocalScale(attachment.scale)
   end
   if attachment.texture then
      hlp.setTextureAndNormalMap(entity, 0, attachment.texture)
   end
   attachment.entity = entity
end

function CCharacter:addAttachments(attachmentsTable)
   for _, attachData in pairs(attachmentsTable) do
      local attachment = tablex.deepcopy(attachData)
      table.insert(self.style.attachments, attachment)
   end
   self:setupAttachments()
end

function CCharacter:removeAttachments(t)
   if not t then return end
   for _, removeAttachment in ipairs(t) do
      for index, charAttachment in ipairs(self.style.attachments) do
         if removeAttachment.name == charAttachment.name then
            hlp.safeDestroyEntity(charAttachment.entity)
            table.remove(self.style.attachments, index)
            break
         end
      end
   end
end

function CCharacter:destroyHair()
   for _, attachment in pairs(self.style.attachments) do
      if attachment.name:find("hair") then
         self:removeAttachments({attachment})
         break
      end
   end
end

function CCharacter:updateAttire()
   if #self.style.body == 0 then return end

   local dontRemoveBodyMesh = { "junk_legs_1", "junk_top_1", "junk_top_2" }
   local t = {}
   for _,v in pairs(self.style.body) do
      for _,val in pairs(v) do
         table.insert(t, val)
      end
   end
   local slots = self:getInventory():getSlots()
   for slotName, item in pairs(slots) do
      local meshes = item and item:getAttireMeshes()
      if meshes then
         for _,val in pairs(meshes) do
            table.insert(t, val)
            if slotName == "hat" then --For accessories that are done as submeshes
               self:destroyHair()
            elseif val:find("legs") and not getKeyByValue(dontRemoveBodyMesh, val) and getKeyByValue(t, "human_male_legs") then
               table.remove(t, getKeyByValue(t, "human_male_legs"))
            elseif val:find("top") and not getKeyByValue(dontRemoveBodyMesh, val) and getKeyByValue(t, "human_male_top") then
               table.remove(t, getKeyByValue(t, "human_male_top"))
            end
         end
      end
   end
   self:setVisibleMeshesOnly(t)
end

-- ---------------------------------------------------------------------------------------
-- Dialogs' rootine
-- ---------------------------------------------------------------------------------------
function CCharacter:startTalk(char)
   return false
end

function CCharacter:onStartDialog(animator)
   if self.animations and self.animations.talk and self.animations.talk.default then
      animator:registerAnimations(self.animations.talk.default, self:getPrefabName())
      self.dialogAnimator = animator
   end
end

-- consider moving to CNPC once it becomes an exclusive base class
-- for all talkable characters
function CCharacter:onStartMessage(animation)
   if self.dialogAnimationAllowed then
      if animation then
         self._randomTalkAnim = animation
         self.animationsManager:playAction(self._randomTalkAnim)
      elseif self.dialogAnimator then
         local nextAnimation = self.dialogAnimator:next(self:getPrefabName())
         if nextAnimation then
            if self.animationsManager:playActionExclusively(nextAnimation) then
               self._randomTalkAnim = nextAnimation
            end
         else
            log("ERROR: CCharacter:onStartMessage: dialogAnimator didn't return an animation")
         end
      end
   end
end

function CCharacter:stopTalk(char)
   if self._randomTalkAnim then
      self.animationsManager:stopActionOrCycle(self._randomTalkAnim)
      self._randomTalkAnim = nil
   end
   self.dialogAnimator = nil
end

function CCharacter:getLabel()
   local label = ObjectsLabels.getLabel(self:getPrefabName())

   if label == "" then
      label = self:getName()
   end

   return label
end

function CCharacter:setDialogAnimationAllowed(state, seconds)
   if self.dialogAnimationTimer then
      self.dialogAnimationTimer:stop()
      self.dialogAnimationTimer = nil
   end
   self.dialogAnimationAllowed = state
   if seconds then
      self.dialogAnimationTimer = runTimer(seconds, nil, function()
         self.dialogAnimationAllowed = not state
         self.dialogAnimationTimer = nil
      end, false)
   end
end

--Label above the head when alive, and at default pos when dead
function CCharacter:getLabelPos()
   local pos = self:getPose():getPos()
   local headPose = self:findBonePose("Head")
   if self:getState("dead") then
      pos.y = pos.y + 45
   elseif headPose then
      pos = headPose:getPos()
      pos.y = pos.y + 45
   else
      pos.y = pos.y + self:getCollisionHeight()
   end
   return pos
end

-- ---------------------------------------------------------------------------------------
--
-- ---------------------------------------------------------------------------------------
local function checkNan(pos)
   for _, comp in pairs(pos) do
      if isNaN(comp) then
         return true
      end
   end
   return false
end

function CCharacter:OnIdle()
   if self:getState("dead") then return end
   local pos = self:getPose():getPos()
   local nan = checkNan(pos)
   if not nan then
      self.safePosition = pos
   else
      self:getPose():setPos(self.safePosition)
      local name, scriptClass = hlp.getNameAndClass(self)
      log(string.format("WARNING: NaN detected in position of %s<%s>", name, scriptClass))
      if isSavingEnabled() then
         getScene():tryAutoSave()
         initSavegamesList(gameplayUI.wndSaveLoad:getChild("Savegames"))
         pauseGame()
         confirmMessage(gameplayUI.wndPause, partial(loadSaveVersionCheck, getLastSaveID()), nil, "[font='decor-6']We detected an engine error, \nbut managed to autosave your progress. \nDo you want to load it?")
      end
   end
   self:trackLookAtTarget()
   if self.immortality ~= "immortal" then
      self:regenerate(getFrameTime())
   end
   if self.shouldTickAI and self.behaviorTreeTimer then
      self.behaviorTreeTimer:fire()
      self.shouldTickAI = false
   end
end

function CCharacter:getSafePos()
   local pos = self:getPose():getPos()
   return checkNan(pos) and self.safePosition or pos
end

function CCharacter:regenerate(secondsElapsed)
   for _, stat in ipairs(self.regeneratingStats) do
      stat:regenTick(secondsElapsed)
   end
end

---Meant to be subscribed to time fast forwarding
---Regeneration ignores min and max. The value gets clamped at the next getValue(false) call,
---which allows to properly accumulate regeneration + overtime status effects.
function CCharacter:onFastForwardTime(event, ...)
   self:regenerate(event.elapsed:getAs("rSecond"))
end

function CCharacter:OnInventoryChange(event)
end

function CCharacter:OnItemEquip(event)
   if event.eventType == "ItemEquipped" then
      if type(event.slotId) == "number" then
         local bonePose = self:getBonePose("item_slot" .. event.slotId)
         if bonePose then
            local itemPose = event.item:getPose()
            itemPose:setParent(bonePose)
            itemPose:resetLocalPose()
            if event.item:isMeleeWeapon() and (event.slotId == 3 or event.slotId == 4) then
               itemPose:setLocalRot({x=-55})
            end

            event.item:setCollisionCharactersRoot(false, false)
            event.item:setDynamicRoot(false)
            if not self:isDisabled() then
               event.item:show()
            end
         end
      elseif event.item:isAccessory() and event.item:getAttachments() then --Sorts out accessories done as submeshes
         self:addAttachments(event.item:getAttachments())
      else
         self:updateAttire()
      end
   end
end

function CCharacter:OnItemUnequip(event)
   if event.eventType == "ItemUnequipped" then
      if type(event.slotId) == "number" then
         event.item:getPose():resetParent()
         event.item:hide()
      elseif event.item:isAccessory() and event.item:getAttachments() then --Sorts out accessories done as submeshes
         self:removeAttachments(event.item:getAttachments())
      else
         self:updateAttire()
      end
   end
end

function CCharacter:getHeadPos()
   if self.headBonePose then
      return self.headBonePose:getPos()
   end

   return self:getPose():getPos()
end

function CCharacter:setHeadLookingAllowed(state)
   self.headLooking = state
end

function CCharacter:isHeadLookingAllowed()
   return self.headLooking
end

function CCharacter:trackLookAtTarget()
   if not self.headBonePose then return end

   local closestChar = self.senseScheduler:getClosestCharacter()

   if self:getState("inDialog") and self.talkChar then
      closestChar = self.talkChar
   end

   if self.prevHeadTarget and self.prevHeadTarget ~= closestChar or not self:isHeadLookingAllowed() then
      closestChar = nil
   end

   if not closestChar and self.lookAtFactor <= 0 then
      self.prevHeadTarget = nil
      return
   end

   if not closestChar or not closestChar.getHeadPos or self:getStrafeSpeed() ~= 0 or self:getMoveSpeed() < 0 then
      if self.lookAtFactor > 0 then
         self.headBonePose:setLocalRotQuat(quatSlerp(self.headBonePose:getLocalRotQuat(), self.lookAtTargetRot, clamp(self.lookAtFactor,0,1)))
         self.lookAtFactor = self.lookAtFactor - getFrameTime() * 2
      end
      return
   end

   --if (self == getPlayer()) then log("cn = " .. closestChar:getName()) end
   --log("cv = " .. tostring(self:checkInView(closestChar:getHeadPos(), 40, true)))

   local targetDir = vec3Normalize(vec3Sub(closestChar:getHeadPos(), self:getHeadPos()))

   targetDir = vec3RotateQuat(targetDir, quatInverse(self:getPose():getRotQuat()))

   local targetRotation = quatRotateQuat(quatFromDirs({z=-1}, targetDir))
   local targetAngles = getAnglesFromQuat(targetRotation)
   targetAngles.x = clamp(targetAngles.x, -self.headLookingLimits.x, self.headLookingLimits.x)
   targetAngles.y = clamp(targetAngles.y, -self.headLookingLimits.y, self.headLookingLimits.y)
   targetAngles.z = clamp(targetAngles.z, -self.headLookingLimits.z, self.headLookingLimits.z)
   self.lookAtTargetRot = quatRotateQuat(quatFromEuler(targetAngles), self.headBonePose:getLocalRotQuat())
   --self.lookAtTargetRot = quatRotateQuat(quatFromDirs({z=-1}, targetDir), self.headBonePose:getLocalRotQuat())
   --self.lookAtTargetRot = quatRotateQuat(quatFromDirs(self:getDirSoft(), targetDir), self.headBonePose:getLocalRotQuat())

   if self.lookAtFactor < 1 then
      self.lookAtTargetRot = quatSlerp(self.headBonePose:getLocalRotQuat(), self.lookAtTargetRot, clamp(self.lookAtFactor,0,1))
      self.lookAtFactor    = self.lookAtFactor + getFrameTime() * 3
   end

   self.headBonePose:setLocalRotQuat(self.lookAtTargetRot)

   self.prevHeadTarget = closestChar
end

-- ---------------------------------------------------------------------------------------
-- effects rootine
-- ---------------------------------------------------------------------------------------
function CCharacter:playEffect(effectName, time)
   if not self.fx then self.fx = {} end

   if effectName == "electro_shock" then
      if not self.fx.electroShock then
         self.fx.electroShock = {}
         self.fx.electroShock.emitter = self:createAspect("electro_shock.sps")

         local emitter = self.fx.electroShock.emitter

         emitter:setLoop(true)

         local scale = (self:getCollisionRadius() + self:getCollisionHeight()) * 0.005
         if scale < 0.5 then scale = 0.5 end

         emitter:getPose():setScale     ({x=scale,y=scale,z=scale})
         emitter:getPose():setParent    (self:getPose())
         emitter:getPose():resetLocalPos()
         emitter:getPose():setLocalPos  ({x=0,y=self:getCollisionHeight() * 0.5,z=0})

         self.fx.electroShock.sound = self:createAspect("Play_electro_smash")

         self.fx.electroShock.sound:getPose():setParent(self:getPose())
         self.fx.electroShock.sound:getPose():resetLocalPose()
         self.fx.electroShock.sound:getPose():setLocalPos({x=0,y=100,z=0})
         self.fx.electroShock.sound:setDistance(1200)
      end

      if self.fx.electroShock.timer then
         self.fx.electroShock.timer:stop()
         self.fx.electroShock.timer = nil
      end

      self.fx.electroShock.emitter:play()
      self.fx.electroShock.sound:play()
      self.fx.electroShock.timer = runTimer(time, self.fx.electroShock, CCharacter.stopEffect, false)
   end
end

function CCharacter:stopEffect()
   self.emitter:stop()
   self.timer = nil
end

function CCharacter:getLootTable()
   return self:getInventory():getLootTable()
end

function CCharacter:isDisabled()
   return self.disabled
end

function CCharacter:setDisabled(state)
   if self:isDisabled() == state then return end
   self.disabled = state
   if state then
      if self.BT then
         self.BT:reset()
      end
      self:stopTimers()
   else
      self:setupTimers(self.defaultTimerFrequency)
   end
   self:setVisible(not state)
   self:setActive(not state)
   for _, item in ipairs (self.inventory.slots) do
      if state then
         item:hide()
      else
         item:show()
      end
   end
   for _, attachment in pairs (self.style.attachments) do
      attachment.entity:setVisible(not state)
   end
end

function CCharacter:OnSaveState(state)
   state.immortality = self.immortality
   state.disabled = self.disabled
   state.feelVisible = self:getFeelVisible()
   state.styleName = self.styleName
   state.guild = self:getGuild()
   state.dead = self:getState("dead")
   state.attitudeToMainCharacter = self.attitudeToMainCharacter

   state.stats = self:serializeStats()

   local index = 1
   state.statusEffects = {}
   for _,effect in ipairs(self.statusEffectsManager.statusEffects) do
      if effect:isSaved() then
         state.statusEffects[index] = {}
         effect:OnSaveState(state.statusEffects[index])
         index = index + 1
      end
   end

   state.inventory = self:getInventory():serialize()
   state.interactor = self.interactor:getRaycastActive()
end

function CCharacter:OnLoadState(state)
   if state.immortality then
      self.immortality = state.immortality
   end
   if state.feelVisible ~= nil then
      self:setFeelVisible(state.feelVisible)
   end
   if state.styleName then
      self:setupAppearance(state.styleName)
   end
   if state.guild ~= self:getGuild() then
      self:setGuild(state.guild)
   end

   --Status effects and items should be loaded before stats as their bonuses affect stats' clamping values.
   if state.statusEffects then
      for _,effectState in ipairs(state.statusEffects) do
         self.statusEffectsManager:addStatusEffect(effectState)
      end
   end

   local inventory = self:getInventory()
   inventory:destroyAllItems()
   inventory:deserialize(state.inventory)

   self.interactor:setRaycastActive(state.interactor)

   if state.dead then
      --To exclude chars from being hidden by umbra and to properly play death anim, end of which calls setActive(false) again
      self:setActive(true)
      self:die__() --Call this internal method before stat loading to ensure it's not a new death
   end

   self:deserializeStats(state.stats)

   self:setDisabled(state.disabled) --Will only execute if the current state is different

   self:setAttitudeToMainCharacter(state.attitudeToMainCharacter)
end

return {CCharacter=CCharacter}
