local oo = require "loop.simple"
local CAction = (require "action").CAction
local CNode = (require "node").CNode
local ItemsData = (require "itemsData")
local ItemsInfo = (require "itemsData").ItemsInfo
local CPlayer = (require "player").CPlayer
local CCharacter = (require "character").CCharacter
local SkySystem = (require "environment.sky").SkySystem
local InstallationData = (require "items.installation").ItemRecipes
--+++++++++++++++++++++++++++++++++++++++++ Mod +++++++++++++++++++++++++++++++++++++++++++++
local CritPartialMod  = require "mods.partialcritmod"
--+++++++++++++++++++++++++++++++++++++++++ /Mod ++++++++++++++++++++++++++++++++++++++++++++
local TerminalUI    = require "ui.terminal"
local ImmersiveUI = require "ui.immersiveUI"
local GUIUtils      = require "ui.utils"

local hlp = require "helpers"
local coro = require "coroutines.helpers"

local random = require "random"

local List = require "pl.List"
local tablex = require "pl.tablex"

local f = require "fun"
local partial = f.partial

---@class CMainCharacter : CPlayer
local CMainCharacter = oo.class({
   inventoryType = "player",
   spawnCorpseDummy = false,
}, CPlayer)

function CMainCharacter:init()
   CPlayer.init(self)

   self.god_mode = false
   self.super_speed = false

   self.installations = {}

   self.statusEffectsManager:addStatusEffect({ name = "basicRegens" })
   self.statusEffectsManager:addStatusEffect({ name = "basicArmor" })
   self.statusEffectsManager:addStatusEffect({ name = "basicStatUpgrade" })

   self.level = 1
   self.attributePoints = 0
   self.experience = { current = 0, max = 1000, maxStarting = 1000, }

   self.levelUpBonuses =     { healthMax = 0, staminaMax = 0, energyMax = 0 }
   self.upgradeBonuses =     { healthMax = 10, staminaMax = 10, energyMax = 10 }
   self.assignedAttributes = { healthMax = 0, staminaMax = 0, energyMax = 0 }

   gameplayUI.characterUI:updateStatisticsAttributePoints()

   --Timer that checks the current player pos to manually update shadows
   self.updateShadowsTimer = runTimer(0.2, nil, function()
      local pos = getPlayer():getPose():getPos()
      if not self.prevPos or getDistance(pos, self.prevPos) > 5000 then
         self.prevPos = pos
         updateGlobalShadows()
      end
   end, true)

   self.ffCallback = SkySystem:subscribeFastForwardTime(partial(self.onFastForwardTime, self))
end

function CMainCharacter:initEffects()
   self.fx = {}

   self.fx.fry = self:createAspect("fry_smoke.sps")
   self.fx.fry:disable()

   self.fx.antigrav_hit = self:createAspect("antigrav_hit.sps")
   self.fx.antigrav_hit:setLoop(false)
   self.fx.antigrav_hit:getPose():setScale({x=1,y=1,z=1})
   self.fx.antigrav_hit:getPose():setParent(self:getPose())
   self.fx.antigrav_hit:getPose():resetLocalPos()
   self.fx.antigrav_hit:disable()

   self.fx.smoking_smoke = hlp.createJointSmokingEmitterAspect(self)

   self.fx.digging_dust = self:createAspect("sand_flow.sps")
   self.fx.digging_dust:setLoop(true)
   self.fx.digging_dust:getPose():setScale({x=0.5,y=0.5,z=0.5})
   self.fx.digging_dust:getPose():setParent(self:getPose())
   self.fx.digging_dust:getPose():resetLocalPos()
   self.fx.digging_dust:getPose():setLocalPos({x=0,y=0,z=-50})
   self.fx.digging_dust:disable()
end

function CMainCharacter:initSounds()
   self.sounds = {}

   self.sounds.cough = self:createAspect("main_hero_cough_1.wav")
   self.sounds.cough:getPose():setParent(self:getPose())
   self.sounds.cough:getPose():resetLocalPos()
   self.sounds.cough:setLoop(true)
   self.sounds.cough:setDelay(2)
   self.sounds.cough:setDistance(1000)

   self.sounds.fry = self:createAspect("fry.wav")
   self.sounds.fry:getPose():setParent(self:getPose())
   self.sounds.fry:getPose():resetLocalPos()
   self.sounds.fry:setLoop    (false)
   self.sounds.fry:setDistance(1000)

   self.sounds.death = self:createAspect("game_over.wav")
   self.sounds.death:getPose():setParent(self:getPose())
   self.sounds.death:getPose():resetLocalPos()
   self.sounds.death:setLoop    (false)
   self.sounds.death:setDistance(2000)

   self.sounds.jump = self:createAspect("jump_1.wav")
   self.sounds.jump:getPose():setParent(self:getPose())
   self.sounds.jump:getPose():resetLocalPos()
   self.sounds.jump:setLoop    (false)
   self.sounds.jump:setDistance(500)

   --TODO:FIXME: adjust jump sounds when we have new files.
   self.sounds.jump_land_1 = self:createAspect("jump_1.wav")
   self.sounds.jump_land_1:getPose():setParent(self:getPose())
   self.sounds.jump_land_1:getPose():resetLocalPos()
   self.sounds.jump_land_1:setLoop    (false)
   self.sounds.jump_land_1:setDistance(500)

   self.sounds.jump_land_2 = self:createAspect("jump_2.wav")
   self.sounds.jump_land_2:getPose():setParent(self:getPose())
   self.sounds.jump_land_2:getPose():resetLocalPos()
   self.sounds.jump_land_2:setLoop    (false)
   self.sounds.jump_land_2:setDistance(500)

   self.sounds.impact_axe = {}
   self.sounds.impact_bullet = {}

   for i=1,5 do
      local soundName = string.format("main_hero_flesh_impact_axe_%d%s", i, ".wav")
      hlp.insertSoundToTable(self, soundName, self.sounds.impact_axe, {distance=500, volume=0.05})

      soundName = string.format("main_hero_flesh_impact_bullet_%d%s", i, ".wav")
      hlp.insertSoundToTable(self, soundName, self.sounds.impact_bullet, {distance=500, volume=0.3})
   end

   for _, snd in ipairs(self.sounds.impact_axe) do
      snd:getPose():setParent(self:getPose())
      snd:getPose():resetLocalPos()
   end

   for _, snd in ipairs(self.sounds.impact_bullet) do
      snd:getPose():setParent(self:getPose())
      snd:getPose():resetLocalPos()
   end
end

function CMainCharacter:OnHit(params)
   CPlayer.OnHit(self, params)
   local snd
   if params.impactType == "melee" and params.impactor:getAnimations() ~= "boxing" then
      snd = random.choice(self.sounds.impact_axe)
   elseif params.impactType == "ranged" then
      snd = random.choice(self.sounds.impact_bullet)
   end
   if snd then
      snd:play()
   end
end

function CMainCharacter:loadParameters()
   CPlayer.loadParameters(self)

   local stats = {
      armor        = {baseValue = 0},
      healthMax    = {baseValue = 100, min = 1},
      healthRegen  = {baseValue = 0},
      health       = {value = 100, min = 0, max = "healthMax", regen = "healthRegen"},
      staminaMax   = {baseValue = 100},
      staminaRegen = {baseValue = 0},
      stamina      = {value = 100, min = 0, max = "staminaMax", regen = "staminaRegen"},
      energyMax    = {baseValue = 100},
      energyRegen  = {baseValue = 5},
      energy       = {value = 100, min = 0, max = "energyMax", regen = "energyRegen"},

      foodMax    = {baseValue = 3200},
      foodRegen  = {baseValue = -0.25},
      food       = {value = 3200, min = 0, max = "foodMax", regen = "foodRegen"},
      waterMax   = {baseValue = 3000},
      waterRegen = {baseValue = -0.25},
      water      = {value = 3000, min = 0, max = "waterMax", regen = "waterRegen"},
      sleepMax   = {baseValue = 100},
      sleepRegen = {baseValue = -0.01},
      sleep      = {value = 100, min = 0, max = "sleepMax", regen = "sleepRegen"},

      --MISC
      staminaRunCost = {baseValue = -1.25},
      staminaStepMoveCost = {baseValue = -20},
      staminaJumpCost = {baseValue = -5},
      staminaMeleeAttackCost = {baseValue = -5},
      staminaRangeAttackCost = {baseValue = -1},
      energyScanCost = {baseValue = -50},
   }
   self:initializeStats(stats)

   self.parameters.maxLandingSpeed  = 1000

   self.initialStyle = "jack_naked"
   self:setupAppearance(self.initialStyle)

   local items = loadParamItemCounts(self, "items", {})
   for name, count in pairs(items) do
      self:getInventory():addItem(name, count)
   end
end

function CMainCharacter:wearHair()
   self:setupAccessories({{bone="head_slot", name="hair_jack.sbg"}})
end

function CMainCharacter:OnCreate()
   self.setupInProgress = true

   setMC(self)
   CPlayer.OnCreate(self)
   self:initEffects()
   self:initSounds()

   setDefaultPlayerCameraFov(getPlayerFov())
   self.prevCamOffset = getDefaultPlayerCameraOffset()
   self.rightShoulderAim = true
   self:updateCamera()

   if not getScene():isLoadedGame() then
      if isDebug("inventory") then
         self:obtainCheatInventory()
      else
         self:obtainStartInventory()
      end
      self:equipHatOnStart()
      self:equipAttireOnStart()

      self:loadItemsToHotbar()
   end

   self.setupInProgress = false

   runTimer(1.0 / 10, self, self.updateFocus, true)
end

function CMainCharacter:updateFocus()
   -- focus
   if getPlayer() == self then -- raycast only when not remote controlling
      local obj
      local camHeight = self:getCameraHeight()
      local camDist = self:getCameraDist()
      local distToCamera = vec3Length({x=0,y=camHeight,z=camDist})
      local dist = distToCamera + 150
      local interactY = self:getPose():getPos().y + 100
      -- first raycast closest character
      obj = raycastCharacterOnScreen({x=0.5, y=0.5}, false)
      if obj then
         if obj.isEnemy and obj:isEnemy(self) and objInDist(self:getPose():getPos(), obj:getPose():getPos(), 4000) then
            gameplayUI.hudUI:showEnemyCursor(true)
         else
            gameplayUI.hudUI:showEnemyCursor(false)
         end

         if not objInDist(self:getPose():getPos(), obj:getPose():getPos(), 300) then
            obj = nil
         end
         if not hlp.isCharacter(obj) then
            obj = nil
         end
      else
         gameplayUI.hudUI:showEnemyCursor(false)
      end
      -- then try raycasting interactors
      if not obj then
         obj = raycastInteractorOnScreen({x=0.5, y=0.5}, dist, true)
         if obj then
            obj = obj:getObject()
            if math.abs(interactY - obj:getPose():getPos().y) > 150 then
               obj = nil
            end
         end
      end
      -- then try for closest to the camera in angle
      if not obj then
         -- try for closest character
         obj = self.senseScheduler:getCharInFocus(dist)
         -- then try for closest interactor
         if not obj then
            local ints = getInteractorsInView(500)
            if #ints > 0 then
               local cameraPos = self:getCamera():getPose():getPos()
               local playerPos = self:getPose():getPos()
               ints = List(ints):filter(function(arg)
                  local argPos = arg:getPose():getPos()
                  -- check for interactor that doesn't want to be seen by raycast
                  if arg:getRaycastRadius() == 0 then
                     return false
                  end
                  if checkPointInSector(cameraPos, self:getDirTarget(), argPos, 40, dist) then
                     if objInDist(playerPos, argPos, dist) then
                        if math.abs(interactY - arg:getPose():getPos().y) > 150 then
                           return false
                        else
                           return true
                        end
                     end
                  end
                  return false
               end)
               if #ints > 0 then
                  local distances = List()
                  for _, v in ipairs(ints) do
                     distances:append(getDistance(cameraPos, v:getPose():getPos()))
                  end
                  local min = distances:minmax()
                  obj = ints[distances:index(min)]
                  if obj then
                     obj = obj:getObject()
                  end
               end
            end
         end
      end
      if obj then
         if gameplayUI:getFocusObj() ~= obj then
            questSystem:fireEvent("find", obj:getName(), obj)
         end
         gameplayUI:setFocusObj(obj)
      else
         gameplayUI:setFocusObj(nil)
      end
   end
   -- end focus
end

function CMainCharacter:equipHatOnStart()
   CCharacter.equipHatOnStart(self)
end

function CMainCharacter:obtainCheatInventory(forcedCount)
   local blacklist = {
      "message_test.itm",
      "drawing_test.itm",
      "abori_gun_mortar.gun",
      "spacer_jacket.itm",
      "spacer_pants.itm",
      "hat_jack.itm",
      "energy_shield_1.itm",
      "energy_boots.itm",
      "power_cell.itm",
   }

   for itemName,v in pairs(ItemsInfo) do
      local category = ItemsData.getItemInvCategory(itemName)
      if not inList(blacklist, itemName) and v.category ~= "test" and v.category ~= "quest" then
         local count = 1
         if not forcedCount then
            if ItemsData.isItemMoney(itemName) then
               count = 10000
            elseif category == "ammo" then
               count = 300
            elseif category == "tech" or category == "food" or category == "drink" or category == "smokable" or category == "meds" or category == "misc" then
               count = 10
            end
         else
            count = forcedCount
         end
         local item = self:getInventory():addItem(itemName, count)
         if item and item.magazineMax then
            item.magazine = item.magazineMax
         end
      end
   end

   gameplayUI.hotbarUI:setItemToHotbarByName(1, "machete.wpn" )
   gameplayUI.hotbarUI:setItemToHotbarByName(2, "revolver.gun")
   gameplayUI.hotbarUI:setItemToHotbarByName(3, "shotgun.gun" )
   gameplayUI.hotbarUI:setItemToHotbarByName(4, "howdah.gun")
   gameplayUI.hotbarUI:setItemToHotbarByName(5, "scamp_22.gun")
   gameplayUI.hotbarUI:setItemToHotbarByName(6, "kabarog_hsg.gun")
   gameplayUI.hotbarUI:setItemToHotbarByName(7, "carbine.gun")
