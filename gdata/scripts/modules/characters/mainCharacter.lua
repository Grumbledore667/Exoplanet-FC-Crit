local oo = require "loop.simple"
local ItemsData = (require "itemsData")
local ItemsInfo = (require "itemsData").ItemsInfo
local CPlayer = (require "player").CPlayer
local CCharacter = (require "character").CCharacter
local SkySystem = (require "environment.sky").SkySystem
local InstallationData = (require "items.installation").ItemRecipes

local TerminalUI    = require "ui.terminal"
local ImmersiveUI = require "ui.immersiveUI"
local GUIUtils      = require "ui.utils"

local hlp = require "helpers"
local coro = require "coroutines.helpers"
--+++++++++++++++++++++++++++++++++++++++++ Mod +++++++++++++++++++++++++++++++++++++++++++++
local CritPartialMod  = require "mods.partialcritmod"
--+++++++++++++++++++++++++++++++++++++++++ /Mod ++++++++++++++++++++++++++++++++++++++++++++
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

   self.sounds.cough = self:createAspect("Play_main_hero_cough")
   self.sounds.cough:getPose():setParent(self:getPose())
   self.sounds.cough:getPose():resetLocalPos()
   self.sounds.cough:setDelay(2)
   self.sounds.cough:setDistance(1000)

   self.sounds.fry = self:createAspect("Play_fry")
   self.sounds.fry:getPose():setParent(self:getPose())
   self.sounds.fry:getPose():resetLocalPos()
   self.sounds.fry:setDistance(1000)

   self.sounds.death = self:createAspect("Play_game_over")
   self.sounds.death:getPose():setParent(self:getPose())
   self.sounds.death:getPose():resetLocalPos()
   self.sounds.death:setDistance(2000)

   self.sounds.jump = self:createAspect("Play_human_male_jump")
   self.sounds.jump:getPose():setParent(self:getPose())
   self.sounds.jump:getPose():resetLocalPos()
   self.sounds.jump:setDistance(500)

   --TODO:FIXME: adjust jump sounds when we have new files.
   self.sounds.jump_land = self:createAspect("Play_human_male_jump")
   self.sounds.jump_land:getPose():setParent(self:getPose())
   self.sounds.jump_land:getPose():resetLocalPos()
   self.sounds.jump_land:setDistance(500)

   self.sounds.impact_axe = self:createAspect("Play_main_hero_flesh_impact_axe")
   self.sounds.impact_axe:getPose():setParent(self:getPose())
   self.sounds.impact_axe:getPose():resetLocalPos()
   self.sounds.impact_axe:setDistance(500)

   self.sounds.impact_bullet = self:createAspect("Play_main_hero_flesh_impact_bullet")
   self.sounds.impact_bullet:getPose():setParent(self:getPose())
   self.sounds.impact_bullet:getPose():resetLocalPos()
   self.sounds.impact_bullet:setDistance(500)
end

function CMainCharacter:OnHit(params)
   CPlayer.OnHit(self, params)
   local snd
   if params.impactType == "melee" and params.impactor:getAnimations() ~= "boxing" then
      snd = self.sounds.impact_axe
   elseif params.impactType == "ranged" then
      snd = self.sounds.impact_bullet
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
      staminaSideStepCost = {baseValue = -20},
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
   self:addAttachments({{bone="head_slot", name="hair_jack.sbg"}})
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
   self.aiTree = "ai.trees.mainCharacter"
   self:createTree(self.aiTree)
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
            elseif ItemsData.isItemStackable(itemName) and category ~= "quest" then
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
      local bedObject = self:getBBVar("bedObject")
      if bedObject then
         bedObject:deactivate(self)
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
   self:setState("inAir", false)
   self:setState("falling", false)
   self:setState("jumping", false)
   self:setState("disableAirPickup", false)
   self:tryCancelActions(false)

   runTimerAdv(0.05, false, function()
      if not self:getState("swimming") then
         local deltaLandingSpeed = (-landingSpeed) - self.parameters.maxLandingSpeed
         self.sounds.jump_land:play()

         self:setState("blockItemUse", false)
         self:setState("disableInteraction", false)
         self:setState("disableJump", false)

         if deltaLandingSpeed > 0 then
            self:setBBVar("deltaLandingSpeed", deltaLandingSpeed)
            self:setState("landing", true)
         end
      end
   end)
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
         local bedObject = self:getBBVar("bedObject")
         if self:getState("sleepAtBed") and bedObject then
            bedObject:deactivate(self)
         elseif self:getState("resting") and self.campObject and not gameplayUI.waitingUI:isWaitingMode() then
            self.campObject:deactivate(self)
         elseif self:getState("gathering") then
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
   elseif getButtonDoubleTap("BACK") and currentWeapon and not self:getState("inAir") and self:canMove() then
      self:setBBVar("sideStepDir", "back")
      self:requestBehaviorStart("side_step")
   elseif getButtonDoubleTap("LEFT") and currentWeapon and not self:getState("inAir") and self:canMove() then
      self:setBBVar("sideStepDir", "left")
      self:requestBehaviorStart("side_step")
   elseif getButtonDoubleTap("RIGHT") and currentWeapon and not self:getState("inAir") and self:canMove() then
      self:setBBVar("sideStepDir", "right")
      self:requestBehaviorStart("side_step")

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

