local oo = require "loop.simple"

local MiscLabels = require "miscLabels"
local ItemsData = require "itemsData"
local stringx = require "pl.stringx"
local GUIUtils = require "ui.utils"
local hlp = require "helpers"
--+++++++++++++++++++++++++++++++++++++++++ Mod +++++++++++++++++++++++++++++++++++++++++++++
local CritPartialMod  = require "mods.partialcritmod"
--+++++++++++++++++++++++++++++++++++++++++ /Mod ++++++++++++++++++++++++++++++++++++++++++++

local CBaseModule = require "ui.baseModule"

---@class CItemInfoUI : CBaseModule
local CItemInfoUI = oo.class({
   layoutName = "item_info.layout",
}, CBaseModule)

---Internal. Adds colored difference text between two numbers, to show differences of hovered item over equipped one.
local function compareStat(stat1, stat2, text, digits)
   if not stat1 or not stat2 or not text then return end
   digits = digits or 0
   local delta = stat2 - stat1
   local pattern1 = delta < 0 and "%s%s(" or "%s%s(+" --Plus sign is added to positive differences
   local formatString = pattern1 .. "%." .. digits .. "f)%s" --Results in  "%s%s(%.0f)%s" or "%s%s(%.2f)%s" etc.
   if delta > 0 then
      text = string.format(formatString, text, gameplayUI.betterColorTag, delta, gameplayUI.whiteTag)
   elseif delta < 0 then
      text = string.format(formatString, text, gameplayUI.worseColorTag, delta, gameplayUI.whiteTag)
   end
   return text
end

--Methods
function CItemInfoUI:init()
   CBaseModule.init(self)

   self.container = self.wnd:getChild("Container"):toVerticalLayoutContainer()
   self.name = self.wnd:getChild("Container/Name")

   self.stats = self.wnd:getChild("Container/Stats")
   self.stats:setMargin(CEGUI.UBox(CEGUI.UDim(0, 0), CEGUI.UDim(0.08, 0), CEGUI.UDim(0, 0), CEGUI.UDim(0.08, 0)))

   self.value = self.wnd:getChild("Container/Value")
   self.description = self.wnd:getChild("Container/Description")
   self.borders = {
      self.wnd:getChild("BorderLeft"),
      self.wnd:getChild("BorderRight"),
      self.wnd:getChild("Container/BorderTop"),
      self.wnd:getChild("Container/BorderBottom"),
      self.wnd:getChild("Container/BorderName"),
      self.wnd:getChild("Container/BorderDescription"),
   }
end

function CItemInfoUI:show(state, item)
   self.item = nil
   self.itemMockup = nil
   if hlp.isOperable(item) then
      self.item = item
   else
      self.itemMockup = item
   end
   return CBaseModule.show(self, state)
end

function CItemInfoUI:onShow()
   self:setup()
end

function CItemInfoUI:onHide()
   self.item = nil
   self.itemMockup = nil
   self:showDescription(false)
end

function CItemInfoUI:getCharacter()
   if gameplayUI.npcEditorUI and gameplayUI.npcEditorUI:isVisible() then
      return gameplayUI.npcEditorUI.char
   else
      return getMC()
   end
end