end

function CMainCharacter:obtainStartInventory()
   self:getInventory():addItem("hand_to_hand.wpn", 1)
   self:getInventory():addItem("hat_jack.itm", 1)
   self:getInventory():addItem("spacer_jacket.itm", 1)
   self:getInventory():addItem("spacer_pants.itm", 1)
   self:getInventory():addItem("scanner.itm", 1)

   gameplayUI.hotbarUI:setItemToHotbarByName(1, "hand_to_hand.wpn")
end

function CMainCharacter:loadItemsToHotbar()
   local items = loadParamStrings(self, "toHotbar", {})
   for i, name in ipairs(items) do
      gameplayUI.hotbarUI:setItemToHotbarByName(i, name)
   end
end

function CMainCharacter:onSleepStart()
   self:setDisableActionStates(true)
   self:setState("sleeping", true)
   if self:getState("sleepAtBed") then
      gameplayUI.billboardUI:show(false)
   else
      self.animationsManager:playCycle(self.animations.sitbyfire.sleep)
   end
   gameplayUI.waitingUI:show(false)

   self.statusEffectsManager:addStatusEffect({name = "sleepBuff"})
end

function CMainCharacter:onSleepStop()
   self:setState("disableInteraction", false)
   self:setState("blockItemUse", false)
   self:setState("sleeping", false)
   self:setStatCount("health", self:getStatMax("health"))
   if self:getState("sleepAtBed") then
      if self.bedObject then
         self.bedObject:deactivate(self)
      end
      gameplayUI.billboardUI:setup("Sleeping", string.format("Press '%s' to get up", getButtonCurrentKeyName("ACTIVATE")))
   else
      self.animationsManager:playCycle(self.animations.sitbyfire.default)
   end
   gameplayUI.waitingUI:show(true)

   self.statusEffectsManager:destroyEffectsByName("sleepBuff")
end


function CMainCharacter:spendStat(statName, value, deplete)
   if CPlayer.spendStat(self, statName, value, deplete) then
      if type(value) == "string" then
         value = self.stats[value]:getValue()
      end
      if statName == "stamina" then
         self:changeStatCount("food", value * 0.00005 * self:getStatCount("food"))
         self:changeStatCount("water", value * 0.0001 * self:getStatCount("water"))
      end
      return true
   end
   return false
end

function CMainCharacter:OnIdle()
   if self:getState("dead") then return end
   CPlayer.OnIdle(self)

   if self:getStatCount("stamina") <= 0 then
      self:setState("tired", true)
   elseif self:getStatCount("stamina") > self:getStatCount("staminaMax") * 0.2 and self:getState("tired") then
      self:setState("tired", false)
   end

   gameplayUI.characterUI:updateStatisticsAttributePoints()
   gameplayUI.characterUI:updateAllPlayerEffectsUI()

   --energy gun ammo
   local currentWeapon = self:getWeaponSlotItem()
   if currentWeapon and currentWeapon:getWeaponType() == "energy" then
      gameplayUI.hudUI:updateWeaponUI({item = currentWeapon})
   end

   if not self.camSlope then
      self.camSlope = 0.0
   end

   if self:getState("hipFire") then
      self.camSlope = mixF(self.camSlope, getAngle({x=0, y=1, z=0}, self:getCamera():getUp(), self:getCamera():getRight()), getFrameTime() * 20)
   else
      self.camSlope = mixF(self.camSlope, 0.0, getFrameTime())
   end

   if math.abs(self.camSlope) < 1.0 then
      return
   end

   self:rotateBone("Man Spine" , self.camSlope*0.2)
   self:rotateBone("Man Spine1", self.camSlope*0.2)
   self:rotateBone("Man Spine2", self.camSlope*0.5)

   self:rotateBone("Man Neck", self.camSlope)
   self:rotateBone("Man Head", self.camSlope)

   self:rotateBone("Man L Clavicle", self.camSlope)
   self:rotateBone("Man R Clavicle", self.camSlope)
end

function CMainCharacter:onStepEventIn()
   if self:getState("disableMove") then return end
   CPlayer.onStepEventIn(self)
   --To play it a frame after the step sound
   runTimer(0, nil, function()
      if self:getInventory():getSlotItem("top") or self:getInventory():getSlotItem("bottom") then
         self.soundManager:OnEventIn("ammunition")
      end
   end, false)
end

function CMainCharacter:OnAir(dist)
   if not self:getState("climbing_ladder") and not self:getState("climbing_ladder_down") then
      CPlayer.OnAir(self, dist)
      self:setState("inAir", true)
      self:setState("disableJump", true)
      self:setState("blockItemUse", true)
      self:setState("disableInteraction", true)

      local delay = 0.9
      if not self:getState("jumping") then
         delay = 0.3
      end

      if self.fallTimer then
         self.fallTimer:stop()
         self.fallTimer = nil
      end

      self.fallTimer = runTimer(delay, nil, function()
         if self:getState("inAir") then
            local animationSet = self:getInventory():getWeaponSlotAnimationSet()
            local anim = self.animations.fall[animationSet] or self.animations.fall.default
            self.animationsManager:playCycle(anim, 0.1)
            self:setState("falling", true)
         end
         self.fallTimer = nil
      end, false)
      self:tryCancelActions(false)
   end
end

function CMainCharacter:OnLanding(landingSpeed)
   if self.fallTimer then
      self.fallTimer:stop()
      self.fallTimer = nil
   end
   self.deltaLandingSpeed = (-landingSpeed) - self.parameters.maxLandingSpeed
   runTimer(0.05, nil, function()
      if not self:getState("swimming") then
         if random.random() * 2 < 1 then
            self.sounds.jump_land_1:play()
         else
            self.sounds.jump_land_2:play()
         end
         if self.deltaLandingSpeed > 0 then
            local damage = scaleValue(self:getStatCount("healthMax"), self.deltaLandingSpeed, self.parameters.maxLandingSpeed)
            local boots = self:getInventory():getSlotItem("boots")
            if boots and boots.fallDamageBlockMul and self:getStatCount("energy") >= boots.fallEnergyCost then
               damage = damage * boots.fallDamageBlockMul
               self:changeStatCount("energy", -boots.fallEnergyCost)
            end
            self:hit(damage, nil)
         end

         self:setState("blockItemUse", false)
         self:setState("disableInteraction", false)
         self:setState("disableJump", false)
         self:animatedEvent("land")
      end

      self:setState     ("inAir", false)
      self:setState     ("falling", false)
      self:setState     ("jumping", false)
      self:setState     ("disableAirPickup", false)
      self:tryCancelActions(false)
   end, false)
end

function CMainCharacter:OnSlideBegin()
   self:setState("sliding", true)
   self:setDisableActionStates(true)
   self:setState("disableMove", false)
   local animationSet = self:getInventory():getWeaponSlotAnimationSet()
   local anim
   if animationSet == "" or not self.animations.slide[animationSet] then
      anim = self.animations.slide.default
   else
      anim = self.animations.slide[animationSet]
   end
   self.animationsManager:playCycle(anim)
   self:tryCancelActions(false)
end

function CMainCharacter:OnSlideEnd()
   self:setState("sliding", false)
   self:setDisableActionStates(false)
   self:tryCancelActions(false)
end

function CMainCharacter:OnControlDown(code)
   if not CPlayer.OnControlDown(self, code) then
      return false
   end

   local currentWeapon = self:getWeaponSlotItem()
   local focusObj = gameplayUI:getFocusObj()

   if code == getButtonCode("ATTACK") and self:canAttack() then
      if currentWeapon and not self:getState("waitReloadEnd") then
      elseif self.lastWeapon then
         setButton("ATTACK", false)
         local lastWeapon = self:getInventory():getItemById(self.lastWeapon:getId())
         if lastWeapon then
            self:useItem(lastWeapon)
         end
      else
         setButton("ATTACK", false)
         local handWeapon = self:getInventory():getItemByName("hand_to_hand.wpn")
         self:useItem(handWeapon)
      end

   elseif (code == getButtonCode("AIM") and not GUIUtils.interactiveWindowsVisible()
            and not TerminalUI.isCursorVisible()) then
      ImmersiveUI.triggerUI("weapon")
      if currentWeapon and currentWeapon:isMeleeWeapon() and self:canAttack() then
         self:useItem(currentWeapon)
      elseif not currentWeapon or currentWeapon and currentWeapon:isRangedWeapon() then
         self:startAiming()
      end

   elseif code == getButtonCode("JUMP") and self:canJump() then
      local boots = self:getInventory():getSlotItem("boots")
      if getButton("SPRINT") and boots then
         if boots.OnActivate and self:getStatCount("energy") >= boots.jumpEnergyCost then
            self:OnItemActivateSafe(boots)
            self:changeStatCount("energy", -boots.jumpEnergyCost)
         end
      end

   elseif code == getButtonCode("ACTIVATE") then
      if self:canInteract() then
         if self:getState("sleepAtBed") and self.bedObject then
            self.bedObject:deactivate(self)
         elseif self:getState("resting") and self.campObject and not gameplayUI.waitingUI:isWaitingMode() then
            self.campObject:deactivate(self)
         elseif self:getState("gathering") and not self:getState("waitGatherFinish") then
            self:forceStopGathering(false)
         elseif self.exchangeTarget and not self:getState("trading") then
            self:interactObject("deactivate", self.exchangeTarget, nil)
         else
            self:preActivateObject()
         end
      --Exception to be able to pickup 1 item during airtime/jumping
      elseif self:getState("inAir") and focusObj and focusObj.getType and focusObj:getType() == "pickup" and not self:getState("disableAirPickup") then
         self:preActivateObject()
         --restore air states and restrict another air pickup
         self:setState("disableInteraction", true)
         self:setState("disableJump", true)
         self:setState("blockItemUse", true)
         self:setState("disableAirPickup", true)
      end

   elseif code == getButtonCode("RELOAD") then
      self:tryReload()

   elseif code == getButtonCode("PREVIOUS") then
      ImmersiveUI.triggerUI("weapon")
      self:prevWeapon()

   elseif code == getButtonCode("HOTBAR1") then
      self:OnHotbarItemClick(1)
   elseif code == getButtonCode("HOTBAR2") then
      self:OnHotbarItemClick(2)
   elseif code == getButtonCode("HOTBAR3") then
      self:OnHotbarItemClick(3)
   elseif code == getButtonCode("HOTBAR4") then
      self:OnHotbarItemClick(4)
   elseif code == getButtonCode("HOTBAR5") then
      self:OnHotbarItemClick(5)
   elseif code == getButtonCode("HOTBAR6") then
      self:OnHotbarItemClick(6)
   elseif code == getButtonCode("HOTBAR7") then
      self:OnHotbarItemClick(7)
   elseif code == getButtonCode("HOTBAR8") then
      self:OnHotbarItemClick(8)
   elseif code == getButtonCode("HOTBAR9") then
      self:OnHotbarItemClick(9)
   elseif code == getButtonCode("HOTBAR0") then
      self:OnHotbarItemClick(10)
   elseif code == getButtonCode("HOTBARQ") then
      local openedInventory = gameplayUI.inventoryContainer:isVisible() and gameplayUI.inventoryContainer
                              or gameplayUI.inventoryTurret:isVisible() and gameplayUI.inventoryTurret
      if openedInventory and not gameplayUI.itemDelimiterUI:isVisible() then
         openedInventory:onTakeAll()
      else
         self:OnHotbarItemClick(11)
      end

   elseif code == getButtonCode("HOLSTER") and (self:canInteract() or self:getState("reloading")) then
      ImmersiveUI.triggerUI("weapon")
      if currentWeapon then
         self:unequipItem(currentWeapon, true)
      elseif self.lastWeapon then
         local lastWeapon = self:getInventory():getItemById(self.lastWeapon:getId())
         if lastWeapon then
            self:useItem(lastWeapon)
         end
      end

   elseif ((code == getButtonCode("INVENTORY") or code == getButtonCode("INVENTORYALT"))
         and self:canUseUI()) then
      gameplayUI.gameplayMenuUI:toggleTab("Inventory")

   elseif code == getButtonCode("CRAFT") and self:canUseUI() then
      gameplayUI.gameplayMenuUI:toggleTab("Crafting")
   elseif code == getButtonCode("ALT") then
      if gameplayUI.itemInfoUI:isVisible() then
         gameplayUI.itemInfoUI:showDescription(true)
      end

   elseif code == getButtonCode("JOURNAL") and self:canUseUI() then
      gameplayUI.gameplayMenuUI:toggleTab("Journal")
   elseif code == getButtonCode("TIMESKIP") and self:canUseUI() then
      if self:getState("resting") then
         if gameplayUI.waitingUI:isVisible() then
            gameplayUI.waitingUI:show(false)
         else
            gameplayUI.waitingUI:show(true)
         end
      end

   elseif code == getButtonCode("RESTING") and self:canUseUI() then
      if isDebug("keys") and not self:getState("cooking") and not self:getState("talk") then
         self:setState("resting", not self:getState("resting"))
      end

   elseif code == getButtonCode("MAP") and self:canUseUI() then
      gameplayUI.gameplayMenuUI:toggleTab("Map")

   elseif code == getButtonCode("CAMVIEW") then
      local rangedMode = currentWeapon and currentWeapon:isRangedWeapon()
      local aimMode = self:getState("aiming")
      if rangedMode or aimMode then
         self.rightShoulderAim = not self.rightShoulderAim
         if self.rightShoulderAim then
            self.prevCamOffset = 53
         else
            self.prevCamOffset = -47
         end
      else
         self.prevCamOffset = self.prevCamOffset + 50
         if self.prevCamOffset > 53 then
            self.prevCamOffset = -47
            self.rightShoulderAim = false
         else
            self.rightShoulderAim = true
         end
      end
      self:updateCamera()

   elseif code == getButtonCode("CAMUP") then
      if getDefaultPlayerCameraHeight() < getGlobalParam("maxCamHeight") then
         setGlobalParam("camHeight", getDefaultPlayerCameraHeight() + 10)
         setDefaultPlayerCameraHeight(getDefaultPlayerCameraHeight() + 10)
         self:updateCamera()
      end
   elseif code == getButtonCode("CAMDOWN") then
      if getDefaultPlayerCameraHeight() > getGlobalParam("minCamHeight") then
         setGlobalParam("camHeight", getDefaultPlayerCameraHeight() - 10)
         setDefaultPlayerCameraHeight(getDefaultPlayerCameraHeight() - 10)
         self:updateCamera()
      end

   elseif code == getButtonCode("GODMODE") and isDebug("keys") then
      local msg = "God mode on"
      if not self.god_mode and not self.super_speed then
         self.god_mode = true
      elseif self.god_mode and not self.super_speed then
         msg = "Super speed on"
         self.super_speed = true
      else
         msg = "God mode and super speed off"
         self.god_mode = false
         self.super_speed = false
      end
      gameplayUI:showInfoTextEx(msg, "major", "")
   end

   return true