-- action methods

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
   local ladderPose = self.ladderObj:getPose()
   local dir = vec3RotateQuat({x=0,y=0,z=1}, ladderPose:getRotQuat())

   self:setHeadLookingAllowed(false)
   self:holsterWeapon()
   self:setOrientationSpeed(0)
   self:setDisableActionStates(true)
   self:setCollisionObjects(false)

   --Wait for character movement to stop
   coro.wait(0.2)

   if self:getState("climbing_ladder") then
      local anchors = self.ladderObj:getAnchors(self, "bottom")
      local speed = 140
      local anims = self.animations.ladder.up

      --Move to the ladder
      self:moveAndOrientate(anchors[1], dir, 0.2)
      --coro.waitCharacterEvent(self, "OnMoveAndOrientateStop")

      self.animationsManager:playAction(anims.to)
      coro.waitAnimationEventIn(self, anims.to, "end")

      --Loop going UP
      self.animationsManager:playCycle(anims.loop, 0)
      self:moveAndOrientate(anchors[2], dir, getDistance(anchors[1], anchors[2]) / speed)
      coro.waitCharacterEvent(self, "OnMoveAndOrientateStop")

      self.animationsManager:playCycle(random.choice(self.animations.idle.default))
      self.animationsManager:playAction(anims.out)

      --Climb up
      self:moveAndOrientate(anchors[3], dir, 1)
      coro.waitCharacterEvent(self, "OnMoveAndOrientateStop")

      self:setCollisionObjects(true) --Turning it on before another moveAndOrientate solves sinking into collider

      --Move forward a little bit, also works as workaround for sinking
      self:moveAndOrientate(anchors[4], dir, 0.2)
      coro.waitCharacterEvent(self, "OnMoveAndOrientateStop")

   elseif self:getState("climbing_ladder_down") then
      local anchors = self.ladderObj:getAnchors(self, "top")
      local speed = 600
      local anims = self.animations.ladder.down

      --Move to the ladder
      self:moveAndOrientate(anchors[1], dir, 0.2)
      coro.waitCharacterEvent(self, "OnMoveAndOrientateStop")

      --Start animation
      self.animationsManager:playCycle(anims.loop)
      self.animationsManager:playAction(anims.to)

      --Drop down on the ladder
      self:moveAndOrientate(anchors[2], dir, self:getAnimDuration(anims.to))
      coro.waitCharacterEvent(self, "OnMoveAndOrientateStop")

      --Loop going DOWN
      self:moveAndOrientate(anchors[3], dir, getDistance(anchors[2], anchors[3]) / speed)
      coro.waitCharacterEvent(self, "OnMoveAndOrientateStop")

      --Get off the ladder
      self.animationsManager:playAction(anims.out, 0, 0)
      self.animationsManager:playCycle(random.choice(self.animations.idle.default), 0)

      self:setCollisionObjects(true) --Turning it on before another moveAndOrientate solves sinking into collider

      --TODO:FIXME:Workaround for sinking
      self:moveAndOrientate(anchors[4], dir, 0.1)
      coro.waitCharacterEvent(self, "OnMoveAndOrientateStop")
   end

   self:setState("climbing_ladder", false)
   self:setState("climbing_ladder_down", false)
end

function CMainCharacter:climb_ladder_finish()
   self:stopMoveAndOrientate()
   self:setDisableActionStates(false)
   self:setHeadLookingAllowed(true)
   self:setCollisionObjects(true)
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

function CMainCharacter:rest_running()
   self:setHeadLookingAllowed(false)
   self:holsterWeapon()
   self:setOrientationSpeed(0)
   self:setDisableActionStates(true)
   self:updateCamera()

   if self.campObject then
      local offset = vec3Add(vec3Mul(vec3Normalize(vec3Sub(self:getPose():getPos(), self.campObject:getPose():getPos())), 120), self.campObject:getPose():getPos())
      offset.y = offset.y + 10
      self:moveAndOrientate(offset, vec3Normalize(vec3Sub(self.campObject:getPose():getPos(), self:getPose():getPos())), 0.1)
      coro.waitCharacterEvent(self, "OnMoveAndOrientateStop")
   end

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
end

function CMainCharacter:rest_finish()
   self:setState("getting up", true)
   self:updateCamera()
end

function CMainCharacter:get_up_running()
   gameplayUI.restHintUI:show(false)
   gameplayUI.waitingUI:show(false)

   self:setState("finished_cooking", false)
   self:setState("finished_drinking", false)
   self:setState("finished_eating", false)

   --Means we have to get up and not just transfer to these sub states
   if not self:getState("cooking") and not self:getState("eating") and not self:getState("drinking") then
      self.animationsManager:playCycle("idle")
      self.animationsManager:playAction(self.animations.sitbyfire.to.idle)
      self:setState("disableInteraction", true)

      coro.waitAnimationEnd(self, self.animations.sitbyfire.to.idle)

      self:setDisableActionStates(false)
      self:setHeadLookingAllowed(true)
      self.statusEffectsManager:destroyEffectsByName("restBuff")
   end
end

function CMainCharacter:get_up_finish()
   self:setState("getting up", false)
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

function CMainCharacter:restAtBed(obj)
   getScene():tryAutoSave()
   self:setBBVar("bedObject", obj)
   self:setState("sleepAtBed", true)
   return true
end

function CMainCharacter:leaveBed(obj)
   if gameplayUI.waitingUI:isWaitingMode() then return false end
   self:setState("sleepAtBed", false)
   self:setState("leavingBed", true)
   return true
end

function CMainCharacter:restAtBed_running()
   self:setHeadLookingAllowed(false)
   self:holsterWeapon()
   self:setOrientationSpeed(0)
   self:setDisableActionStates(true)
   local bedObject = self:getBBVar("bedObject")

   coro.wait(0.2) --Wait for the player movement to stop

   bedObject:setCollisionCharacters(false, false)
   local offset = localPointToWorld({x=0,y=0,z=-80}, bedObject:getPose())
   offset.y = self:getPose():getPos().y
   local dir = vec3RotateQuat({x=0,y=0,z=-1}, bedObject:getPose():getRotQuat())
   self:moveAndOrientate(offset, dir, 0.5)

   self.animationsManager:playCycle(self.animations.sleepAtBed.loop)
   self.animationsManager:playAction(self.animations.sleepAtBed.to)

   coro.wait(1) --Pause to let 'to' anim almost finish