function CItemInfoUI:setup()
   local char = self:getCharacter()
   local itemName = self.item and self.item:getItemName() or self.itemMockup.itemName
   local qualityInt = self.item and self.item:getQuality() or ItemsData.getItemDefaultQuality(itemName)
   local equippedItem = char:getInventory():getSlotItem(ItemsData.getAttireType(itemName)) or char:getWeaponSlotItem()

   local qualityTag = gameplayUI.qualityTags[qualityInt]
   self:setBorderColors(gameplayUI.qualityColors[qualityInt])

   local labelText = string.format("%s%s%s", qualityTag, ItemsData.getItemLabel(itemName), gameplayUI.whiteTag)
   self.name:setText(labelText)

   local weaponXp = ""

   if ItemsData.isItemWeapon(itemName) then
      local xpRequired = CritPartialMod:nextLevel(CritPartialMod:currentWPNLevel(CritPartialMod:hits(itemName))+1)-CritPartialMod:hits(itemName)
      if CritPartialMod:returnType(itemName) ~= "Melee" then
         weaponXp = string.format("%s%s%d%s%d%s%s%.4f%s", "-------------Usage Stats-------------\n","WeaponLVL: ", CritPartialMod:currentWPNLevel(CritPartialMod:hits(itemName)),"\nXp to next Level: ", xpRequired, "\nAccuracyBonus: +", gameplayUI.damageColorTags.physical, CritPartialMod:AccuracyBonus(itemName), gameplayUI.whiteTag)
      else
         weaponXp = string.format("%s%s%d%s%d%s", "-------------Usage Stats-------------\n","WeaponLVL: ", CritPartialMod:currentWPNLevel(CritPartialMod:hits(itemName)),"\nXp to next Level: ", xpRequired, gameplayUI.whiteTag)
      end
      CritPartialMod:extLogOut("isWeapon", "YES")
   else
      weaponXp = ""
      CritPartialMod:extLogOut("isWeapon", "NO")
   end
   --STATS
   local infoTable = {
      self:getTypeInfo(itemName, qualityInt),
      self:getQualityInfo(itemName, qualityInt),
      self:getDamageInfo(itemName, qualityInt, equippedItem),
      self:getHitEffectsInfo(itemName, qualityInt),
      self:getArmorInfo(itemName, qualityInt, equippedItem),
      self:getEnergyBlockInfo(itemName, qualityInt, equippedItem),
      self:getAttackSpeedInfo(itemName, qualityInt, equippedItem),
      self:getAccuracyInfo(itemName, qualityInt, equippedItem),
      self:getAmmoInfo(itemName, qualityInt, equippedItem),
      self:getAmmoTypeInfo(itemName, qualityInt),
      self:getEnergyCostInfo(itemName, qualityInt, equippedItem),
      self:getRestoreInfo(itemName, qualityInt),
      self:getEffectsInfo(itemName, qualityInt),
      weaponXp
   }
   local stats = table.concat(infoTable)
   self.stats:setText(stats)

   --VALUE
   self.value:setText(self:getValueInfo(itemName, qualityInt))

   --Reset description to use later as a kind of minimal width
   self.description:setProperty("HorzFormatting", "CentreAligned")
   self.description:setText("Hold 'ALT' for description")

   self:adjustWnd()

   self:showDescription(stats:len() <= 30 or getButton("ALT"))
end

function CItemInfoUI:getTypeInfo(itemName, qualityInt)
   local itemType

   local text = ""
   if ItemsData.isItemWeapon(itemName) then
      itemType = ItemsData.getItemAnimations(itemName)
   else
      itemType = ItemsData.getItemInvCategory(itemName)
   end
   local typeLabel = MiscLabels.getItemTypeLabel(itemType)
   if typeLabel then
      text = string.format("Type: %s\n", typeLabel)
   end
   return text
end

function CItemInfoUI:getQualityInfo(itemName, qualityInt)
   local qualityTag = gameplayUI.qualityTags[qualityInt]

   local text = ""
   if ItemsData.isItemWeapon(itemName) then
      text = string.format("Quality: %s%s%s\n", qualityTag, MiscLabels.getItemQualityLabel(qualityInt), gameplayUI.whiteTag)
   end
   return text
end

function CItemInfoUI:getDamageInfo(itemName, qualityInt, equippedItem)
   local damage = self.item and self.item:getDamage() or ItemsData.getItemDamage(itemName, qualityInt)
   local bulletsInShot = self.item and self.item.getBulletsInShot and self.item:getBulletsInShot() or ItemsData.getItemBulletsInShot(itemName)

   local text = ""
   if damage > 0 then
      local totalDmg = damage * (bulletsInShot or 1)
      text = string.format("%s%s%d%s", "Damage: ", gameplayUI.damageColorTags.physical, totalDmg, gameplayUI.whiteTag)
      if bulletsInShot and bulletsInShot > 1 then
         text = string.format("%s%s(%dx%d)%s", text, gameplayUI.damageColorTags.physical, damage, bulletsInShot, gameplayUI.whiteTag)
      end
      if equippedItem then
         local totalEquippedDmg = equippedItem:getDamage() * (equippedItem.getBulletsInShot and equippedItem:getBulletsInShot() or 1)
         text = compareStat(totalEquippedDmg, totalDmg, text)
      end
      text = string.format("%s\n", text)
   end
   return text
end