end

function CMainCharacter:OnControlUp(code)
   if not CPlayer.OnControlUp(self, code) then
      return false
   end

   if code == getButtonCode("ATTACK") then
      if not gameplayUI.inventoryPlayer:isVisible() and self:getState("interacting") then
         self:activateObject()
      end

   elseif code == getButtonCode("AIM") then
      self:stopAiming()

   elseif code == getButtonCode("ACTIVATE") then
      if not gameplayUI.inventoryPlayer:isVisible() and self:getState("interacting") then
         self:activateObject()
      end

   elseif code == getButtonCode("ALT") then
      if gameplayUI.itemInfoUI:isVisible() then
         gameplayUI.itemInfoUI:showDescription(false)
      end

   end

   return true
end

function CMainCharacter:exchangeStart(object)
   gameplayUI.inventoryPlayer:show(true)
   object:showInventory(true)
end

function CMainCharacter:exchangeStop(object)
   object:showInventory(false)
end

function CMainCharacter:getTargetInventory()
   if self.exchangeTarget then
      return self.exchangeTarget:getInventory()
   end
   return nil
end

function CMainCharacter:addActions()
   local move = CAction{}
   move:allowRestartOnEvent("onChangeButtonState")
   move:allowRestartOnEvent("onChangeState")
   move.start = self.move_start
   move.stop  = self.move_stop
   move.name  = "move"

   local jump = CAction{}
   jump.start = self.jump
   jump.name  = "jump"

   local attack = CAction{}
   attack.start = self.attack
   attack.name  = "attack"

   local rest = CAction{}
   --rest:allowRestartOnEvent("onChangeState")
   rest.start = self.rest_running
   rest.stop  = self.rest_finish
   rest.name  = "rest"

   local cook = CAction{}
   --cook:allowRestartOnEvent("onChangeState")
   cook.start = self.cook_running
   cook.stop  = self.cook_finish
   cook.name  = "cook"

   local interact = CAction{}
   interact:allowRestartOnEvent("onChangeState")
   interact.start = self.interact_start
   --interact.stop  = self.interact_stop
   interact.name  = "interact"

   local climb_ladder = CAction{}
   climb_ladder.start = self.climb_ladder_running
   climb_ladder.stop  = self.climb_ladder_finish
   climb_ladder.name  = "climb_ladder"

   local climb_ladder_down = CAction{}
   climb_ladder_down.start = self.climb_ladder_running
   climb_ladder_down.stop  = self.climb_ladder_finish
   climb_ladder_down.name  = "climb_ladder_down"

   local root = CNode{}
   root:yes (self.climb_ladder_down_):no  (self.climb_ladder_):no  (self.interact_):no  (self.rest_):no  (self.jump_):no   (self.attack_):yes  (attack)
   root:yes (self.climb_ladder_down_):no  (self.climb_ladder_):no  (self.interact_):no  (self.rest_):no  (self.jump_):yes  (jump)
   root:yes (self.climb_ladder_down_):no  (self.climb_ladder_):no  (self.interact_):no  (self.rest_):no  (self.move_):yes  (move)
   root:yes (self.climb_ladder_down_):no  (self.climb_ladder_):no  (self.interact_):no  (self.rest_):yes (self.cook_):no   (rest)
   root:yes (self.climb_ladder_down_):no  (self.climb_ladder_):no  (self.interact_):no  (self.rest_):yes (self.cook_):yes  (cook)
   root:yes (self.climb_ladder_down_):no  (self.climb_ladder_):no  (self.interact_):yes (interact)
   root:yes (self.climb_ladder_down_):no  (self.climb_ladder_):yes (climb_ladder)
   root:yes (self.climb_ladder_down_):yes (self.climb_ladder_):no  (climb_ladder_down)

   self.actionsScheduler.root = root
   self.notificationCenter:postNotification("onActionsSchedulerRootUpdate")
end

-- action methods and predecates
function CMainCharacter:climb_ladder_()
   return self:getState("climbing_ladder")
end
function CMainCharacter:climb_ladder_down_()
   return self:getState("climbing_ladder_down")
end


function CMainCharacter:climbLadder(ladderObj)
   if ladderObj then
      self.ladderObj = ladderObj
      if ladderObj:bottom() then
         self:setState("climbing_ladder", true)
      else
         self:setState("climbing_ladder_down", true)
      end
      return true
   else
      return false
   end
end