end

function CMainCharacter:restAtBed_finish()
   self:setState("disableInteraction", false)
   gameplayUI:closeUI()
   gameplayUI.waitingUI:show(true)
   gameplayUI.billboardUI:setup("Sleeping", string.format("Press '%s' to get up", getButtonCurrentKeyName("ACTIVATE")))
end

function CMainCharacter:leavingBed_running()
   gameplayUI.billboardUI:show(false)
   gameplayUI.restHintUI:show(false)
   gameplayUI.waitingUI:show(false)
   self.animationsManager:playCycle("idle")
   self.animationsManager:playAction(self.animations.sleepAtBed.out)
   self:setState("disableInteraction", true)

   coro.waitAnimationEnd(self, self.animations.sleepAtBed.out)
end

function CMainCharacter:leavingBed_finish()
   self:setState("leavingBed", false)
   local bedObject = self:getBBVar("bedObject")
   bedObject:setCollisionCharacters(true, true)
   self:setDisableActionStates(false)
   self:setHeadLookingAllowed(true)
   self:setBBVar("bedObject", nil)
end

function CMainCharacter:setDisableActionStates(state)
   self:setState("blockItemUse", state)
   self:setState("disableAttack", state)
   self:setState("disableMove", state)
   self:setState("disableJump", state)
   self:setState("disableInteraction", state)
end

function CMainCharacter:cook_running()
   local cookTime = 5
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
   self:setBBVar("consumingItem", item)
end

function CMainCharacter:consume_running()
   local item = self:getBBVar("consumingItem")
   self:setHeadLookingAllowed(false)
   self:setDisableActionStates(true)
   self:holsterWeapon()

   local itemName = item:getItemName()
   local itemModel = ItemsData.getItemModel(item:getItemName())
   local consumeModel = ItemsData.getItemConsumeModel(itemName) or itemModel
   self.consumeEntity = hlp.spawnConsumeEntity(item, self:getBonePose("item_slot" .. self:getWeaponSlot()))

   local animations = self.animations
   local isResting = self:getState("resting")
   local anim = ""
   if item:isFood() then
      anim = (isResting and animations.sitbyfire.eat) or animations.idle.eat.default
      self.animationsManager:subscribeAnimationEventIn(anim, "item_change", hlp.safeDestroyEntity, self.consumeEntity)
   elseif item:isDrink() then
      anim = (isResting and animations.sitbyfire.drink) or animations.idle.drink.default
   elseif item:isSmokable() then
      -- TODO: support sitbyfire smoking
      anim = animations.idle.to.smoke
      self.animationsManager:subscribeAnimationEventIn(anim, "smoking_blow", self.fx.smoking_smoke.play, self.fx.smoking_smoke)
      self.animationsManager:subscribeAnimationEventIn(anim, "item_change", hlp.safeDestroyEntity, self.consumeEntity)
   elseif item:isInjector() then
      anim = animations.idle.injector.default
      self.animationsManager:subscribeAnimationEventIn(anim, "item_change", function()
         self.consumeEntity:getMeshByName(consumeModel):setVisible(false)
      end)
   end

   local cycle = isResting and animations.sitbyfire.default or animations.idle.default[1]
   self.animationsManager:playCycle(cycle)
   self.animationsManager:playAction(anim)

   coro.waitAnimationEventIn(self, anim, "buff_apply")

   self:applyItemEffects(item)

   coro.waitAnimationEnd(self, anim)
end

function CMainCharacter:consume_finish()
   hlp.safeDestroyEntity(self.consumeEntity)
   self.fx.smoking_smoke:stop()
   self:setHeadLookingAllowed(true)
   self:setBBVar("consumingItem", nil)
   self:setDisableActionStates(false)
   self:setState("consuming", false)
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

   local item, count = self.interactTarget:pickupItem(self.inventory)
   local countText = ""
   if item then
      if count and count > 1 then
         countText = string.format("(%d)", count)
      end
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

function CMainCharacter:startHipFire(delay)
   local currentWeapon = self:getWeaponSlotItem()
   if self:getState("reloading") or not currentWeapon
      or (currentWeapon and not currentWeapon:isRangedWeapon()
      and currentWeapon:getItemName() ~= "strange_detector.itm") then return end
   self:setHeadLookingAllowed(false)
   self:setState("hipFire", true)
   local moveParams = self:getMovementParameters()
   local _, aimAnimation = self:getAimingAnimations(moveParams.moveType, moveParams.dirType, currentWeapon:getAnimations())
   if aimAnimation then
      self.animationsManager:playCycle(aimAnimation, delay)
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

function CMainCharacter:tryShoulder(delay, shoulderAnimation)
   delay = delay or 0
   self:stopShoulderTimer()
   self.shoulderTimer = runTimer(delay, nil, function()
      if self:canInteract() and self:canAttack()
         and self:canMove() and self:canJump()
         and shoulderAnimation then
         self.animationsManager:playCycle(shoulderAnimation)
      end
   end, false)
end

function CMainCharacter:stopShoulderTimer()
   if self.shoulderTimer then
      self.shoulderTimer:stop()
      self.shoulderTimer = nil
   end
end

function CMainCharacter:getDirectionalAnimations(animations, moveType, dirType)
   local animationsMoveType = animations[moveType]

   if not animationsMoveType then
      return nil
   end

   if dirType and animationsMoveType[dirType] then
      animationsMoveType = animationsMoveType[dirType]
   end

   return animationsMoveType
end