function CItemInfoUI:getHitEffectsInfo(itemName, qualityInt)
   local hitEffects = self.item and self.item:getHitEffects() or ItemsData.getItemHitEffects(itemName)

   local text = ""
   if hitEffects then
      for _, effect in ipairs(hitEffects) do
         text = string.format("%s\\[%s\\]", gameplayUI.damageColorTags[effect.damageType], MiscLabels.getLabel(effect.name))
         if effect.changeStats then
            for statName, value in pairs(effect.changeStats) do
               local dpsStr = " DPS "
               if value >= 0 then
                  dpsStr = ""
               end
               local dps = math.abs(value) / effect.duration
               text = string.format("%s  %s %s %s for %d sec%s\n", text, dps, MiscLabels.getBonusLabel(statName), dpsStr, effect.duration, gameplayUI.whiteTag)
            end
         end
      end
   end
   return text
end

function CItemInfoUI:getArmorInfo(itemName, qualityInt, equippedItem)
   local armor = self.item and self.item:getArmor() or ItemsData.getItemArmor(itemName)

   local text = ""
   if armor then
      text = string.format("%s%s%d%s", "Armor: ", gameplayUI.damageColorTags.physical, armor, gameplayUI.whiteTag)
      if equippedItem then
         text = compareStat(equippedItem:getArmor() or 0, armor, text)
      end
      text = string.format("%s\n", text)
   end
   return text
end

function CItemInfoUI:getEnergyBlockInfo(itemName, qualityInt, equippedItem)
   local energyBlock = self.item and self.item:getDmgPerEnergy() or ItemsData.getItemDmgPerEnergy(itemName)

   local text = ""
   if energyBlock then
      text = string.format("Damage/Energy: %.0f", energyBlock)
      local dmgPerEnergy = equippedItem:getDmgPerEnergy() or 0
      if equippedItem then
         text = compareStat(dmgPerEnergy, energyBlock, text, 1)
      end
      text = string.format("%s\n", text)
   end
   return text
end

function CItemInfoUI:getAttackSpeedInfo(itemName, qualityInt, equippedItem)
   local itemCooldown = self.item and self.item:getCooldown() or ItemsData.getItemCooldown(itemName, qualityInt)
   ---Internal. Crutchy method to calculate attack rate of the weapon based on animations it uses. Only for visual reference.
   local function getAttackSpeed(itemName, qualityInt)
      local char = self:getCharacter()
      local attackDuration = 0
      local attackAnim = char.animations.idle.attack[ItemsData.getItemAnimations(itemName)]
      if attackAnim then
         local anims
         if type(attackAnim) == "table" then
            anims = attackAnim
         else
            anims = {attackAnim}
         end

         --Get duration of the whole attack sequence
         for _, anim in pairs(anims) do
            attackDuration = attackDuration + char:getAnimDuration(anim)
         end

         --Get average for weapons with random attacks
         if type(attackAnim) == "table" then
            attackDuration = attackDuration / #attackAnim
         end

         attackDuration = math.max(itemCooldown, attackDuration)
         return attackDuration ~= 0 and 1 / attackDuration or nil
      end
   end

   local attackSpeed = ItemsData.isItemWeapon(itemName) and getAttackSpeed(itemName, qualityInt)

   local text = ""
   if attackSpeed then
      text = string.format("Attack Rate: %.2f", attackSpeed)
      local equippedAttackSpeed = equippedItem and getAttackSpeed(equippedItem:getItemName(), equippedItem:getQuality())
      if equippedAttackSpeed then
         text = compareStat(equippedAttackSpeed, attackSpeed, text, 2)
      end
      text = string.format("%s\n", text)
   end
   return text
end

function CItemInfoUI:getAccuracyInfo(itemName, qualityInt, equippedItem)
   local accuracy = self.item and self.item.getAccuracy and self.item:getAccuracy() or ItemsData.getItemAccuracy(itemName)

   local text = ""
   if accuracy then
      accuracy = (accuracy - 0.9) * 1000
      text = string.format("Accuracy: %.0f", accuracy)
      if equippedItem and equippedItem.getAccuracy then
         local equippedAccuracy = (equippedItem:getAccuracy() - 0.9) * 1000
         text = compareStat(equippedAccuracy, accuracy, text)
      end
      text = string.format("%s\n", text)
   end
   return text