function CMainCharacter:climb_ladder_running()
   local anchorBot = self.ladderObj:getMeshByName("anchor_bot"):getPose():getPos()
   local anchorMid = self.ladderObj:getMeshByName("anchor_mid"):getPose():getPos()
   local anchorTopF = self.ladderObj:getMeshByName("anchor_top_f"):getPose():getPos()
   local anchorTopB = self.ladderObj:getMeshByName("anchor_top_b"):getPose():getPos()
   self.ladderCoro = runTimerCo(function()
      local anims
      local targetPos
      local dir = vec3RotateQuat({x=0,y=0,z=1}, self.ladderObj:getPose():getRotQuat())

      --OFFSET TO THE FIRST ANCHOR
      if self:getState("climbing_ladder") then
         anims = self.animations.ladder.up
         targetPos = anchorBot
      elseif self:getState("climbing_ladder_down") then
         anims = self.animations.ladder.down
         targetPos = anchorTopB
      end

      self:setHeadLookingAllowed(false)
      self:holsterWeapon()
      self:setOrientationSpeed(0)
      self:setDisableActionStates(true)

      self:moveAndOrientate(targetPos, dir, 0.1)

      coro.waitCharacterEvent(self, "OnMoveAndOrientateStop")

      --Adjust player before vertical movement
      local delay
      if self:getState("climbing_ladder_down") then
         delay = self:getAnimDuration(anims.to) / 1.5 --Delay so the player won't drop down immediately
         self:moveAndOrientate(anchorTopF, dir, delay)
      end

      self.animationsManager:playCycle(anims.loop)
      self.animationsManager:playAction(anims.to)

      if delay then
         coro.waitCharacterEvent(self, "OnMoveAndOrientateStop")
      else
         coro.waitAnimationEnd(self, anims.to)
      end

      --Player is in position for looping
      local finishDelay
      if self:getState("climbing_ladder") then
         local speed = 140
         targetPos = anchorMid
         finishDelay = getDistance(anchorBot, anchorMid) / speed
      elseif self:getState("climbing_ladder_down") then
         local speed = 600
         targetPos = anchorBot
         finishDelay = getDistance(anchorTopF, anchorBot) / speed
      end

      self:moveAndOrientate(targetPos, dir, finishDelay)
      self.animationsManager:playCycle(anims.loop, 0)

      coro.waitCharacterEvent(self, "OnMoveAndOrientateStop")

      self.animationsManager:playCycle(random.choice(self.animations.idle.default))
      self.animationsManager:playAction(anims.out)

      --Move player up, then forward to avoid forcing him through the ledge (to which ladder's attached)
      if self:getState("climbing_ladder") then
         self:moveAndOrientate(anchorTopF, dir, 0.5)

         coro.waitCharacterEvent(self, "OnMoveAndOrientateStop")

         self:moveAndOrientate(anchorTopB, dir, 0.26)
      end

      coro.waitAnimationEnd(self, anims.out)

      self:setState("climbing_ladder", false)
      self:setState("climbing_ladder_down", false)
   end)
end

function CMainCharacter:climb_ladder_finish()
   self:setDisableActionStates(false)
   self:setHeadLookingAllowed(true)
   self.ladderObj = nil
end

function CMainCharacter:restAtCamp(obj)
   getScene():tryAutoSave()
   self.campObject = obj
   self:setState("resting", true)
   return true
end

function CMainCharacter:leaveCamp(obj)
   if self:getState("cooking") or gameplayUI.waitingUI:isWaitingMode() then
      return false
   end
   self:setState("resting", false)
   self.campObject = nil
   return true
end

function CMainCharacter:rest_()
   return self:getState("resting")
end

function CMainCharacter:rest_running()
   self.restCoro = runTimerCo(function()
      self:setHeadLookingAllowed(false)
      self:holsterWeapon()
      self:setOrientationSpeed(0)
      self:setDisableActionStates(true)

      coro.wait(0.2) --Wait for the player movement to stop

      if self.campObject then
         local offset = vec3Add(vec3Mul(vec3Normalize(vec3Sub(self:getPose():getPos(), self.campObject:getPose():getPos())), 120), self.campObject:getPose():getPos())
         offset.y = offset.y + 10
         self:moveAndOrientate(offset, vec3Normalize(vec3Sub(self.campObject:getPose():getPos(), self:getPose():getPos())), 0.5)
      end

      self:setCameraHeight(70, 1.0)
      self:setCameraDist(100, 1.5)
      self:setCameraFov(getDefaultPlayerCameraFov(), 0.5)

      gameplayUI.restHintUI:show(true)

      --Means we have to sit down and not just transfer from these sub states
      if not self:getState("finished_cooking") and not self:getState("finished_drinking") and not self:getState("finished_eating") then
         self.animationsManager:playAction(self.animations.idle.to.sitbyfire)

         coro.wait(1) --Pause to let 'to' anim almost finish

         self.statusEffectsManager:addStatusEffect({name = "restBuff"})
      else
         self:setState("finished_cooking", false)
         self:setState("finished_drinking", false)
         self:setState("finished_eating", false)
      end
      self.animationsManager:playCycle(self.animations.sitbyfire.default, 0)
      self:setState("blockItemUse", false)
      self:setState("disableInteraction", false)
      self.restCoro = nil
   end)
end

function CMainCharacter:rest_finish()
   runTimerCo(function()
      gameplayUI.restHintUI:show(false)
      gameplayUI.waitingUI:show(false)

      self:setState("finished_cooking", false)
      self:setState("finished_drinking", false)
      self:setState("finished_eating", false)

      --Means we have to get up and not just transfer to these sub states
      if not self:getState("cooking") and not self:getState("eating") and not self:getState("drinking") then
         self.animationsManager:playAction(self.animations.sitbyfire.to.idle)
         self:setState("disableInteraction", true)

         coro.waitAnimationEnd(self, self.animations.sitbyfire.to.idle)

         self:setDisableActionStates(false)
         self:setHeadLookingAllowed(true)
         self.statusEffectsManager:destroyEffectsByName("restBuff")
      end
   end)
end

function CMainCharacter:forceStopResting()
   self:tryCancelCooking()
   self:tryCancelConsuming()

   --Wait for ai to start getting back to the rest state and stop it
   runTimer(0, nil, function()
      if self:getState("resting") then
         if self.restCoro then
            self.restCoro:stop()
            self.restCoro = nil
         end
         if self.campObject then
            self.campObject:deactivate(self)
         else
            self:setState("resting", false)
         end
      end
   end, false)
end

--Isn't initiated in the old AI system.
function CMainCharacter:restAtBed(obj)
   getScene():tryAutoSave()
   self.bedObject = obj
   self:setState("sleepAtBed", true)
   self:restAtBed_running()
   return true
end

function CMainCharacter:leaveBed(obj)
   if gameplayUI.waitingUI:isWaitingMode() then return false end
   self:setState("sleepAtBed", false)
   self:restAtBed_finish()
   self.bedObject = nil
   return true
end

function CMainCharacter:restAtBed_running()
   runTimerCo(function()
      self:setHeadLookingAllowed(false)
      self:holsterWeapon()
      self:setOrientationSpeed(0)
      self:setDisableActionStates(true)
      self:setCollision(false)

      coro.wait(0.2) --Wait for the player movement to stop

      local offset = localPointToWorld({x=0,y=0,z=-80}, self.bedObject:getPose())
      offset.y = self:getPose():getPos().y
      local dir = vec3RotateQuat({x=0,y=0,z=-1}, self.bedObject:getPose():getRotQuat())
      self:moveAndOrientate(offset, dir, 0.5)

      self.animationsManager:playCycle(self.animations.sleepAtBed.loop)
      self.animationsManager:playAction(self.animations.sleepAtBed.to)

      coro.wait(1) --Pause to let 'to' anim almost finish

      self:setState("disableInteraction", false)
      gameplayUI:closeUI()
      gameplayUI.waitingUI:show(true)
      gameplayUI.billboardUI:setup("Sleeping", string.format("Press '%s' to get up", getButtonCurrentKeyName("ACTIVATE")))
   end)
end

function CMainCharacter:restAtBed_finish()
   runTimerCo(function()
      gameplayUI.billboardUI:show(false)
      gameplayUI.restHintUI:show(false)
      gameplayUI.waitingUI:show(false)
      self.animationsManager:playCycle("idle")
      self.animationsManager:playAction(self.animations.sleepAtBed.out)
      self:setState("disableInteraction", true)

      coro.waitAnimationEnd(self, self.animations.sleepAtBed.out)

      self:setCollision(true)
      self:setDisableActionStates(false)
      self:setHeadLookingAllowed(true)
   end)
end

function CMainCharacter:setDisableActionStates(state)
   self:setState("blockItemUse", state)
   self:setState("disableAttack", state)
   self:setState("disableMove", state)
   self:setState("disableJump", state)
   self:setState("disableInteraction", state)
end

function CMainCharacter:cook_()
   return self:getState("cooking")
end

function CMainCharacter:cook_running()
   local cookTime = 5
   self.cookCoro = runTimerCo(function()
      self:holsterWeapon()
      self:setState("blockItemUse", true)
      self:setState("disableInteraction", true)

      self.animationsManager:playAction(self.animations.sitbyfire.cook)

      local cookInfo = ItemsData.getItemCookInfo(self.cookItem:getItemName())
      self.cookingStick = getScene():createEntity("wooden_stick.sbg", "")
      self.cookingStick:getPose():setParent(self:getBonePose("item_slot" .. self:getWeaponSlot()))
      self.cookingStick:getPose():resetLocalPose()

      local foodPos = {x=0,y=20,z=-35}
      self.cookEntity = getScene():createEntity(cookInfo.model, "")
      self.cookEntity:getPose():setParent(self.cookingStick:getPose())
      self.cookEntity:getPose():resetLocalPose()
      self.cookEntity:getPose():setLocalPos(foodPos)
      self.cookEntity:setTexture(0, cookInfo.texRaw)

      self.fx.fry:getPose():setParent(self.cookEntity:getPose())
      self.fx.fry:getPose():resetLocalPose()
      self.fx.fry:play()

      self.sounds.fry:getPose():setParent(self.cookEntity:getPose())
      self.sounds.fry:getPose():resetLocalPose()
      self.sounds.fry:play()
      self.sounds.fry:setVolume(1)

      gameplayUI.interactProgressUI:setup("Cooking", cookTime)

      coro.wait(cookTime/2)

      self.cookEntity:setTexture(0, cookInfo.texCooked)
      self.sounds.fry:setVolume(2)

      coro.wait(cookTime/2)

      self:setState("cooking", false)
      self.cookCoro = nil
   end)
end

function CMainCharacter:cook_finish()
   self:setState("blockItemUse", false)
   self:setState("disableInteraction", false)

   self:setState("resting", true)
   self:setState("finished_cooking", true)

   if self.cookItem then
      local cookInfo = ItemsData.getItemCookInfo(self.cookItem:getItemName())
      local count = self.cookCount or 1
      self:getInventory():destroyItem(self.cookItem, count)
      self:getInventory():addItem(cookInfo.item, count)

      self.fx.fry:getPose():resetParent()
      self.fx.fry:stop()

      getScene():destroyEntity(self.cookingStick)
      getScene():destroyEntity(self.cookEntity)
   end

   self.cookCount  = nil
   self.cookEntity = nil
   self.cookItem   = nil
end

function CMainCharacter:consumeItem(item)
   self:setState("consuming", true)
   self.consumingItem = item
   self:consume_running()
end

function CMainCharacter:consume_running()
   self.consumeCoro = runTimerCo(function()
      local item = self.consumingItem
      self:setHeadLookingAllowed(false)
      self:setDisableActionStates(true)
      self:holsterWeapon()

      local itemName = item:getItemName()
      local itemModel    = ItemsData.getItemModel(item:getItemName())
      local consumeModel = ItemsData.getItemConsumeModel(itemName) or itemModel
      self.consumeEntity = hlp.spawnConsumeEntity(item, self:getBonePose("item_slot" .. self:getWeaponSlot()))

      local anim = ""
      if item:isFood() then
         anim = (self:getState("resting") and self.animations.sitbyfire.eat) or self.animations.idle.eat.default
         self.animationsManager:subscribeAnimationEventIn(anim, "item_change", hlp.safeDestroyEntity, self.consumeEntity)
      elseif item:isDrink() then
         anim = (self:getState("resting") and self.animations.sitbyfire.drink) or self.animations.idle.drink.default
      elseif item:isSmokable() then
         anim = self.animations.idle.to.smoke
         self.animationsManager:subscribeAnimationEventIn(anim, "smoking_blow", self.fx.smoking_smoke.play, self.fx.smoking_smoke)
         self.animationsManager:subscribeAnimationEventIn(anim, "item_change", hlp.safeDestroyEntity, self.consumeEntity)
      elseif item:isInjector() then
         anim = self.animations.idle.injector.default
         self.animationsManager:subscribeAnimationEventIn(anim, "item_change", function() self.consumeEntity:getMeshByName(consumeModel):setVisible(false) end)
      end

      self.animationsManager:playAction(anim)

      coro.waitAnimationEventIn(self, anim, "buff_apply")

      self:applyItemEffects(item)

      coro.waitAnimationEnd(self, anim)

      self:setState("consuming", false)
      self:consume_finish()
      self.consumeCoro = nil
   end)
end

function CMainCharacter:consume_finish()
   hlp.safeDestroyEntity(self.consumeEntity)
   self.fx.smoking_smoke:stop()
   self:setHeadLookingAllowed(true)
   self.consumingItem = nil
   self:setDisableActionStates(false)
end

function CMainCharacter:interact_start()
   if self:getState("talk") then
      self:animatedMoveEvent("idle", nil)
   else
      self:holsterWeapon()
      self.animationsManager:playCycle(self.animations.crouch.device)
   end
end

-- not all interactable objects have a __tostring method that points to getDescriptiveName
-- TODO:FIXME: fix it!
local function tryGetDescriptiveName(obj)
   if obj then
      if obj.getDescriptiveName then return obj:getDescriptiveName() end
      if obj.getName then return obj:getName() end
   end
end

function CMainCharacter:interactStart()
   self:interactStopTimer()

   --log("Interact Start: ".. self.interactType)

   if self.interactType == "activate" then
      log("Activating " .. tostring(tryGetDescriptiveName(self.interactTarget)))

      if self.interactTime > 0 then
         questSystem:fireEvent("start_activate", self.interactTarget:getName(), self.interactTarget)
         self:setState("interacting", true)

         gameplayUI.interactProgressUI:setup("Interacting", self.interactTime)

         self.interactTimer = runTimer(self.interactTime, self,  function (obj)
            if obj.interactTarget.activate then
               obj.interactTarget:activate(obj)
            end
            obj:interactStop()
         end, false)
      else
         if self.interactTarget.activate then
            self.interactTarget:activate(self)
         end
         self:interactStop()
      end

   elseif self.interactType == "deactivate" then
      log("Deactivating " .. tostring(tryGetDescriptiveName(self.interactTarget)))

      if self.interactTarget.deactivate then
         self.interactTarget:deactivate(self)
      end

      self:interactStop()

   elseif self.interactType == "drop" then
      if self.interactTime > 0 then
         self:setState("interacting", true)

         gameplayUI.interactProgressUI:setup("Installing", self.interactTime)

         self.interactTimer = runTimer(self.interactTime, nil,  function ()
            local target = self.interactTarget
            self.interactTarget:OnAltActivate()
            gameplayUI:showInventoryPickInfo(target:getLabel() .. " was removed from Inventory")
            self:getInventory():destroyItem(target)
            self:interactStop()
         end, false)
      else
      -- drop item
      end

   elseif self.interactType == "pick" then
      local itemName = (self.interactTarget.getItemName and self.interactTarget:getItemName()) or self.interactTarget.itemName
      if itemName and self:getInventory():canStoreItems(itemName) <= 0 then
         gameplayUI:showInventoryPickInfo("Can't add to Inventory (Limit reached)")
         return
      end
      self:setState("picking", true)
      if isDebug("fastLoot") or self:getState("inAir") then
         self:onObjectTakenEventIn()
         self:onPickupAnimationEnd()
      else
         self:setDisableActionStates(true)
         local difference = self.interactTarget:getPose():getPos().y - self:getPose():getPos().y
         if difference > 130 then
            self.pickupAnimation = self.animations.idle.to.takeobjectfast_top
         elseif difference > 70 then
            self.pickupAnimation = self.animations.idle.to.takeobjectfast_table
         else
            self.pickupAnimation = self.animations.idle.to.takeobjectfast
         end

         self.animationsManager:playAction(self.pickupAnimation, 0.3, 0.3)
         self.animationsManager:subscribeAnimationEventIn(self.pickupAnimation, "obj_taken", self.onObjectTakenEventIn, self)
         self.animationsManager:subscribeAnimationEventIn(self.pickupAnimation, "end", self.onPickupAnimationEnd, self)
         self.animationsManager:subscribeAnimationEnd(self.pickupAnimation, self.onPickupAnimationEnd, self)
      end
   elseif self.interactType == "talk" then
      self:startTalk(self.interactTarget)
      self:interactStop()
   end
end

function CMainCharacter:onObjectTakenEventIn()
   if not self.interactTarget or not hlp.isOperable(self.interactTarget) then return end

   local item
   local res  = nil
   local itemCount
   local countText = ""
   local objName, scriptClass = hlp.getNameAndClass(self.interactTarget)
   if self.interactTarget.isItem then
      item = self.interactTarget
      itemCount = item:getCount()
      res  = self:getInventory():addItemObj(self.interactTarget)
   else
      item = self.interactTarget:getAsItem()
      if item then
         itemCount = item:getCount()
         res  = self:getInventory():addItemObj(item)
      end
   end
   if itemCount then
      countText = string.format("(%d)", itemCount)
   end
   if res then
      gameplayUI:showInventoryPickInfo(item:getLabel() .. countText  .. " was added to Inventory")
   end
end

function CMainCharacter:onPickupAnimationEnd()
   self:setState("picking", false)
   self:setDisableActionStates(false)
   self:interactStop()
   self.animationsManager:clearCallbacks(self.pickupAnimation)
   if self.pickupTimer then
      self.pickupTimer:stop()
      self.pickupTimer = nil
   end
end

function CMainCharacter:interactStop()
   log("Interact Stop")
   self:interactStopTimer()

   gameplayUI.interactProgressUI:show(false)

   self.interactTarget = nil
   self.interactInterruptCB = nil

   self:setState ("interacting", false)
end

function CMainCharacter:interactStopTimer()
   if self.interactTimer then
      self.interactTimer:stop()
      self.interactTimer = nil
   end
end

function CMainCharacter:interact_()
   return self:getState("interacting") or self:getState("talk")
end

function CMainCharacter:startAiming()
   self:setHeadLookingAllowed(false)
   self:setState("aiming", true)
   if self:canAttack() then
      self:startHipFire(0.5)
   end
end

function CMainCharacter:stopAiming()
   self:setState("aiming", false)
   if self:getWeaponSlotItem() then
      self:stopHipFire(5)
   else
      self:stopHipFire(0)
   end
end

function CMainCharacter:startHipFire(speed)
   local currentWeapon = self:getWeaponSlotItem()
   if self:getState("reloading") or not currentWeapon or (currentWeapon and not currentWeapon:isRangedWeapon()) then return end
   self:setHeadLookingAllowed(false)
   self:setState("hipFire", true)
   if self.aimAnimation then
      self.animationsManager:playCycle(self.aimAnimation, speed)
   end
   self:stopHipFire(5)
end

function CMainCharacter:stopHipFire(delay, force)
   delay = delay or 0
   if self.hipFireTimer then
      self.hipFireTimer:stop()
   end
   self.hipFireTimer = runTimer(delay, nil, function()
      self.hipFireTimer = nil
      if force or not self:getState("aiming") then
         self:setHeadLookingAllowed(true)
         self:setState("hipFire", false)
      end
   end, false)
end

function CMainCharacter:tryShoulder(delay)
   delay = delay or 0
   self:stopShoulderTimer()
   self.shoulderTimer = runTimer(delay, nil, function()
      if self:canInteract() and self:canAttack()
         and self:canMove() and self:canJump()
         and self.shoulderAnimation then
         self.animationsManager:playCycle(self.shoulderAnimation)
      end
   end, false)
end

function CMainCharacter:stopShoulderTimer()
   if self.shoulderTimer then
      self.shoulderTimer:stop()
      self.shoulderTimer = nil
   end
end

-- animations
function CMainCharacter:animatedMoveEvent(moveType, dirType)
   if not CPlayer.animatedMoveEvent(self, moveType, dirType) then
      return false
   end

   if self:getState("sliding") or self:getState("gathering") or self:getState("picking") or self:getState("openLootbox")
      or self:getState("knockout") or self:getState("sleepAtBed") or self:getState("falling") then return false end

   local animations   = nil
   local currentWeapon = self:getWeaponSlotItem()
   local animationSet = self:getInventory():getWeaponSlotAnimationSet()
   local jumpAnims    = nil
   local attackAnims  = nil
   local cockAnims    = nil
   local scanAnims    = nil
   self.animations.cock = nil
   self.animations.equipAnims = nil
   self.animations.unequipAnims = nil
   self.animations.scanAnim     = nil

   local default = false

   self:stopShoulderTimer()

   if not self.animations[moveType] then
      return false
   else
      if not self.animations[moveType][dirType] or not dirType then
         animations = self.animations[ moveType ][ animationSet ]
         if not animations then
            animations = self.animations[ moveType ][ "default" ]
            default = true
         end
         jumpAnims   = self.animations[ moveType ]["jump"]
         attackAnims = self.animations[ moveType ]["attack"]
         scanAnims = self.animations[ moveType ]["scan"]
         cockAnims = self.animations[ moveType ]["cock"]
      else
         animations = self.animations[ moveType ][ dirType ][ animationSet ]
         if not animations then
            animations = self.animations[ moveType ][ dirType ][ "default" ]
            default = true
         end
         jumpAnims   = self.animations[ moveType ][ dirType ]["jump"]
         attackAnims = self.animations[ moveType ][ dirType ]["attack"]
         scanAnims = self.animations[ moveType ][ dirType ]["scan"]
         cockAnims = self.animations[ moveType ][ dirType ]["cock"]
      end
      self.animations.equipAnims = self.animations["equip"][ moveType ]
      self.animations.unequipAnims = self.animations["unequip"][ moveType ]
      self.animations.scanAnim = scanAnims and (scanAnims[animationSet] or scanAnims.default)
   end

   local animation = animations

   if type(animations) == "table" then
      if default then
         animation = random.choice(animations)
      else
         animation = animations[1]
      end
   end

   if jumpAnims then
      self.animations.jump = jumpAnims[animationSet]
      if not self.animations.jump then
         self.animations.jump = jumpAnims["default"]
      end
   end

   if self:getState("swimming") then
      if moveType == "idle" then
         animation = self.animations.swim.idle
      elseif moveType == "walk" or moveType == "run" or moveType == "sprint" then
         animation = self.animations.swim[dirType]
      end
   elseif self:getState("crouch") then
      animation = self.animations.crouch.default
   elseif self:getState("jumping") then
      animation = self.animations.jump
   end

   --log("event type = " .. eventType)
   -- aim animation processing
   if (animations and type(animations) == "table" and not default
         and not self:getState("swimming") and not self:getState("jumping")
         and currentWeapon:isRangedWeapon()) then
      self.loopAnimation = animations[1]
      self.aimAnimation  = animations[#animations]
      self.shoulderAnimation = animations[2]

      if self:getState("hipFire") then
         animation = self.aimAnimation
      else
         animation = self.loopAnimation
         if moveType == "idle" then
            self:tryShoulder(5)
         end
      end
   elseif self:getState("remoteControl") then
      animation = self.animations.control.default
   else
      self.loopAnimation = animation
      self.aimAnimation  = nil
   end

   --log(animation)
   self.animationsManager:playCycle(animation)
   if type(animation) ~= "table" then
      self.animationsManager:subscribeAnimationEventIn(animation, "step1", self.onStepEventIn, self)
      self.animationsManager:subscribeAnimationEventIn(animation, "step2", self.onStepEventIn, self)
   end


   if attackAnims then
      self.animations.attack = attackAnims[ animationSet ]

      if cockAnims then
         self.animations.cock = cockAnims[animationSet]
      end

      self.animations.attackAlt = attackAnims.melee_alt
      if animationSet == "boxing" and attackAnims.boxing_alt then
         self.animations.attackAlt = attackAnims.boxing_alt
      end

      if not self.animations.attack then
         self.animations.attack = attackAnims[ "default" ]
      elseif type(self.animations.attack) == "table" then
         self.animations.attack = random.choice(self.animations.attack)
      end
      if type(self.animations.attackAlt) == "table" then
         self.animations.attackAlt = random.choice(self.animations.attackAlt)
      end
   end

   return true
end

function CMainCharacter:animatedEvent(eventType, direction)
   if not CPlayer.animatedEvent(self, eventType) then
      return false
   end

   if not self.animations[eventType] then
      return false
   end
   --log("event = " .. eventType)
   local currentWeapon = self:getWeaponSlotItem()

   if eventType == "attack" or eventType == "attackAlt" then
      ImmersiveUI.triggerUI("weapon")
      if not currentWeapon then return false end

      local anim = self.animations.attack

      --TODO:FIXME: Figure out why attack event sometimes sent before self.animations.attack assign
      if not anim or anim == "" then return end

      if eventType == "attackAlt" and currentWeapon:isMeleeWeapon() then anim = self.animations.attackAlt end

      if currentWeapon then
         if self:getState("reloading") and currentWeapon:isRangedWeapon() and currentWeapon:isMagazineEmpty() then
            return false
         elseif self:getState("reloading") then
            self:tryCancelReloading()
         end
         self:startHipFire(0.01)

         if currentWeapon:isWeapon() then
            self.attackAnimationTimeStart = getGameTime()
            if currentWeapon:isRangedWeapon() and currentWeapon:isMagazineEmpty() then
               if currentWeapon:getAvailableAmmoItem() and getGlobalParam("firstTimeReloading") then
                  gameplayUI.annoyingHintUI:addTask(function() return string.format("Press '%s' to reload", getButtonCurrentKeyName("RELOAD")) end, "reloading")
               end
               runTimer(0.2, self, self.onAttackAnimationStop, false)
            elseif currentWeapon:getWeaponType() == "energy" and currentWeapon.energyCost > self:getStatCount("energy") then
               runTimer(0.2, self, self.onAttackAnimationStop, false)
            else
               self.animationsManager:playAction(anim)
               --Cocking shotguns and carbine
               if self.animations.cock then
                  self.animationsManager:subscribeAnimationEnd(anim, function()
                     self.animationsManager:playAction(self.animations.cock)
                     self.animationsManager:subscribeAnimationEnd(self.animations.cock, self.onAttackAnimationStop, self)
                  end)
               else
                  self.animationsManager:subscribeAnimationEnd(anim, self.onAttackAnimationStop, self)
               end
            end

            self:setState("disableInteraction", true)
            self:setState("disableAttack", true)
            self:setState("blockItemUse", true)
            if self.safeDisableAttackTimer == nil then
               self.safeDisableAttackTimer = runTimer(5, nil, function()
                  self:setState("disableAttack", false)
                  self:setState("disableMove", false)
                  self:setState("blockItemUse", false)
                  self:setState("disableInteraction", false)
               end, false)
            end
         end

         if currentWeapon:isMeleeWeapon() then
            self:setHeadLookingAllowed(false)
            self:setState("disableJump", true)
            self:setState("disableInteraction", true)
            if not string.find(anim, "__") then
               self:setState("disableMove", true)
            end
            self.animationsManager:subscribeAnimationEventIn(anim, "attack", self.onAttackAnimationIn, self)
            self.animationsManager:subscribeAnimationEventOut(anim, "attack", self.onAttackAnimationOut, self)
         elseif currentWeapon:isRangedWeapon() then
            runTimer(0.05, nil, function()
               if getGameOption("cameraShake") and currentWeapon:getMagazine() > 0 then
                  if currentWeapon:getAnimations() == "shotgun" then
                     self:shakeCamera(5, 0.2)
                  elseif currentWeapon:getWeaponType() ~= "energy" then
                     self:shakeCamera(3, 0.2)
                  end
               end
               self:OnItemActivateSafe(currentWeapon)
               self:spendStat("stamina", "staminaRangeAttackCost", true)
            end, false)
         else
            self:OnItemActivateSafe(currentWeapon)
         end
      end

   elseif eventType == "land" then
      if self.deltaLandingSpeed > 0 and not self.god_mode then
         self:setState("landing", true)
         self:setDisableActionStates(true)
         local function landingEnd(self)
            self:setState("landing", false)
            self:setDisableActionStates(false)
         end

         local fallDamage = scaleValue(self:getStatCount("healthMax"), self.deltaLandingSpeed, self.parameters.maxLandingSpeed)
         local anim
         local animationSet = self:getInventory():getWeaponSlotAnimationSet()
         if fallDamage <= 50 then
            anim = self.animations.land.default[animationSet] or self.animations.land.default.default
         else
            anim = self.animations.land.hard[animationSet] or self.animations.land.hard.default
         end
         self.animationsManager:playAction(anim)
         self.animationsManager:subscribeAnimationEnd(anim, landingEnd, self)
      end
   elseif eventType == "jump" then
      self.animationsManager:stopActionOrCycle(self.animations.jump)
      self:spendStat("stamina", "staminaJumpCost", true)
      self.sounds.jump:play()
   elseif eventType == "hit" then
      local anim = self.animations.hit.default
      if direction and currentWeapon and currentWeapon:getAnimations() then
         local animSet = currentWeapon:getAnimations()
         if self.animations.hit[animSet] then
            anim = self.animations.hit[animSet][direction]
         end

         if currentWeapon:isRangedWeapon() then
            self:startHipFire(0.1)
         end
      end

      if not self:getState("climbing_ladder") and not self:getState("climbing_ladder_down") then
         self.animationsManager:playAction(anim, 0.3, 0.3)
      else
         self.soundManager:OnEventIn("hurt2")
      end
   end

   return true
end

function CMainCharacter:onAttackAnimationIn()
   self:OnItemActivateSafe(self:getWeaponSlotItem())
   self:spendStat("stamina", "staminaMeleeAttackCost", true)
end

function CMainCharacter:onAttackAnimationOut()
   self:OnItemDeactivateSafe(self:getWeaponSlotItem())
end

function CMainCharacter:onAttackAnimationStop()
   local coolDownTime = 0
   local attackAnimationTimeElapsed = math.min(getGameTime() - self.attackAnimationTimeStart, 2)
   local weapon = self:getWeaponSlotItem()
   if weapon then
      self:OnItemDeactivateSafe(weapon)
      coolDownTime = weapon:getCooldown()
      if weapon:isMeleeWeapon() then
         self:setHeadLookingAllowed(true)
      end
   end

   self:setDisableActionStates(false)
   self:setState("disableAttack", true)

   if getGameOption("autoReload") and weapon and weapon:isRangedWeapon() and weapon:isMagazineEmpty() then
      if self:tryReload() then
         return
      end
   end

   coolDownTime = math.max(0, coolDownTime - attackAnimationTimeElapsed)

   runTimer(coolDownTime, self, self.coolDown, false)
end

function CMainCharacter:onStopMessage()
end

function CMainCharacter:startAnimatedGathering(obj, toolPrefab)
   if not gameplayUI.billboardUI:isVisible() then
      gameplayUI.billboardUI:setup("Gathering", "Press 'Activate' to stop")
   end
   self:holsterWeapon()
   self:setDisableActionStates(true)
   self:setState("disableInteraction", false) --so it could be cancelled by player
   self:setState("gathering", true)
   self:setState("waitGatherFinish", false)
   self.gatherObj = obj
   if toolPrefab and not self.toolEntity then
      self.toolEntity = getScene():createEntity(toolPrefab, "")
      if self.toolEntity then
         self.toolEntity:getPose():setParent(self:getBonePose("item_slot" .. self:getWeaponSlot()))
         self.toolEntity:getPose():resetLocalPose()
      end
   end
end

function CMainCharacter:tryStopAnimatedGathering(forced)
   if self.gatherObj:getActivationsLeft() <= 0 or forced then
      self.animationsManager:clearCallbacks(self.gatherAnimation)
      self:setDisableActionStates(false)
      self:setState("gathering", false)
      self:setState("waitGatherFinish", false)
      self.toolEntity = hlp.safeDestroyEntity(self.toolEntity)
      gameplayUI.billboardUI:show(false)
      if self.gatherObj then
         self.gatherObj:deactivate(self)
         self.gatherObj = nil
      end
   else --For player to be able to cancel it again
      self:setState("disableInteraction", false)
   end
end

function CMainCharacter:forceStopGathering(onHit)
   if not onHit then
      self.animationsManager:stopActionsAndCycles()
   end
   self:tryStopAnimatedGathering(true)
end

function CMainCharacter:startDigging(obj)
   self:startAnimatedGathering(obj, "shovel.sbg")
   self.animationsManager:playCycle(self.animations.dig.default)

   local function onDustEventIn()
      self.fx.digging_dust:play()
      runTimer(2, nil, function() self.fx.digging_dust:stop() end, false)
   end

   local function onDigSoundEventIn()
      self.soundManager:OnEventIn(obj:getDigSound())
   end

   local function onDigEventIn()
      self:setState("waitGatherFinish", true)
      self:setState("disableInteraction", true)
      self.gatherObj:onDigDone()
   end

   self.gatherAnimation = self.animations.dig.default
   self.animationsManager:subscribeAnimationEventIn(self.gatherAnimation, "dust", onDustEventIn, self)
   self.animationsManager:subscribeAnimationEventIn(self.gatherAnimation, "dig", onDigEventIn, self)
   self.animationsManager:subscribeAnimationEventIn(self.gatherAnimation, "dig_sound", onDigSoundEventIn, self)
   self.animationsManager:subscribeAnimationEventIn(self.gatherAnimation, "end", self.tryStopAnimatedGathering, self)
end

function CMainCharacter:startMining(obj)
   local prefabName = obj:getPrefabName()
   if obj:getPose():getPos().y - self:getPose():getPos().y > 50
      or prefabName == "shard_4.sbg"
      or prefabName == "shard_5.sbg"
      or prefabName == "shard_6.sbg" then
      self.gatherAnimation = self.animations.mine.front
   else
      self.gatherAnimation = self.animations.mine.down
   end
   self:startAnimatedGathering(obj, "pickaxe.sbg")
   self.animationsManager:playCycle(self.gatherAnimation)

   local function onMiningHit()
      self:setState("waitGatherFinish", true)
      self:setState("disableInteraction", true)
      local timesMined = getGlobalParam("timesMined") + 1
      setGlobalParam("timesMined", timesMined)
      local skillUp = 0
      if timesMined == 10 then
         skillUp = 2
      elseif timesMined == 20 then
         skillUp = 5
      elseif timesMined == 30 then
         skillUp = 10
      end
      self.skillsManager:inc("mining", skillUp)

      if self.gatherAnimation == self.animations.mine.front then
         self.fx.antigrav_hit:getPose():setLocalPos({x=35,y=120,z=-135})
         self.fx.antigrav_hit:play()
      else
         self.fx.antigrav_hit:getPose():setLocalPos({x=20,y=0,z=-135})
         self.fx.antigrav_hit:play()
      end

      local skill = self.skillsManager:get("mining")
      local count = obj.fertility + random.random(-2,2) + (obj.fertility + 1) * math.floor(skill/10)
      count = math.max(count, obj.fertility)
      addItemToPlayer("antigravium_shards.itm", count)

      if not obj.crystalMined and skill * (0.5 + obj.fertility/10) >= random.random(1, 100) then
         addItemToPlayer("antigravium.itm", 1)
         obj.crystalMined = true
      end
      obj.resource = obj.resource - 1
      obj:onMiningHit()
   end

   self.animationsManager:subscribeAnimationEventIn(self.gatherAnimation, "hit", onMiningHit, self)
   self.animationsManager:subscribeAnimationEventIn(self.gatherAnimation, "end", self.tryStopAnimatedGathering, self)
end

function CMainCharacter:coolDown()
   if self.safeDisableAttackTimer then
      self.safeDisableAttackTimer:stop()
      self.safeDisableAttackTimer = nil
   end
   self:setState("disableAttack", false)
end

function CMainCharacter:OnHotbarItemClick(index)
   local hoveredItem = gameplayUI.hoveredItem
   --Set the currently hovered item to hotbar (excluding the Q slot if container is open)
   if hoveredItem and (index ~= 11 or not gameplayUI.inventoryContainer:isVisible()) then
      gameplayUI.hotbarUI:setItemToHotbar(index, hoveredItem)
   else
      ImmersiveUI.triggerUI("weapon")
      local item = self:getInventory():getItemById(gameplayUI.hotbarUI:getHotbarItemIdInSlot(index))
      self:useItem(item)
      gameplayUI.hotbarUI:updateAllHotbarItems()
   end
end

function CMainCharacter:holsterWeapon(doNotInterrupt, forceAutoAssign)
   local pInventory = self:getInventory()
   if not doNotInterrupt then
      self:tryCancelEquipping()
   end
   local weapon = self:getWeaponSlotItem()
   if weapon then
      local fastSlot
      if weapon:isWeapon() then
         fastSlot = weapon:getFastAccessSlot() or forceAutoAssign and pInventory:autoAssignFastAccessSlot(weapon:getId(), true)
      end
      pInventory:unequipSlot(self:getWeaponSlot(), false, false)
      if fastSlot then
         pInventory:equipSlotWithItem(fastSlot, weapon:getId(), true, false)
      end
   end
end

function CMainCharacter:tryCancelEquipping()
   if self:getState("equipping") then
      self.itemToEquip = nil
      self.animationsManager:stopActionsAndCycles()
      self:setState("blockItemUse", false)
      self:setState("disableAttack", false)
      self:setState("equipping", false)
   end
end

function CMainCharacter:tryCancelUnequipping()
   if self:getState("unequipping") then
      self.itemToUnequip = nil
      self.animationsManager:stopActionsAndCycles()
      self:setState("blockItemUse", false)
      self:setState("disableAttack", false)
      self:setState("unequipping", false)
   end
end

function CMainCharacter:equipItem(item)
   local weapon = self:getWeaponSlotItem()
   local slotID = item:getAttireType() or 1
   if slotID == 1 then
      self:setState("equipping", true)
      self.itemToEquip = item
      if weapon then
         self:unequipItem(weapon)
      else
         self:onUnequipEnd()
      end
   else
      self:getInventory():equipSlotWithItem(slotID, item:getId())
   end
end

function CMainCharacter:unequipItem(item, forceAutoAssign)
   if item and item ~= self.itemToUnequip then
      if item == self:getWeaponSlotItem() then
         self:tryCancelReloading()
         self:stopHipFire(0, true)
         self:setState("unequipping", true)
         self:setState("blockItemUse", true)
         self:setState("disableAttack", true)
         self:setDialogAnimationAllowed(false)
         self.itemToUnequip = item
         local unequipAnim = self.animations.unequipAnims[item:getAnimations()]
         if unequipAnim then
            self.animationsManager:playAction(unequipAnim, 0.3, 0.3, nil)
            self.animationsManager:subscribeAnimationEventIn(unequipAnim, "unequip", self.onUnequipEventIn, self, forceAutoAssign)
            self.animationsManager:subscribeAnimationEnd(unequipAnim, self.onUnequipEnd, self)
         else
            self:onUnequipEventIn(forceAutoAssign)
            self:onUnequipEnd()
         end
      else
         local slotID = item:getAttireType() or getKeyByValue(self:getInventory().fastAccessSlots, item:getItemName()) or 1
         self:getInventory():unequipSlot(slotID)
      end
   end
end

function CMainCharacter:onUnequipEventIn(forceAutoAssign)
   self:holsterWeapon(true, forceAutoAssign)
   self:move_start()
end

function CMainCharacter:onUnequipEnd()
   self:setState("unequipping", false)
   self:setState("blockItemUse", false)
   self:setState("disableAttack", false)
   self:setDialogAnimationAllowed(true)
   self.itemToUnequip = nil
   if self.itemToEquip then
      self:setState("equipping", true)
      self:setState("blockItemUse", true)
      self:setState("disableAttack", true)
      self:setDialogAnimationAllowed(false)
      local equipAnim = self.animations.equipAnims[self.itemToEquip:getAnimations()]
      if equipAnim then
         self.animationsManager:playAction(equipAnim, 0.3, 0.3, nil)
         self.animationsManager:subscribeAnimationEventIn(equipAnim, "equip", self.onEquipEventIn, self)
      else
         self:onEquipEventIn()
      end
   end
end

function CMainCharacter:onEquipEventIn()
   if not self.itemToEquip then return end
   local pInventory = self:getInventory()
   if self.itemToEquip:isWeapon() then
      local fastSlot = self.itemToEquip:getFastAccessSlot()
      if fastSlot then
         pInventory:unequipSlot(fastSlot, true)
      else
         pInventory:autoAssignFastAccessSlot(self.itemToEquip:getId(), false)
      end
   end

   self.lastWeapon = self.itemToEquip
   self:getInventory():equipSlotWithItem(self:getWeaponSlot(), self.itemToEquip:getId())
   self:startHipFire(0.01)
   gameplayUI.characterUI:setStatisticsCombat(self.itemToEquip)
   ImmersiveUI.triggerUI("weapon")
   self.itemToEquip = nil
   self:setState("blockItemUse", false)
   self:setState("disableAttack", false)
   self:setState("equipping", false)
   self:setDialogAnimationAllowed(true)
end

function CMainCharacter:useItem(item)
   if item ~= self:getWeaponSlotItem() then self:tryCancelReloading() end
   if self:getState("blockItemUse") then return end

   if item and item ~= self:getWeaponSlotItem() then
      local itemName = item:getItemName()
      if item:isWeapon() then
         if self:getState("resting") then return end
         self:setState("blockItemUse", true)
         self:setState("disableAttack", true)
         self:equipItem(item)

      elseif item:isEquipable() then
         if not item:isEquipped() then
            self:equipItem(item)
         elseif itemName == "scanner.itm" or itemName == "scanner_broken.itm" then
            self:runScanWave(item, true)
         end

      elseif item:isMap() or item:isMessage() or item:getInvCategory() == "drawing" or item:isItemContainer() then
         self:OnItemActivateSafe(item)
      elseif item:isConsumable() then
         self:useConsumable(item)
      end
   end
end

function CMainCharacter:useConsumable(item)
   --Medkits have no animations for now
   if (item:isSmokable() and self:getState("resting")) or item:isBandage() then
      self:applyItemEffects(item)
   else
      self:consumeItem(item)
   end
   self:getInventory():destroyItem(item)
end

function CMainCharacter:nextWeapon()
   CPlayer.nextWeapon(self)
end

function CMainCharacter:prevWeapon()
   CPlayer.prevWeapon(self)
end

function CMainCharacter:interactObject(intType, intObject, interruptCB)
   self.interactType        = intType
   self.interactTarget      = intObject
   self.interactInterruptCB = interruptCB

   --log("Interact Type: " .. intType)

   self.interactTime = 0

   if intObject.getInteractTime then
      self.interactTime = intObject:getInteractTime(intType)
   end

   self:interactStart()
end

function CMainCharacter:preActivateObject()
   local interactor = gameplayUI:getFocusObj()

   if interactor then
      local interactorType = interactor.getType and interactor:getType()
      if interactorType == "activator" and interactor.isActivated and interactor:isActivated() then
         self:interactObject("deactivate", interactor, nil)

      elseif interactorType == "talker" then
         self:interactObject("talk", interactor, nil)

      elseif interactorType == "turret" then
         self:interactObject("activate", interactor, function (obj) obj:interactObject("activate", obj.interactTarget, nil) end)

      elseif interactorType == "pickup" then
         self:interactObject("pick", interactor, nil)

      elseif interactorType == "activator" then
         self:interactObject("activate", interactor, nil)
      end

   elseif self:getWeaponSlotItem() and self:getWeaponSlotItem():hasAltActivation() then
      self:interactObject("drop", self:getWeaponSlotItem(), nil)
   end
end

function CMainCharacter:activateObject()
   if self:activateInterrupt() then
      return true
   end

   if gameplayUI.inventoryPlayer:isVisible() then
      gameplayUI.inventoryPlayer:show(false)
      return true
   end

   return false
end

function CMainCharacter:activateInterrupt()
   if self:getState("interacting") then
      local callback = self.interactInterruptCB
      local target   = self.interactTarget

      self:interactStop()

      if callback then
         self.interactTarget = target
         callback(self)
         self.interactTarget = nil
      end
      return true
   end

   return false
end

function CMainCharacter:startControlObject(object, entityName, entityClass, cameraParams)
   if self.controlledCopy then return end

   if getGlobalParam("firstTimeBug") then
      runTimer(0, gameplayUI, gameplayUI.startBugHint, false)
   end

   self:resetButtons()
   runTimer(0, false, partial(self.setHeadLookingAllowed, self), false)
   gameplayUI:closeUI()

   self:setState("remoteControl", true)

   --Create a copy of the object with a needed player class
   self.controlledCopy = getScene():createEntity(entityName, entityClass)
   self.controlledCopy:getPose():setPos(object:getPose():getPos())
   self.controlledCopy:getPose():setRot(self:getPose():getRot())
   self.controlledCopy:getCamera():getPose():setRot(self:getPose():getRot())
   self.controlledCopy.ownerPlayer = self
   if cameraParams then
      self.controlledCopy:setCameraHeight(cameraParams.height, 0)
      self.controlledCopy:setCameraDist  (cameraParams.dist  , 0)
      self.controlledCopy:setCameraOffset(cameraParams.offset, 0)
      self.controlledCopy:setCameraFov   (cameraParams.fov   , 0)
   end

   --Hide, store and carry the real object on the player copy until release
   self.controlledCopy.controlledOriginal = object
   self.controlledCopy.controlledOriginal:getPose():setParent(self.controlledCopy:getPose())
   self.controlledCopy.controlledOriginal:getPose():resetLocalPose()
   self.controlledCopy.controlledOriginal:setVisible(false)
   self.controlledCopy.controlledOriginal:setActive(false)

   setPlayer(self.controlledCopy)
   gameplayUI:setFocusObj(nil)
end

function CMainCharacter:onStopControlObject()
   if not self.controlledCopy then return end
   log("CMainCharacter:onStopControlObject")
   setPlayer(self)
   gameplayUI:stopBugHint()
   self:setHeadLookingAllowed(true)
   self:setState("remoteControl", false)

   getScene():destroyEntity(self.controlledCopy)
   self.controlledCopy = nil
end

function CMainCharacter:hasItem(itemName)
   local item = self:getInventory():getItemByName(itemName)
   if not item then return false end
   return true
end

function CMainCharacter:OnStuckIn()
end

function CMainCharacter:OnStuckOut()
end


function CMainCharacter:tryCancelActions(onHit)
   self:tryCancelCooking()
   self:tryCancelConsuming()
   self:tryCancelEquipping()
   self:tryCancelUnequipping()
   self:tryCancelReloading()
   self:tryCancelScan()
   if self:getState("resting") then
      self:forceStopResting()
   elseif self:getState("gathering") then
      self:forceStopGathering(onHit)
   end
end

function CMainCharacter:tryCancelLadder()
   if self:getState("climbing_ladder_down") or self:getState("climbing_ladder") then
      if self.ladderCoro then
         self.ladderCoro:stop()
         self.ladderCoro = nil
         self:stopMoveAndOrientate()
      end
      self:setState("climbing_ladder", false)
      self:setState("climbing_ladder_down", false)
      self:climb_ladder_finish()
   end
end

function CMainCharacter:tryCancelScan()
   if self:getState("scan") then
      if self.scanCoro then
         self.scanCoro:stop()
         self.scanCoro = nil
      end
      self:setState("scan", false)
   end
end

function CMainCharacter:tryCancelCooking()
   if self:getState("cooking") then
      if self.cookCoro then
         self.cookCoro:stop()
         self.cookCoro = nil
      end
      self:cook_finish()
      gameplayUI.interactProgressUI:show(false)
      self:setState("cooking", false)
   end
end

function CMainCharacter:tryCancelConsuming()
   if self:getState("consuming") then
      if self.consumeCoro then
         self.consumeCoro:stop()
         self.consumeCoro = nil
      end
      self:consume_finish()
      self:setState("consuming", false)
   end
end

function CMainCharacter:tryCancelReloading()
   if self:getState("reloading") then
      local currentWeapon = self:getWeaponSlotItem()
      if currentWeapon then currentWeapon:stopSound("reload") end
      local animations = self:getCurrentReloadAnimations()
      if type(animations) == "table" then
         for _,anim in ipairs(animations) do
            self:stopAction(anim)
         end
      elseif animations then
         self:stopAction(animations)
      end

      if self.reloadCoro then
         self.reloadCoro:stop()
         self.reloadCoro = nil
      end
      self:reload_finish()
   end
end

function CMainCharacter:OnInventoryChange(event)
   if event.eventType == "ItemAdded" then
      if not self.setupInProgress then
         questSystem:fireEvent("get", event.item:getItemName())
      end
   elseif event.eventType == "ItemGiven" then
      questSystem:fireEvent("give", event.item:getItemName())
   elseif event.eventType == "ItemEquipped" then
      --TODO:FIXME: Think of a more official and universal way to update ammo
      if event.item:isRangedWeapon() and not self.setupInProgress then --Can't update ammo like that upon game load, cause the ammo item might not be there yet
         event.item:updateAmmoCount()
      end
      if event.item:getAttireType() == "gadget" then
         gameplayUI.hotbarUI:setItemToHotbar(11, event.item)
      elseif event.item:getEquippedSlot() == self:getWeaponSlot() and getGameOption("autoReload") then
         if event.item:isRangedWeapon() and event.item:isMagazineEmpty() then
            self:tryReload()
         end
      end
   elseif event.eventType == "ItemUnequipped" then
      if event.item:getAttireType() == "hat" then
         self:wearHair()
      elseif event.item:getAttireType() == "gadget" then
         gameplayUI.hotbarUI:clearHotbarSlot(11)
      end
   end
end

-- ---------------------------------------------------------------------------------------
-- Dialogs' rootine
-- ---------------------------------------------------------------------------------------
function CMainCharacter:startTalk(char)
   if not char then
      return false
   end

   local name = char:getName()
   log("talk start with " .. tostring(name))
   if char:startTalk(self) then
      self.dialogTarget = char

      dialogSystem:subscribeOnStopDialog(self.setHasNoEnemiesOverride, self, self.hasNoEnemiesOverride)
      self:setHasNoEnemiesOverride(true)

      self:tryCancelEquipping()
      self:tryCancelUnequipping()
      self:unequipItem(self:getWeaponSlotItem())
      self:setState("talk", true)
      self:moveAndOrientate(self:getPose():getPos(), vec3Normalize(vec3Sub(char:getPose():getPos(), self:getPose():getPos())), 0.5)
      self:updateCamera()

      --Also call startTalk for other dialog actors
      for _,actor in pairs(char.dialog.actors) do
         if actor ~= self and actor ~= char then
            actor:startTalk(self)
         end
      end

      return true
   end

   log("talk start refused with " .. name)
   return false
end

function CMainCharacter:stopTalk(char)
   if self.dialogTarget then
      self.dialogTarget:stopTalk()

      --Also call stopTalk for other dialog actors
      for _,actor in pairs(self.dialogTarget.dialog.actors) do
         if actor ~= self and actor ~= self.dialogTarget then
            actor:stopTalk(self)
         end
      end

      self.dialogTarget = nil
   end
   self:setState("talk", false)
   CPlayer.stopTalk(self, char)
   return true
end

function CMainCharacter:onStartDialog(animator)
   animator:registerAnimations(self.animations.talk.default, self:getPrefabName())
   self.dialogAnimator = animator
end

function CMainCharacter:onStopDialog()
   self:stopTalk()
   self.animationsManager:stopActionsAndCycles()
end

function CMainCharacter:updateCamera()
   local currentWeapon = self:getWeaponSlotItem()
   local rangedMode = currentWeapon and currentWeapon:isRangedWeapon()
   local aimMode = self:getState("aiming") and (rangedMode or not currentWeapon)

   local camHeight = getDefaultPlayerCameraHeight()
   local camDist   = getDefaultPlayerCameraDistance()
   local camFov    = getDefaultPlayerCameraFov()
   local speed     = 0.25

   if aimMode then
      camHeight = 160
      camDist = 100
      camFov = 45
      if self.rightShoulderAim then
         self:setCameraOffset(53, 0.25)
      else
         self:setCameraOffset(-47, 0.25)
      end
   else
      if self.prevCamOffset == 3 and not rangedMode then
         camHeight = camHeight + 25
      end

      if TerminalUI.isCursorVisible() then
         camHeight = 200
         camDist   = 90
         camFov    = 60
         speed     = 0.5
      elseif getGlobalParam("inScene") == "start_scene" then
         camHeight = 200
         camDist   = 350
         speed     = 8
      elseif getGlobalParam("inScene") == "getup_scene" then
         speed = 10
      end

      if rangedMode then
         camDist = 130
         if self.rightShoulderAim then
            self:setCameraOffset(53, 0.25)
         else
            self:setCameraOffset(-47, 0.25)
         end
      else
         self:setCameraOffset(self.prevCamOffset, speed)
      end
   end

   self:setCameraHeight(camHeight, speed)
   self:setCameraDist  (camDist  , speed)
   self:setCameraFov   (camFov   , speed)
end

function CMainCharacter:startTrade(char)
   self.exchangeTarget = char
   self._exchangeTargetPreviousHasNoEnemiesOverride = self.exchangeTarget.hasNoEnemiesOverride
   self.exchangeTarget:setHasNoEnemiesOverride(true)
   self._previousHasNoEnemiesOverride = self.hasNoEnemiesOverride
   self:setHasNoEnemiesOverride(true)
   self:setState("talk", true)
   self:setState("trading", true)
   self:setState("disableUI", true)
   self:setDisableActionStates(true)
   gameplayUI.tradingUI:show(true)
end

function CMainCharacter:stopTrade(char)
   self.exchangeTarget:setHasNoEnemiesOverride(self._exchangeTargetPreviousHasNoEnemiesOverride)
   self._exchangeTargetPreviousHasNoEnemiesOverride = nil

   self.exchangeTarget:setState("trading", false)
   self.exchangeTarget = nil
   self:setHasNoEnemiesOverride(self._previousHasNoEnemiesOverride)
   self._previousHasNoEnemiesOverride = nil
   self:setState("talk", false)
   self:setState("trading", false)
   self:setState("disableUI", false)
   self:setDisableActionStates(false)
   gameplayUI.tradingUI:show(false)
end



function CMainCharacter:startSwim(swimTrigger)
   if swimTrigger then
      self.swimTrigger = swimTrigger
      self:setState("disableAttack", true)
      self:setState("blockItemUse", true)
      self:setState("disableJump", true)
      self:setState("swimming", true)
      self:holsterWeapon()
   end
end

function CMainCharacter:stopSwim(swimTrigger)
   self.swimTrigger = nil
   self:setState("disableAttack", false)
   self:setState("blockItemUse", false)
   self:setState("disableJump", false)
   self:setState("swimming", false)
end

function CMainCharacter:getCurrentMoveType()
   for _, move in ipairs{"idle", "walk", "run", "sprint"} do
      if self:getState(move.."Mode") then
         return move
      end
   end
   log("ERROR: CMainCharacter:getCurrentMoveType couldn't properly detect current move type")
   return "idle" -- just to be safe
end

function CMainCharacter:getCurrentReloadAnimations()
   local default = "device__left"
   local gun = self:getWeaponSlotItem()
   local reloadAll = self.animations.reload
   local moveType = self:getCurrentMoveType()
   if not gun or not reloadAll or not moveType then
      return default
   end
   local reloadMove = reloadAll[moveType]
   local weaponReloadType = gun:getReloadAnimations()
   if not reloadMove or not weaponReloadType then
      return default
   end

   return reloadMove[weaponReloadType] or default
end


function CMainCharacter:tryReload()
   local weapon = self:getWeaponSlotItem()
   if self:canInteract() and not self:getState("sprintMode")
      and weapon and weapon:isRangedWeapon() and weapon.magazine
      and weapon:getAvailableAmmoItem() and not self:getState("reloading") then
      local ammoAvailable = weapon:getAvailableAmmoCount() - weapon.magazine
      local animations = self:getCurrentReloadAnimations()
      if type(animations) == "table" then animations = animations[1] end
      if ammoAvailable > 0 and weapon.magazine < weapon.magazineMax and animations then
         ImmersiveUI.triggerUI("weapon")
         if getGlobalParam("firstTimeReloading") then
            setGlobalParam("firstTimeReloading", false)
         end
         gameplayUI.annoyingHintUI:completeTask("reloading")
         self:startHipFire(0.1)
         self:setState("reloading", true)
         self:reload_running()
         return true
      end
   end
   return false
end

function CMainCharacter:reload_running()
   self.reloadCoro = runTimerCo(function()
      local weapon = self:getWeaponSlotItem()
      self:setState("disableAttack", false)
      self:setState("disableInteraction", true)
      self:setState("blockItemUse", true)
      self:setHeadLookingAllowed(false)

      local animations = self:getCurrentReloadAnimations()
      --Looped reloading one ammo at a time
      if weapon:getReloadAnimations() == "shotgun1" or weapon:getReloadAnimations() == "carbine" then
         self.animationsManager:playAction(animations[1], 0.3, 0)

         coro.waitAnimationEventIn(self, animations[1], "startloop")

         local ammoAvailable = weapon:getAvailableAmmoCount() - weapon.magazine
         while ammoAvailable > 0 and weapon.magazine < weapon.magazineMax do
            weapon:playSound("reload_loop", true)

            self.animationsManager:playAction(animations[2], 0, 0)

            coro.waitAnimationEventIn(self, animations[2], "reload")

            weapon:OnLoadGun()
            ImmersiveUI.triggerUI("weapon")

            ammoAvailable = weapon:getAvailableAmmoCount() - weapon.magazine
         end

         weapon:playSound("reload_out", true)
         self:setState("waitReloadEnd", true)
         self.animationsManager:playAction(animations[3], 0)

         coro.waitAnimationEnd(self, animations[3])
      else --Normal single animated reloading
         weapon:playSound("reload", true)
         self.animationsManager:playAction(animations)

         coro.waitAnimationEventIn(self, animations, "reload")

         weapon:OnLoadGun()
         ImmersiveUI.triggerUI("weapon")

         coro.waitAnimationEnd(self, animations)
      end

      self.reloadCoro = nil
      self:reload_finish()
   end)
end

function CMainCharacter:reload_finish()
   self:setState("reloading", false)
   self:setState("blockItemUse", false)
   self:setState("waitReloadEnd", false)
   self:setState("disableMove", false)
   self:setState("disableInteraction", false)
   self:setHeadLookingAllowed(true)
end

function CMainCharacter:openLootbox(obj)
   self:setState("openLootbox", true)
   self:setDisableActionStates(true)
   self:holsterWeapon()
   runTimer(0.2, nil, function() --Wait for movement to end
      local pos = obj.animAnchor:getPose():getPos()
      pos.y = obj:getPose():getPos().y
      local dir = vec3RotateQuat({x=0,y=0,z=-1}, obj:getPose():getRotQuat())

      self:moveAndOrientate(pos, dir, 0.3)
      runTimer(0.3, nil, function()
         self.animationsManager:playCycle(self.animations.idle.lootbox.loop)
         self.animationsManager:playAction(self.animations.idle.lootbox.to)
         self.animationsManager:subscribeAnimationEventIn(self.animations.idle.lootbox.to, "end", self.onLootboxOpenEnd, self)
         obj:playAnimation("open", false)
      end, false)
   end, false)
end

function CMainCharacter:onLootboxOpenEnd(obj)
   self:setState("disableInteraction", false)
   self:exchangeStart(self.exchangeTarget)
end

function CMainCharacter:closeLootbox(obj)
   self:setState("disableInteraction", true)
   self:setState("openLootbox", false)
   self.animationsManager:playAction(self.animations.idle.lootbox.out)
   self.animationsManager:subscribeAnimationEventIn(self.animations.idle.lootbox.out, "end", self.onLootboxCloseEnd, self)
   obj:playAnimation("close", false)
end

function CMainCharacter:onLootboxCloseEnd(obj)
   self:setDisableActionStates(false)
end

function CMainCharacter:runScanWave(item, animated)
   self.scanCoro = runTimerCo(function()
      if self.scanWaveTimer or self:getState("scan")
         or self:getStatCount("energy") < math.abs(self:getStatCount("energyScanCost")) then
         self.scanCoro = nil
         return
      end

      local anim = self.animations.scanAnim
      local delayIn
      local delayOut
      local itemName = item:getItemName()

      if animated and anim and not self:getState("aiming") then
         self:setState("scan", true)
         local weapon = self:getWeaponSlotItem()
         local detectMode = weapon and weapon:getItemName() == "strange_detector.itm"
         if detectMode then
            self.animationsManager:playAction(anim)
         else
            delayIn = 0.1
            if self:getState("hipFire") then
               delayOut = 0.4
            else
               delayOut = 0.2
            end
         end
         self.animationsManager:playAction(anim, delayIn, delayOut)

         coro.waitAnimationEventIn(self, anim, "button")
         self:setState("scan", false)
      end

      if not self:spendStat("energy", "energyScanCost", false) then return end

      if itemName == "scanner_broken.itm" then
         self.soundManager:OnEventIn("scan_broken")
         return
      else
         self.soundManager:OnEventIn("scan")
      end

      local breakQuestActive = getGlobalParam("scannerBreakQuestActive") and not isDebug("quest") and not isQuestActive("scan_it")
      local useTimes = getGlobalParam("scannerBreakQuestUseTimesLeft")
      if breakQuestActive and useTimes ~= nil then
         if useTimes > 0 then
            setGlobalParam("scannerBreakQuestUseTimesLeft", useTimes - 1)
         else
            setGlobalParam("scannerBreakQuestActive", false)
            if self:getInventory():destroyItemByName("scanner.itm") then
               self:getInventory():addItem("scanner_broken.itm")
               equipItemForPlayer("scanner_broken.itm", "gadget", false)
               gameplayUI.hotbarUI:setItemToHotbarByName(11, "scanner_broken.itm")

               local scanWaveSoundBreaking = self:createAspect("scan_breaks.wav")
               scanWaveSoundBreaking:getPose():setParent(self:getPose())
               scanWaveSoundBreaking:getPose():resetLocalPose()
               scanWaveSoundBreaking:getPose():setLocalPos({x=0,y=100,z=0})
               scanWaveSoundBreaking:setLoop(false)
               scanWaveSoundBreaking:setVolume(0.15)
               scanWaveSoundBreaking:setDistance(1000)
               scanWaveSoundBreaking:play()

               coro.wait(0)

               local esfx = self:createAspect("electro_shock.sps")
               esfx:getPose():setParent(self:getBonePose("LeftForeArmRoll"))
               esfx:getPose():resetLocalPos()
               esfx:disable()
               esfx:setLoop(false)
               esfx:play()
               local dmg = 5
               if self:getStatCount("health") <= dmg then
                  dmg = 0
               end
               self:hit(dmg, nil)

               coro.wait(1)

               startQuest("broken_scanner")
               return
            end
         end
      end

      if not self.scanWave then
         self.scanWave = self:createAspect("scan_wave.sbg")
         self.scanWave:setVisible(false)
      end

      local scanRadius = 2000
      local baseRadius = 200

      self:setHighlightsRadius(baseRadius)

      local pos = self:getPose():getPos()
      self.scanWave:getPose():setPos({x=pos.x,y=pos.y+100,z=pos.z})
      self.scanWave:getPose():setScale({x=baseRadius,y=baseRadius,z=baseRadius})
      self.scanWave:setVisible(true)

      self.scanWaveTimer = runTimerExt(1/60, {obj=self, initRadius=baseRadius},
         function (params)
            if params.obj.scanWaveTimer then
               local radius = params.initRadius + params.obj.scanWaveTimer:getTimeDuration() * (scanRadius-params.initRadius)

               params.obj.scanWave:getPose():setScale({x=radius/100,y=radius/100,z=radius/100})
               params.obj:setHighlightsRadius(radius)

               if params.obj.scanWaveTimer and params.obj.scanWaveTimer:getTimeLeft() == 0 then
                  params.obj.scanWave:setVisible(false)
                  params.obj:setHighlightsRadius(0)
                  params.obj.scanWaveTimer = nil
               end
            end
         end,
      1)
      self.scanCoro = nil
   end)
end

function CMainCharacter:isDamageAllowed(charAttacker)
   if charAttacker and charAttacker:getScriptClass() == "CMainCharacterBug" then return false end
   return CCharacter.isDamageAllowed(self, charAttacker)
end

function CMainCharacter:hit(damage, charAttacker, direction)
   if self:getState("dead") then return end
   local prevHealthPercent = self:getStatPercent("health")
   CPlayer.hit(self, damage, charAttacker, direction)

   local currentHealth = self:getStatPercent("health")
   self:tryCancelActions(true)
   if currentHealth < 20 or (prevHealthPercent - currentHealth) >= 10 then
      self:tryCancelLadder()
   end
end

function CMainCharacter:die()
   gameplayUI:closeUI()
   if self.dialogTarget then
      dialogSystem:stopDialog(nil)
   end

   CPlayer.die(self)

   self.sounds.death:play()

   if self.hipFireTimer then
      self.hipFireTimer:stop()
      self.hipFireTimer = nil
   end

   self.animationsManager:clearAllCallbacks()
   self.animationsManager:playAction(self.animations.die.default, nil, nil, true)

   if self.deathTimer then
      self.deathTimer:stop()
      self.deathTimer = nil
   end
   self.deathTimer = runTimer(3, nil, function()
      if gameplayUI:isGameplayRootWindow() and not isEditor() then
         confirmMessage(gameplayUI.wndGameplay, function()
            pauseGame()
            saveGameMenu()
         end, function()
            exitLocation()
         end, "load a game")
      end
   end, false)
end

function CMainCharacter:OnTriggerEnter(trigger)
   oo.getsuper(CMainCharacter).OnTriggerEnter(self, trigger)
end

function CMainCharacter:addExp(value, silent)
   self.experience.current = self.experience.current + math.ceil(value * (getGlobalParam("expMultiplier") or 1))

   local lvls = 0
   while self.experience.current >= math.floor(self.experience.maxStarting * 1.5 ^ (self.level + lvls - 1)) do
      self.experience.current = self.experience.current - math.floor(self.experience.maxStarting * 1.5 ^ (self.level + lvls - 1))
      lvls = lvls + 1
   end

   gameplayUI.characterUI:updateStatisticsExperience()

   self:addLevels(lvls)

   if not silent and value > 0 then
      gameplayUI:showInfoTextEx("Exp +" .. value, "minor", "")
   end
end

function CMainCharacter:addLevels(value, silent)
   if value > 0 then
      if self.level == 1 then
         gameplayUI.annoyingHintUI:addTask(function() return string.format("You've got attribute points! Press '%s' to raise your stats.", getButtonCurrentKeyName("INVENTORY")) end, "AP")
         gameplayUI.characterUI:highlightUpgradeButtons(true)
      end
      self.level = self.level + value
      self.experience.max = math.floor(self.experience.maxStarting * 1.5 ^ (self.level - 1))
      self.attributePoints = self.attributePoints + value

      gameplayUI.characterUI:updateStatisticsExperience()
      gameplayUI.characterUI:updateStatisticsLevel()
      gameplayUI.characterUI:setStatUpgradeButtonsDisabled(false)

      if not silent then
         self:playSoundScheduled("game_lvlup.wav", 10)
         gameplayUI:showInfoTextEx("Reached level " .. self.level, "major", "")
      end
   end
end

function CMainCharacter:upgradeStat(statName)
   if self.attributePoints > 0 then
      self.attributePoints = self.attributePoints - 1
      self.assignedAttributes[statName] = self.assignedAttributes[statName] + 1
      local value = round(self.upgradeBonuses[statName] * hlp.CGParam("statsUpgradeBonusMul"):get())
      self:changeStatCount(string.gsub(statName, "Max", ""), value) --restore the increased amount, the Max stat gets updated automatically
      gameplayUI.annoyingHintUI:completeTask("AP")
      if self.attributePoints <= 0 then
         gameplayUI.characterUI:setStatUpgradeButtonsDisabled(true)
         gameplayUI.characterUI:highlightUpgradeButtons(false)
      end
   end
end

function CMainCharacter:OnSaveState(state)
   state.feelVisible = self:getFeelVisible()
   state.level = self.level
   state.experience = self.experience.current
   state.initialStyle = self.initialStyle
   --+++++++++++++++++++++++++++++++++++++++++ Mod +++++++++++++++++++++++++++++++++++++++++++++
   state.weaponXP = CritPartialMod:returnhits()
   --+++++++++++++++++++++++++++++++++++++++++ /Mod ++++++++++++++++++++++++++++++++++++++++++++

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
   state.attributePoints = self.attributePoints
   state.assignedAttributes = self.assignedAttributes

   -- installations
   local inst = {}
   local any_inst = false
   for k,v in pairs(self.installations) do
      local class_name = nil
      if v.getScriptClass then
         class_name = v:getScriptClass()
      else
         for k2,v2 in pairs(InstallationData) do
            for k3,v3 in pairs(v2) do
               if k3 == v:getPrefabName() then
                  class_name = v3.type
               end
            end
         end
      end
      if class_name and v.OnSaveState then
         local save_state = {}
         v:OnSaveState(save_state)
         local data = {}
         data["type"] = v:getPrefabName()
         data["class"] = class_name
         data["state"] = save_state
         table.insert(inst, data)
         any_inst = true
      end
   end
   if any_inst then
      state.installations = inst
   end

   state.prevCamOffset = self.prevCamOffset
   state.rightShoulderAim = self.rightShoulderAim
end

function CMainCharacter:OnLoadState(state)
   self.setupInProgress = true
   self.initialStyle = state.initialStyle
   self:setupAppearance(self.initialStyle)

   if state.feelVisible ~= nil then
      self:setFeelVisible(state.feelVisible)
   end

   if state.level then
      self:addLevels(state.level - 1, true)
   end

   if state.experience then
      self:addExp(state.experience, true)
   end
   --+++++++++++++++++++++++++++++++++++++++++ Mod +++++++++++++++++++++++++++++++++++++++++++++
   if state.weaponXP then
      for k,v in pairs (state.weaponXP) do
         CritPartialMod:loadhits(k,v)
      end

   end
   --+++++++++++++++++++++++++++++++++++++++++ /Mod ++++++++++++++++++++++++++++++++++++++++++++
   --Status effects, attributes and items should be loaded before stats as their bonuses affect stats' clamping values.
   if state.statusEffects then
      for _,effectState in ipairs(state.statusEffects) do
         self.statusEffectsManager:addStatusEffect(effectState)
      end
   end

   if state.attributePoints then
      for statName, timesUpgraded in pairs(state.assignedAttributes) do
         for i=1,timesUpgraded do
            self:upgradeStat(statName)
         end
      end
   end

   if state.inventory then
      self:getInventory():deserialize(state.inventory)

      -- installations
      if state.installations then
         for _,v in pairs(state.installations) do
            if v.class then
               local obj = getScene():createEntity(v.type, v.class, {installer=self})
               if obj then
                  if obj.OnLoadState then
                     self:addInstallation(obj)
                     obj:OnLoadState(v.state)
                  else
                     getScene():destroyEntity(obj)
                  end
               end
            end
         end
      end
   end

   self:deserializeStats(state.stats)

   setDefaultPlayerCameraHeight(getGlobalParam("camHeight") or self:getCameraHeight())
   if state.prevCamOffset then self.prevCamOffset = state.prevCamOffset end
   if state.rightShoulderAim then self.rightShoulderAim = state.rightShoulderAim end

   self.setupInProgress = false
   self:updateCamera()
end

function CMainCharacter:getLabel()
   return "Jack"
end

function CMainCharacter:addInstallation(obj)
   local index = tablex.find(self.installations, obj)
   if not index then
      table.insert(self.installations, obj)
      obj:subscribeOnDestroy(self.removeInstallation, self, obj)
      if not getScene():isLoadedGame() then
         questSystem:fireEvent("add_installation", obj:getScriptClass(), obj)
      end
   end
end

function CMainCharacter:removeInstallation(obj)
   local index = tablex.find(self.installations, obj)
   if index then
      table.remove(self.installations, index)
      if not getScene():isLoadedGame() then
         questSystem:fireEvent("remove_installation", obj:getScriptClass(), obj)
      end
   end
end

return {CMainCharacter=CMainCharacter}