-- animations
function CMainCharacter:animatedMoveEvent(moveType, dirType)
   if not CPlayer.animatedMoveEvent(self, moveType, dirType) then
      return false
   end

   if self:getState("sliding") or self:getState("gathering") or self:getState("picking") or self:getState("openLootbox")
      or self:getState("knockout") or self:getState("sleepAtBed") or self:getState("falling") then return false end

   local currentWeapon = self:getWeaponSlotItem()
   local animationSet = currentWeapon and currentWeapon:getAnimations()

   local default = false

   self:stopShoulderTimer()

   local animationsMoveType = self:getDirectionalAnimations(self.animations, moveType, dirType)

   if not animationsMoveType then
      return false
   end

   local jumpAnims = animationsMoveType["jump"]
   local jump
   if jumpAnims then
      jump = jumpAnims[animationSet] or jumpAnims["default"]
   end

   local animations = animationsMoveType[animationSet]
   if not animations then
      animations = animationsMoveType["default"]
      default = true
   end

   local animation = animations
   if type(animations) == "table" then
      if default then
         animation = random.choice(animations)
      else
         animation = animations[1]
      end
   end

   self:setBBVar("lastJumpAnimation", nil)
   if self:getState("swimming") then
      if moveType == "idle" then
         animation = self.animations.swim.idle
      elseif moveType == "walk" or moveType == "run" or moveType == "sprint" then
         animation = self.animations.swim[dirType]
      end
   elseif self:getState("crouch") then
      animation = self.animations.crouch.default
   elseif self:getState("jumping") then
      self:setBBVar("lastJumpAnimation", jump)
      animation = jump
   end

   --log("event type = " .. eventType)
   -- aim animation processing
   local loopAnimation, aimAnimation, shoulderAnimation = self:getAimingAnimations(moveType, dirType, animationSet)
   if (loopAnimation and not self:getState("swimming") and not self:getState("jumping")) then
      if self:getState("hipFire") then
         animation = aimAnimation
      else
         animation = loopAnimation
         if moveType == "idle" then
            self:tryShoulder(5, shoulderAnimation)
         end
      end
   elseif self:getState("remoteControl") then
      animation = self.animations.control.default
   end

   self.animationsManager:playCycle(animation)
   self.animationsManager:subscribeAnimationEventIn(animation, "step1", self.onStepEventIn, self)
   self.animationsManager:subscribeAnimationEventIn(animation, "step2", self.onStepEventIn, self)

   return true
end