end

function CItemInfoUI:getAmmoInfo(itemName, qualityInt, equippedItem)
   local char = self:getCharacter()
   local magazine = self.item and self.item.getMagazine and self.item:getMagazine() or 0
   local magazineMax = self.item and self.item.getMagazineMax and self.item:getMagazineMax() or ItemsData.getItemMagazineMax(itemName)

   local text = ""
   if ItemsData.isItemRangedWeapon(itemName) and not ItemsData.isItemEnergy(itemName) then
      text = string.format("Mag: %d/%d", magazine, magazineMax)
      if equippedItem and equippedItem.getMagazineMax and not equippedItem:isEnergy() then
         local equippedmagazineMax = equippedItem:getMagazineMax()
         text = compareStat(equippedmagazineMax, magazineMax, text)
      end
      local ammoNames = self.item and self.item:getCompatibleAmmo() or ItemsData.getItemCompatibleAmmo(itemName)
      if ammoNames then
         local ammoItem = char.inventory:getItemByName(ammoNames[1])
         local ammoCount = ammoItem and ammoItem:getCount() or 0
         text = string.format("%s   \\[%d\\]", text, ammoCount)
      end
      text = string.format("%s\n", text)
   end
   return text
end

function CItemInfoUI:getAmmoTypeInfo(itemName, qualityInt)
   local text = ""
   if ItemsData.isItemRangedWeapon(itemName) then
      local ammoNames = self.item and self.item:getCompatibleAmmo() or ItemsData.getItemCompatibleAmmo(itemName)
      local caliber
      if not ItemsData.isItemEnergy(itemName) and ammoNames[1] then
         caliber = ItemsData.getAmmoCaliber(ammoNames[1])
      elseif ItemsData.isItemEnergy(itemName) then
         caliber = "Energy"
      end
      if caliber then
         text = string.format("Ammo type: %s\n", caliber)
      end
   end
   return text
end

function CItemInfoUI:getEnergyCostInfo(itemName, qualityInt, equippedItem)
   local text = ""
   if ItemsData.isItemEnergy(itemName) then
      local energyCost = ItemsData.getItemEnergyCost(itemName)
      text = string.format("Energy Cost: %d", energyCost)
      if equippedItem and equippedItem:isEnergy() then
         local equippedEnergyCost = equippedItem:getEnergyCost()
         text = compareStat(equippedEnergyCost, energyCost, text)
      end
      text = string.format("%s\n", text)
   end
   return text
end

function CItemInfoUI:getRestoreInfo(itemName, qualityInt)
   local foodInfo = ItemsData.getItemFoodInfo(itemName)

   local text = ""
   if foodInfo then
      if foodInfo.health then
         text = string.format("%sRestores: %d health\n", text, foodInfo.health)
      end
      if foodInfo.food then
         text = string.format("%sRestores: %d kcal\n", text, foodInfo.food)
      end
      if foodInfo.water then
         text = string.format("%sRestores: %d ml\n", text, foodInfo.water)
      end
   end
   return text
end

function CItemInfoUI:getEffectsInfo(itemName, qualityInt)
   local permaBuffInfo = ItemsData.getItemPermaBuffInfo(itemName)

   local text = ""
   if permaBuffInfo then
      text = string.format("Permanent Buffs: %s\n", gameplayUI:bonusTableToString(permaBuffInfo))
   end

   local effects = ItemsData.getItemConsumeInfo(itemName)
   if effects then
      text = string.format("%sEffects:\n", text)
      for effectName, effect in pairs(effects) do
         if string.find(effectName, "Debuff") then
            text = string.format("%s%s\\[%s\\]%s", text, gameplayUI.worseColorTag, MiscLabels.getLabel(effectName), gameplayUI.whiteTag)
         else
            text = string.format("%s%s\\[%s\\]%s", text, gameplayUI.betterColorTag, MiscLabels.getLabel(effectName), gameplayUI.whiteTag)
         end
         text = string.format("%s%s", text, gameplayUI:bonusTableToString(effect.changeStats))
         text = string.format("%s%s", text, gameplayUI:bonusTableToString(effect.statBonuses))
         text = string.format("%s\nDuration: %s\n", text, effect.duration)
      end
   end
   if text == "" then
      return text
   else
      return "\n" .. text
   end