function CMainCharacter:getAimingAnimations(moveType, dirType, animationSet)
   local animationsMoveType = self:getDirectionalAnimations(self.animations, moveType, dirType)

   if not animationsMoveType then
      return nil
   end

   local animations = animationsMoveType[animationSet]
   if not animations then
      return nil
   end

   local loopAnimation, aimAnimation, shoulderAnimation
   if type(animations) == "table" then
      loopAnimation = animations[1]
      aimAnimation  = animations[#animations]
      shoulderAnimation = animations[2]
   end

   return loopAnimation, aimAnimation, shoulderAnimation
end

function CMainCharacter:getScanAnimations(moveType, dirType, animationSet)
   local directionalAnimations = self:getDirectionalAnimations(self.animations, moveType, dirType)

   if not directionalAnimations then
      return nil
   end

   local scanAnims = directionalAnimations["scan"]
   return scanAnims and (scanAnims[animationSet] or scanAnims.default)
end

function CMainCharacter:getEquipAnimations(moveType, dirType, animationSet)
   local equip, unequip = self.animations["equip"], self.animations["unequip"]
   equip = equip and equip[moveType] and equip[moveType][animationSet]
   unequip = unequip and unequip[moveType] and unequip[moveType][animationSet]

   return equip, unequip
end

function CMainCharacter:getAttackAnimations(moveType, dirType, animationSet)
   local directionalAnimations = self:getDirectionalAnimations(self.animations, moveType, dirType)

   if not directionalAnimations then
      return nil, nil
   end

   local attackAnims = directionalAnimations["attack"]

   if not attackAnims then
      return nil, nil
   end

   local attack = attackAnims[animationSet]
   local attackAlt = attackAnims["melee_alt"]

   if animationSet == "boxing" and attackAnims["boxing_alt"] then
      attackAlt = attackAnims["boxing_alt"]
   end

   if not attack then
      attack = attackAnims["default"]
   elseif type(attack) == "table" then
      attack = random.choice(attack)
   end
   if type(attackAlt) == "table" then
      attackAlt = random.choice(attackAlt)
   end

   return attack, attackAlt
end

function CMainCharacter:getCockingAnimation(moveType, dirType, animationSet)
   local directionalAnimations = self:getDirectionalAnimations(self.animations, moveType, dirType)

   if not directionalAnimations then
      return nil
   end

   local cockAnims = directionalAnimations["cock"]

   return cockAnims and cockAnims[animationSet]
end

function CMainCharacter:landing_running()
   local waitLandingEnd
   if not self:getState("swimming") then
      local deltaLandingSpeed = self:getBBVar("deltaLandingSpeed")
      if deltaLandingSpeed > 0 and not self.god_mode then
         self:setDisableActionStates(true)

         local fallDamage = scaleValue(self:getStatCount("healthMax"), deltaLandingSpeed, self.parameters.maxLandingSpeed)
         local anim
         local animationSet = self:getInventory():getWeaponSlotAnimationSet()
         if fallDamage <= 50 then
            anim = self.animations.land.default[animationSet] or self.animations.land.default.default
         else
            anim = self.animations.land.hard[animationSet] or self.animations.land.hard.default
         end

         local boots = self:getInventory():getSlotItem("boots")
         if boots and boots.fallDamageBlockMul and self:getStatCount("energy") >= boots.fallEnergyCost then
            fallDamage = fallDamage * boots.fallDamageBlockMul
            self:changeStatCount("energy", -boots.fallEnergyCost)
         end
         self:hit(fallDamage, nil)

         if not self:getState("dead") then
            self.soundManager:OnEventIn("hurt2")

            self.animationsManager:playAction(anim)
            self:animatedMoveEvent("idle")
            waitLandingEnd = anim
         end
      end
   end

   if waitLandingEnd then
      coro.waitAnimationEnd(self, waitLandingEnd)
   end
end

function CMainCharacter:landing_finish()
   self:setState("landing", false)
   self:setDisableActionStates(false)
end

function CMainCharacter:animatedEvent(eventType, direction)
   if not CPlayer.animatedEvent(self, eventType) then
      return false
   end

   local eventsToCheck = {
      ["jump"] = true,
   }
   if eventsToCheck[eventType] then
      if not self.animations[eventType] then
         return false
      end
   end
   --log("event = " .. eventType)

   if eventType == "jump" then
      local lastJumpAnimation = self:getBBVar("lastJumpAnimation")
      if lastJumpAnimation then
         self.animationsManager:stopCycle(lastJumpAnimation)
      end
      self:spendStat("stamina", "staminaJumpCost", true)
      self.sounds.jump:play()
   elseif eventType == "hit" and not (self:getState("climbing_ladder") or self:getState("climbing_ladder_down")) then
      self:setBBVar("hit_recovery_direction", direction)
      self:requestBehaviorStart("hit recovery")
   end

   return true
end

function CMainCharacter:hit_recovery_running()
   local currentWeapon = self:getWeaponSlotItem()
   local direction = self:getBBVar("hit_recovery_direction")

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

   self.animationsManager:playAction(anim, 0.3, 0.3)
   coro.waitAnimationEnd(self, anim)
end

function CMainCharacter:hit_recovery_finish()
   self:setState("hit_recovery", false)
   self:setBBVar("hit_recovery_direction", nil)
end

function CMainCharacter:_stopAttackAnimationTimer()
   if self.attackAnimationTimeStart then
      self.attackAnimationTimeStart:stop()
      self.attackAnimationTimeStart = nil
   end
end

function CMainCharacter:_resetAttackAnimationTimer()
   self:_stopAttackAnimationTimer()
   self.attackAnimationTimeStart = runTimerAdv(math.huge)
end

function CMainCharacter:_getAttackAnimationTime()
   local timer = self.attackAnimationTimeStart
   return timer and timer.getTimeDuration and timer:getTimeDuration() or 0
end

function CMainCharacter:attack_ranged_running()
   local currentWeapon = self:getWeaponSlotItem()

   ImmersiveUI.triggerUI("weapon")

   local moveType, dirType = self:getCurrentMoveType(), self:getMovementParameters().dirType
   local animationSet = currentWeapon:getAnimations()
   local anim = self:getAttackAnimations(moveType, dirType, animationSet)

   if self:getState("reloading") and currentWeapon:isMagazineEmpty() then
      return
   elseif self:getState("reloading") then
      self:tryCancelReloading()
   end
   self:startHipFire(0.01)

   self:setState("disableInteraction", true)
   self:setState("attackCooldown", true)
   self:setState("blockItemUse", true)
   if self.safeCooldownTimer == nil then
      self:_startSafeCooldownTimer()
   end

   self:_resetAttackAnimationTimer()
   if currentWeapon:isMagazineEmpty() then
      if currentWeapon:getAvailableAmmoItem() and getGlobalParam("firstTimeReloading") then
         gameplayUI.annoyingHintUI:addTask(function()
            return string.format("Press '%s' to reload", getButtonCurrentKeyName("RELOAD"))
         end, "reloading")
      end
   elseif currentWeapon:getWeaponType() == "energy" and currentWeapon.energyCost > self:getStatCount("energy") then
      return
   end

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

   if not currentWeapon:isMagazineEmpty() then
      self.animationsManager:playAction(anim)
      coro.waitAnimationEnd(self, anim)
   end

   --Cocking shotguns and carbine
   local cockingAnimation = self:getCockingAnimation(moveType, dirType, animationSet)
   if cockingAnimation then
      self.animationsManager:playAction(cockingAnimation)
      coro.waitAnimationEnd(self, cockingAnimation)
   end
end

function CMainCharacter:attack_ranged_finish()
   local weapon = self:getWeaponSlotItem()
   self:OnItemDeactivateSafe(weapon)

   self:setDisableActionStates(false)

   self:startCooldown()
end

function CMainCharacter:startCooldown()
   local coolDownTime = 0
   local attackAnimationTimeElapsed = math.min(self:_getAttackAnimationTime(), 2)
   self:_stopAttackAnimationTimer()

   local gun = self:getWeaponSlotItem()
   if gun then
      coolDownTime = gun:getCooldown()
   end
   coolDownTime = math.max(0, coolDownTime - attackAnimationTimeElapsed)

   runTimerAdv(coolDownTime, false, self.coolDown, self)
end

function CMainCharacter:_startSafeCooldownTimer()
   self.safeCooldownTimer = runTimer(5, nil, function()
      self:setState("attackCooldown", false)
      self:setState("disableMove", false)
      self:setState("blockItemUse", false)
      self:setState("disableInteraction", false)
   end, false)
end

function CMainCharacter:coolDown()
   if self.safeCooldownTimer then
      self.safeCooldownTimer:stop()
      self.safeCooldownTimer = nil
   end
   self:setState("attackCooldown", false)
end

function CMainCharacter:attack_melee_running()
   local currentWeapon = self:getWeaponSlotItem()

   ImmersiveUI.triggerUI("weapon")

   local moveType, dirType = self:getCurrentMoveType(), self:getMovementParameters().dirType
   local animationSet = currentWeapon:getAnimations()
   local anim, attackAlt = self:getAttackAnimations(moveType, dirType, animationSet)

   if getButton("AIM") then anim = attackAlt end

   self:setState("disableInteraction", true)
   self:setState("attackCooldown", true)
   self:setState("blockItemUse", true)
   if self.safeCooldownTimer == nil then
      self:_startSafeCooldownTimer()
   end

   self.animationsManager:playAction(anim)

   self:setHeadLookingAllowed(false)
   self:setState("disableJump", true)
   self:setState("disableInteraction", true)

   if not string.find(anim, "__") then
      self:setState("disableMove", true)
   end

   coro.waitAnimationEventIn(self, anim, "attack")
   self:OnItemActivateSafe(currentWeapon)
   self:spendStat("stamina", "staminaMeleeAttackCost", true)

   coro.waitAnimationEventOut(self, anim, "attack")
   self:OnItemDeactivateSafe(currentWeapon)

   coro.waitAnimationEnd(self, anim)
end

function CMainCharacter:attack_melee_finish()
   local weapon = self:getWeaponSlotItem()
   self:OnItemDeactivateSafe(weapon)
   self:setHeadLookingAllowed(true)
   self:setDisableActionStates(false)
   self:coolDown()
end

function CMainCharacter:attack_misc_start()
   local currentWeapon = self:getWeaponSlotItem()

   ImmersiveUI.triggerUI("weapon")
   self:OnItemActivateSafe(currentWeapon)
end

function CMainCharacter:attack_misc_finish()
   return self:attack_melee_finish()
end

function CMainCharacter:side_step_running()
   local weapon = self:getWeaponSlotItem()
   local animationSet = self:getInventory():getWeaponSlotAnimationSet()
   local dir = self:getBBVar("sideStepDir")
   local animation = self.animations.step[dir][animationSet]
   if self:spendStat("stamina", "staminaSideStepCost", false) then
      self:setDisableActionStates(true)
      self:setState("sideStepping", true)
      self:stopMove()

      local pushDir = self:getDir()
      if dir == "back" then
         pushDir = vec3RotateEuler(pushDir, { x=0, y=180, z=0})
      elseif dir == "left" then
         pushDir = vec3RotateEuler(pushDir, { x=0, y=90, z=0})
      elseif dir == "right" then
         pushDir = vec3RotateEuler(pushDir, { x=0, y=-90, z=0})
      end
      self:push(pushDir, 10000, 0.6)

      if weapon:isRangedWeapon() then
         self:startHipFire(0)
      else
         self.animationsManager:playCycle(self.animations.idle[animationSet])
      end
      self.animationsManager:playAction(animation)

      coro.waitAnimationEnd(self, animation)
   end
end

function CMainCharacter:side_step_finish()
   self:setState("sideStepping", false)
   self:setDisableActionStates(false)
end

function CMainCharacter:onStopMessage()
end

function CMainCharacter:startAnimatedGathering(obj, toolPrefab)
   if not gameplayUI.billboardUI:isVisible() then
      gameplayUI.billboardUI:setup("Gathering", "Press 'Activate' to stop")
   end
   self:holsterWeapon()
   self:setOrientationSpeed(0)
   self:setDisableActionStates(true)
   self:setState("disableInteraction", false) --so it could be cancelled by player
   self:setState("gathering", true)
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
   if self.gatherObj and self.gatherObj:getActivationsLeft() <= 0 or forced then
      self.animationsManager:clearCallbacks(self.gatherAnimation)
      self:setDisableActionStates(false)
      self:setState("gathering", false)
      hlp.safeDestroyEntity(self.toolEntity)
      self.toolEntity = nil
      gameplayUI.billboardUI:show(false)
      if self.gatherObj then
         self.gatherObj:deactivate(self)
         self.gatherObj = nil
      end
   end
end

function CMainCharacter:forceStopGathering(onHit)
   if not onHit then
      self.animationsManager:stopActionsAndCycles()
   end
   self:tryStopAnimatedGathering(true)
end

function CMainCharacter:startDigging(obj)
   self:setState("digging", true)
   self:setBBVar("gatherObj", obj)
end

function CMainCharacter:digging_start()
   local obj = self:getBBVar("gatherObj")
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
      self.gatherObj:onDigDone()
   end

   self.gatherAnimation = self.animations.dig.default
   self.animationsManager:subscribeAnimationEventIn(self.gatherAnimation, "dust", onDustEventIn, self)
   self.animationsManager:subscribeAnimationEventIn(self.gatherAnimation, "dig", onDigEventIn, self)
   self.animationsManager:subscribeAnimationEventIn(self.gatherAnimation, "dig_sound", onDigSoundEventIn, self)
   self.animationsManager:subscribeAnimationEventIn(self.gatherAnimation, "end", self.tryStopAnimatedGathering, self)
end


function CMainCharacter:startMining(obj)
   self:setState("mining", true)
   self:setBBVar("gatherObj", obj)
end

function CMainCharacter:mining_start()
   local obj = self:getBBVar("gatherObj")
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
      self:setBBVar("itemToEquip", nil)
      self.animationsManager:stopActionsAndCycles()
      self:setState("blockItemUse", false)
      self:setState("disableAttack", false)
      self:setState("equipping", false)
   end
end

function CMainCharacter:tryCancelUnequipping()
   if self:getState("unequipping") then
      self:setBBVar("itemToUnequip", nil)
      self.animationsManager:stopActionsAndCycles()
      self:setState("blockItemUse", false)
      self:setState("disableAttack", false)
      self:setState("unequipping", false)
   end
end

--[[
assume all weapons

equipItem -> check
  equipping?
    ignore, finish current equipping
  unequipping?
    switch item to equip after unequipping
--]]

function CMainCharacter:equipItem(item)
   local slotID = item:getAttireType()
   if not slotID then -- put into weapon slot
      if not self:getState("equipping") then
         self:setBBVar("itemToEquip", item)
      end
   else
      self:getInventory():equipSlotWithItem(slotID, item:getId())
   end
end

--[[
assume all weapons

unequipItem -> check
  equipping?
    equipping same item?
      cancel equip
    equipping another item?
      unequip it
  unequipping?
    same item?
      ignore, already unequipping
    other item?
      unequip slot
--]]
function CMainCharacter:unequipItem(item, forceAutoAssign)
   if not item then
      return
   end

   local function unequipSlot()
      local slotID = item:getAttireType() or item:getFastAccessSlot()
      if slotID then
         self:getInventory():unequipSlot(slotID)
      end
   end

   if self:getState("equipping") then
      if self:getBBVar("itemToEquip") == item then
         self:setState("equipping", false)
      else
         unequipSlot()
      end
   elseif self:getState("unequipping") then
      if self:getBBVar("itemToUnequip") ~= item then
         unequipSlot()
      end
   elseif item == self:getWeaponSlotItem() then
      self:tryCancelReloading()
      self:stopHipFire(0, true)
      self:setState("unequipping", true)
      self:setBBVar("itemToUnequip", item)
      self:setBBVar("forceAutoAssign", forceAutoAssign)
   else
      unequipSlot()
   end
end

function CMainCharacter:unequip_running()
   local itemToUnequip = self:getBBVar("itemToUnequip")
   local itemToEquip = self:getBBVar("itemToEquip")

   local forceAutoAssign = self:getBBVar("forceAutoAssign")

   self:setDialogAnimationAllowed(false)
   self:setState("blockItemUse", true)
   self:setState("disableAttack", true)

   if itemToEquip then
      itemToUnequip = self:getWeaponSlotItem()
      if itemToUnequip then
         self:setBBVar("itemToUnequip", itemToUnequip)
      end
   end

   if itemToUnequip then
      self:setState("unequipping", true)

      local moveType = self:getCurrentMoveType()
      local dirType = self:getMovementParameters().dirType
      local animationSet = itemToUnequip:getAnimations()
      local _, unequipAnim = self:getEquipAnimations(moveType, dirType, animationSet)

      if unequipAnim then
         self.animationsManager:playAction(unequipAnim, 0.3, 0.3, nil)

         coro.waitAnimationEventIn(self, unequipAnim, "unequip")
         self:onUnequipEventIn(forceAutoAssign)

         coro.waitAnimationEnd(self, unequipAnim)
      else
         self:onUnequipEventIn(forceAutoAssign)
      end
   end

   -- we reacquire itemToEquip since it could have changed during the unequipping
   itemToEquip = self:getBBVar("itemToEquip")
   if itemToEquip then
      self:setState("unequipping", false)
      self:setState("equipping", true)
      local moveType = self:getCurrentMoveType()
      local dirType = self:getMovementParameters().dirType
      local animationSet = itemToEquip:getAnimations()
      local equipAnim = self:getEquipAnimations(moveType, dirType, animationSet)
      local cycle = self:getAimingAnimations(moveType, dirType, animationSet)

      if equipAnim then
         self.animationsManager:playAction(equipAnim, 0.3, 0.3, nil)
         if cycle then
            self.animationsManager:playCycle(cycle)
         end

         coro.waitAnimationEventIn(self, equipAnim, "equip")
         self:onEquipEventIn()

         coro.waitAnimationEnd(self, equipAnim)
      else
         self:onEquipEventIn()
      end
   end
end

function CMainCharacter:unequip_finish()
   self:setState("unequipping", false)
   self:setState("equipping", false)
   self:setState("blockItemUse", false)
   self:setState("disableAttack", false)

   self:setDialogAnimationAllowed(true)

   self:setBBVar("itemToUnequip", nil)
   self:setBBVar("itemToEquip", nil)
   self:setBBVar("forceAutoAssign", nil)
end

function CMainCharacter:onUnequipEventIn(forceAutoAssign)
   self:holsterWeapon(true, forceAutoAssign)
   self:move_start() -- TODO: playCycle is called all over the place with aiming animations. see if aiming animations could be moved to ai tree
end

function CMainCharacter:onEquipEventIn()
   local itemToEquip = self:getBBVar("itemToEquip")
   if not itemToEquip then return end
   local pInventory = self:getInventory()
   if itemToEquip:isWeapon() then
      local fastSlot = itemToEquip:getFastAccessSlot()
      if fastSlot then
         pInventory:unequipSlot(fastSlot, true)
      else
         pInventory:autoAssignFastAccessSlot(itemToEquip:getId(), false)
      end
   end

   self.lastWeapon = itemToEquip
   self:getInventory():equipSlotWithItem(self:getWeaponSlot(), itemToEquip:getId())
   self:startHipFire()
   ImmersiveUI.triggerUI("weapon")
   self:setBBVar("itemToEquip", nil)
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

   self:holsterWeapon()

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
   getScene():restoreAmbientForMC()
end

function CMainCharacter:hasItem(itemName)
   local item = self:getInventory():getItemByName(itemName)
   if not item then return false end
   return true
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
   self:setState("consuming", false)
end

-- we're cancelling reload now in the ai tree, when "reloading" state is false
--TODO: lookup use cases and consider renaming or inlining the method
--TODO: we need a way to respond to stateChanged events and the like
function CMainCharacter:tryCancelReloading()
   self:setState("reloading", false)
end

function CMainCharacter:OnInventoryChange(event)
   if event.eventType == "ItemAdded" then
      if not self.setupInProgress then
         questSystem:fireEvent("get", event.item:getItemName())
      end
   elseif event.eventType == "ItemGiven" then
      questSystem:fireEvent("give", event.item:getItemName())
   end
end

function CMainCharacter:OnItemEquip(event)
   CPlayer.OnItemEquip(self, event)

   if event.eventType == "ItemEquipped" then
      if event.item:getAttireType() == "gadget" then
         gameplayUI.hotbarUI:setItemToHotbar(11, event.item)
      elseif event.item:getEquippedSlot() == self:getWeaponSlot() and getGameOption("autoReload") then
         if event.item:isRangedWeapon() and event.item:isMagazineEmpty() then
            self:tryReload()
         end
      end
      --TODO:FIXME: Think of a more official and universal way to update ammo
      if event.item:isRangedWeapon() and not self.setupInProgress then --Can't update ammo like that upon game load, cause the ammo item might not be there yet
         event.item:updateAmmoCount()
      end
   end
end

function CMainCharacter:OnItemUnequip(event)
   CPlayer.OnItemUnequip(self, event)

   if event.eventType == "ItemUnequipped" then
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
end

function CMainCharacter:talking_start()
   self.animationsManager:playCycle("idle")
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
         camHeight = camHeight + 40
         camDist   = 90
         camFov    = 60
         speed     = 0.5
      elseif self:getState("resting") then
         camHeight = camHeight - 110
         camDist = 100
         speed = 1
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
   self:setState("disableInteraction", false)
   self:setState("disableAttack", false)
   self:setState("blockItemUse", false)
   self:setState("disableJump", false)
   self:setState("swimming", false)
end

function CMainCharacter:getCurrentMoveType()
   return self:getMovementParameters().moveType
end

function CMainCharacter:getCurrentReloadAnimations()
   local default = "reload__pistol_aim_idle"
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
         return true
      end
   end
   return false
end

function CMainCharacter:reload_running()
   local weapon = self:getWeaponSlotItem()
   self:setState("disableAttack", false)
   self:setState("disableInteraction", true)
   self:setState("blockItemUse", true)
   self:setHeadLookingAllowed(false)

   local function playAction(...)
      self:setBBVar("lastReloadAnimation", (...))
      return self.animationsManager:playAction(...)
   end

   local animations = self:getCurrentReloadAnimations()
   --Looped reloading one ammo at a time
   if weapon:getReloadAnimations() == "shotgun1" or weapon:getReloadAnimations() == "carbine" then
      playAction(animations[1], 0.3, 0)

      coro.waitAnimationEventIn(self, animations[1], "startloop")

      local ammoAvailable = weapon:getAvailableAmmoCount() - weapon.magazine
      while ammoAvailable > 0 and weapon.magazine < weapon.magazineMax do
         weapon:playSound("reload_loop", true)

         playAction(animations[2], 0, 0)

         coro.waitAnimationEventIn(self, animations[2], "reload")

         weapon:OnLoadGun()
         ImmersiveUI.triggerUI("weapon")

         ammoAvailable = weapon:getAvailableAmmoCount() - weapon.magazine
      end

      weapon:playSound("reload_out", true)
      self:setState("waitReloadEnd", true)
      playAction(animations[3], 0)

      coro.waitAnimationEnd(self, animations[3])
   else --Normal single animated reloading
      weapon:playSound("reload", true)
      playAction(animations)

      coro.waitAnimationEventIn(self, animations, "reload")

      weapon:OnLoadGun()
      ImmersiveUI.triggerUI("weapon")

      coro.waitAnimationEnd(self, animations)
   end
   self:setBBVar("lastReloadAnimation", nil)
end

function CMainCharacter:reload_finish()
   local lastReloadAnimation = self:getBBVar("lastReloadAnimation")
   if lastReloadAnimation then
      self.animationsManager:stopAction(lastReloadAnimation)
      local currentWeapon = self:getWeaponSlotItem()
      if currentWeapon then currentWeapon:stopSound("reload") end
   end
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

      local moveType, dirType = self:getCurrentMoveType(), self:getMovementParameters().dirType
      local animationSet = item:getAnimations()
      local anim = self:getScanAnimations(moveType, dirType, animationSet)
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

               local scanWaveSoundBreaking = self:createAspect("Play_scan_breaks")
               scanWaveSoundBreaking:getPose():setParent(self:getPose())
               scanWaveSoundBreaking:getPose():resetLocalPose()
               scanWaveSoundBreaking:getPose():setLocalPos({x=0,y=100,z=0})
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

      self.scanWaveTimer = runTimerAdv(1/60, 1,
         function ()
            if self.scanWaveTimer then
               local radius = baseRadius + self.scanWaveTimer:getTimeDuration() * (scanRadius-baseRadius)

               self.scanWave:getPose():setScale({x=radius/100,y=radius/100,z=radius/100})
               self:setHighlightsRadius(radius)

               if self.scanWaveTimer and self.scanWaveTimer:getTimeLeft() == 0 then
                  self.scanWave:setVisible(false)
                  self:setHighlightsRadius(0)
                  self.scanWaveTimer = nil
               end
            end
         end)
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
   if self:getState("climbing_ladder") or self:getState("climbing_ladder_down") then
      self.soundManager:OnEventIn("hurt2")
   end
   if currentHealth < 20 or (prevHealthPercent - currentHealth) >= 10 then
      self:setState("climbing_ladder", false)
      self:setState("climbing_ladder_down", false)
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
         self:playSoundScheduled("Play_game_lvlup", 10)
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
   --+++++++++++++++++++++++++++++++++++++++++ Mod +++++++++++++++++++++++++++++++++++++++++++++
   if state.weaponXP then
      for k,v in pairs (state.weaponXP) do
         CritPartialMod:loadhits(k,v)
      end

   end
   --+++++++++++++++++++++++++++++++++++++++++ /Mod ++++++++++++++++++++++++++++++++++++++++++++
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