end

function CItemInfoUI:getValueInfo(itemName, qualityInt)
   local char = self:getCharacter()
   local val = self.item and self.item:getValue() or ItemsData.getItemValue(itemName, qualityInt)

   local text = ""
   if gameplayUI.tradingUI:isVisible() and not ItemsData.isItemMoney(itemName) and self.item then
      if self.item:getOwner():getOwner() == char then
         local sellMul = getGlobalParam("sellingPriceMultiplier")
         local globalMul = getGlobalParam("sellToVendorMul")
         local personalMul = getGlobalParam(char.exchangeTarget:getName() .. "_sellToVendorMul") or 1
         val = math.ceil(val * sellMul * globalMul * personalMul)
      else
         local globalMul = getGlobalParam("buyFromVendorMul")
         local personalMul = getGlobalParam(char.exchangeTarget:getName() .. "_buyFromVendorMul") or 1
         val = math.ceil(val * globalMul * personalMul)
      end
   end
   local valueTag = "[colour='FFDAA520']"
   text = string.format("%sValue: %d", valueTag, val)
   return text
end

function CItemInfoUI:adjustWnd()
   local borderSize =  self.wnd:getChild("BorderLeft"):getPixelSize().width * 2
   --Set these subwindows according to their text extents (none of them have word wrap)
   self.name:setHeight(CEGUI.UDim(0, GUIUtils.getStaticTextOrLabelVertExtent(self.name)))
   self.stats:setHeight(CEGUI.UDim(0, GUIUtils.getStaticTextOrLabelVertExtent(self.stats)))
   self.value:setHeight(CEGUI.UDim(0, GUIUtils.getStaticTextOrLabelVertExtent(self.value)))

   local width = math.max(GUIUtils.getStaticTextOrLabelHorzExtent(self.stats),
                          GUIUtils.getStaticTextOrLabelHorzExtent(self.name),
                          GUIUtils.getStaticTextOrLabelHorzExtent(self.description)) + borderSize
   --Gets rid of continuous width increase of the container
   self.wnd:setWidth(CEGUI.UDim(0, width))

   --This (or the next frame) fucks up container's relative sizing
   self.container:layout()

   local rect = self.container:getUnclippedOuterRect():get()
   local pixelHeight = rect:getHeight()
   --Rect width plus the width of the vertical borders not included into vertical container
   local pixelWidth = rect:getWidth() + borderSize
   self.wnd:setSize(CEGUI.USize(CEGUI.UDim(0, pixelWidth), CEGUI.UDim(0, pixelHeight)))
end

function CItemInfoUI:showDescription(state)
   if state and (self.item or self.itemMockup) then
      local description = self.item and self.item:getDesc() or ItemsData.getItemDesc(self.itemMockup.itemName)
      self.description:setProperty("HorzFormatting", "WordWrapLeftAligned")
      self.description:setText(description)
   elseif self.stats:getText():len() > 30 then
      self.description:setProperty("HorzFormatting", "CentreAligned")
      self.description:setText("Hold 'ALT' for description")
   end

   --Description does NOT dictate width and has word wrap - it should be adjusted after the main window
   self.description:setHeight(CEGUI.UDim(0, GUIUtils.getStaticTextOrLabelVertExtent(self.description)))
   self.container:layout()
   local rect = self.container:getUnclippedOuterRect():get()
   local pixelHeight = rect:getHeight()
   self.wnd:setHeight(CEGUI.UDim(0, pixelHeight))
end

function CItemInfoUI:setPosition(mousePos)
   local wndSize = self.wnd:getPixelSize()
   local descHeight = self.description:getHeight().offset

   local xoff = mousePos.x - wndSize.width - 15
   local yoff = mousePos.y - (wndSize.height - descHeight)/2
   local pos = CEGUI.UVector2(CEGUI.UDim(0,xoff), CEGUI.UDim(0,yoff))

   if pos.x.offset < 0 then
      pos.x.offset = xoff + wndSize.width + 45
   end

   gameplayUI:retainPositionInsideDisplay(pos, self.wnd)
end

function CItemInfoUI:setBorderColors(color)
   for _, wnd in pairs(self.borders) do
      wnd:setProperty("ImageColours", color)
   end
end

return CItemInfoUI
