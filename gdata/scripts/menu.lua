package.path = package.path .. ';./gdata/scripts/modules/?.lua;./gdata/scripts/modules/?/init.lua'
package.cpath = package.cpath .. ';./gdata/scripts/modules/?.dll'

dofile("./gdata/scripts/modules/ui/menu/menuUtils.lua")
local Backers = require "support"
local console = require "ui.console"
local options = require "ui.menu.options"
--+++++++++++++++++++++++++++++++++++++++++ Mod +++++++++++++++++++++++++++++++++++++++++++++
local loadmodoptions = require "mods.modoptions"
--+++++++++++++++++++++++++++++++++++++++++ /Mod ++++++++++++++++++++++++++++++++++++++++++++
local deb     = require "global.debug"
local keys    = require "global.keys"
local gameOptions = require "global.gameOptions"
local stringio = require "pl.stringio"
local i18n = require "i18n"

_G.clear      = deb.clear
_G.log        = deb.log
_G.versionStr = deb.versionStr
_G.versionInt = deb.versionInt
_G.mainMenuParam = true


deb.init()
_G.isDebug    = deb.isDebug

TPrint("Loading: persistentData.lua\n")
local pData = require "global.persistentData"
pData.init()

_G.addToPersistentTable  = pData.addToPersistentTable
_G.setPersistentTable    = pData.setPersistentTable
_G.getPersistentTable    = pData.getPersistentTable
_G.fetchPersistentTable  = pData.fetchPersistentTable
_G.commitPersistentTable = pData.commitPersistentTable

TPrint("Loading: keys.lua\n")
keys.init()

_G.getButtonCode           = keys.getButtonCode
_G.getButtonCurrentKeyName = keys.getButtonCurrentKeyName

TPrint("Loading: gameOptions.lua\n")
gameOptions.init()

_G.setGameOption = gameOptions.setGameOption
_G.getGameOption = gameOptions.getGameOption
_G.getGameOptions = gameOptions.getGameOptions

local guiContext = CEGUI.System:getSingleton():getDefaultGUIContext()
local wndMgr     = CEGUI.WindowManager:getSingleton()
local GUIUtils   = require "ui.utils"

local logoChangeAnim
local earlyAccessAnim

local function runConsoleCommand()
   if console.selectAutoCompleteItem() then return end
   if not console.runConsoleCommand() then
      console:getWnd():hide()
   end
end

local function cbKeyDown(args)
   local keyArgs = CEGUI.toKeyEventArgs(args)
   if keyArgs.scancode == 41 then -- `(~)
      if not console:getWnd():isVisible() then
         console:getWnd():show()
         console:getWnd():getChild("Command"):activate()
         console.resetHistoryScrollID()
      else
         console:getWnd():hide()
      end
      return true
   elseif keyArgs.scancode == 1 and console:getWnd():isVisible() then -- escape
      console:getWnd():hide()
      return true
   end
   return false
end

local function initCreditsText(wnd)
   local text = stringio.create()
   text:write(string.rep("\n", 10))
   text:write("[image-size='w:626 h:380'][image='game_logo/LogoName']")
   text:write(string.rep("\n", 10))

   for i=1,#Backers do
      text:write(Backers[i].title .. "\n")

      for j=1,#Backers[i].list do
         text:write(Backers[i].list[j] .. "\n")
      end

      text:write(string.rep("\n", 3))
   end

   text:write(string.rep("\n", 100))

   wnd:setText(text:value())
end

function hasLogoPlayed()
   local pTable = pData.getPersistentTable()
   return pTable and pTable.hasLogoPlayed
end

function setLogoPlayed()
   pData.addToPersistentTable("hasLogoPlayed", true)
end

function dontShowLogos()
   local magic_file = io.open("skip_logos", 'r')
   if magic_file then
      io.close(magic_file)
      return true
   end
   return false
end

function OnInit()
   for _, stringTable in ipairs(require "strings") do
      i18n.load(stringTable)
   end
   i18n.setLocale("en")

   CEGUI.SchemeManager:getSingleton():createFromFile("TaharezLook.scheme")
   guiContext:setDefaultFont("venus rising rg-10")

   deb.initAfterCEGUI()
   
   wndMainMenu = wndMgr:loadLayoutFromFile("main_menu.layout")
   wndMainMenu:getChild("Version"):setProperty("Text", versionStr)
   GUIUtils.widgetSubscribeEventProtected(wndMainMenu, "KeyDown", cbMainMenuKeyDown)
   local logosWnd = wndMainMenu:getChild("StartLogos")

   wndLoadMenu = wndMgr:loadLayoutFromFile("save_load_menu.layout")
   wndLoadMenu:getChild("Version"):setProperty("Text", versionStr)
   GUIUtils.widgetSubscribeEventProtected(wndLoadMenu, "KeyDown", cbLoadMenuKeyDown)

   wndCredits = wndMgr:loadLayoutFromFile("credits.layout")
   wndCredits:getChild("Version"):setProperty("Text", versionStr)
   GUIUtils.widgetSubscribeEventProtected(wndCredits, "KeyDown", cbCreditsKeyDown)
   
   options:init()
   options.backMenu = wndMainMenu
   
   --+++++++++++++++++++++++++++++++++++++++++ Mod +++++++++++++++++++++++++++++++++++++++++++++   
   loadmodoptions:init()
   loadmodoptions.backMenu = wndMainMenu
   loadmodoptions:createmenubutton()
   --+++++++++++++++++++++++++++++++++++++++++ /Mod ++++++++++++++++++++++++++++++++++++++++++++

   console:init()
   wndMainMenu:addChild(console:getWnd())
   console:getWnd():hide()
   GUIUtils.widgetSubscribeEventProtected(console:getWnd():getChild("Command"), "KeyDown", console.cbConsoleCommandKeyDown)
   GUIUtils.widgetSubscribeEventProtected(console:getWnd():getChild("Command"), "KeyUp", console.cbConsoleCommandKeyUp)
   GUIUtils.widgetSubscribeEventProtected(console:getWnd():getChild("Command"), "TextAccepted", runConsoleCommand)
   GUIUtils.widgetSubscribeEventProtected(wndMainMenu, "KeyDown", cbKeyDown)

   guiContext:setRootWindow(wndMainMenu)
   guiContext:getMouseCursor():show()

   GUIUtils.widgetSubscribeEventProtected(wndMainMenu:getChild("NewGameButton"), "Clicked", newLevel)
   GUIUtils.widgetSubscribeEventProtected(wndMainMenu:getChild("ContinueButton"), "Clicked", loadLastGameState)
   GUIUtils.widgetSubscribeEventProtected(wndMainMenu:getChild("LoadGameButton"), "Clicked", loadMenu)
   GUIUtils.widgetSubscribeEventProtected(wndMainMenu:getChild("OptionsButton"), "Clicked", optionsMenu)
   GUIUtils.widgetSubscribeEventProtected(wndMainMenu:getChild("CreditsButton"), "Clicked", showCredits)
   GUIUtils.widgetSubscribeEventProtected(wndMainMenu:getChild("QuitButton"), "Clicked", quitGame)
   
   wndLoadMenu:getChild("SaveButton"):hide()
   wndLoadMenu:getChild("SaveName"):hide()
   wndLoadMenu:getChild("SaveNameBG"):hide()
   GUIUtils.widgetSubscribeEventProtected(wndLoadMenu:getChild("LoadButton"), "Clicked", loadGameState)
   GUIUtils.widgetSubscribeEventProtected(wndLoadMenu:getChild("DeleteButton"), "Clicked", deleteGameState)
   GUIUtils.widgetSubscribeEventProtected(wndLoadMenu:getChild("BackButton"), "Clicked", mainMain)
   
   --CREDITS
   GUIUtils.widgetSubscribeEventProtected(wndCredits:getChild("BackButton"), "Clicked", mainMain)

   local textWnd = wndCredits:getChild("BlackBack/Text")
   initCreditsText(textWnd)
   local scrollSize = textWnd:getProperty("VertExtent")

   local anim = CEGUI.AnimationManager:getSingleton():createAnimation("CreditsTesting")
   local scrollTime = 450
   anim:setDuration(scrollTime)
   anim:setReplayMode(CEGUI.Animation.RM_Loop)

   local affector = anim:createAffector("VertScrollPosition", "float")
   affector:createKeyFrame(0, "0.0")
   affector:createKeyFrame(1, "0.0")
   affector:createKeyFrame(scrollTime, tostring(scrollSize), CEGUI.KeyFrame.P_Linear)

   initSavegames()
   GUIUtils.widgetSubscribeEventProtected(wndLoadMenu:getChild("Savegames"), "MouseDoubleClick", loadGameState)

   trackPlay("menu.ogg", 0)
   wndMainMenu:activate()

   local function setMouseCursorImage()
      guiContext:getMouseCursor():setDefaultImage("TaharezLook/MouseArrow")
   end

   GUIUtils.translateAllWindowsText()

   --LOGOS
   if hasLogoPlayed() or dontShowLogos() then
      setMouseCursorImage()
      return
   end
   setLogoPlayed()

   logosWnd:setVisible(true)

   CEGUI.AnimationManager:getSingleton():loadAnimationsFromXML("logos.xml")

   earlyAccessAnim = CEGUI.AnimationManager:getSingleton():instantiateAnimation("EarlyAccessLabel")
   earlyAccessAnim:setTargetWindow(logosWnd:getChild("Image/EarlyAccessLabel"))
   earlyAccessAnim:start()

   logoChangeAnim = CEGUI.AnimationManager:getSingleton():instantiateAnimation("LogoChange")
   logoChangeAnim:setTargetWindow(logosWnd:getChild("Image"))
   logoChangeAnim:start()

   local function onLogoChangeEnd(args)
      local fadeOutAnim = CEGUI.AnimationManager:getSingleton():instantiateAnimation("LogoFadeOut")
      fadeOutAnim:setTargetWindow(logosWnd)
      fadeOutAnim:start()
      resetCursorPos()
      setMouseCursorImage()
   end
   GUIUtils.widgetSubscribeEventProtected(logosWnd:getChild("Image"), "AnimationEnded", onLogoChangeEnd)
   local function onLogoFadeEnd(args)
      CEGUI.System:getSingleton():getRenderer():destroyTexture("logo_publisher")
      CEGUI.System:getSingleton():getRenderer():destroyTexture("logo_developer")
      CEGUI.System:getSingleton():getRenderer():destroyTexture("logo_early_access")
   end

   GUIUtils.widgetSubscribeEventProtected(logosWnd, "AnimationEnded", onLogoFadeEnd)
   GUIUtils.widgetSubscribeEventProtected(logosWnd, "MouseClick", trySkipLogos)
end

function initSavegames()
   SavegamesListBox = CEGUI.toListbox(wndLoadMenu:getChild("Savegames"))
   initSavegamesList(SavegamesListBox)

   wndMainMenu:getChild("ContinueButton"):setProperty("Disabled", tostring(#gSavegames == 0))
end

function mainMain(args)
   guiContext:setRootWindow(wndMainMenu)
end

function loadMenu(args)
   initSavegames()
   guiContext:setRootWindow(wndLoadMenu)
   wndLoadMenu:moveToFront()
end

function optionsMenu(args)
   options:updateOptions()
   guiContext:setRootWindow(options.wnd)
   options.wnd:moveToFront()
end

function showCredits(args)
   local textWnd = wndCredits:getChild("BlackBack/Text")

   local animInstance = CEGUI.AnimationManager:getSingleton():instantiateAnimation("CreditsTesting")
   animInstance:setTargetWindow(textWnd)

   guiContext:setRootWindow(wndCredits)
   wndCredits:moveToFront()
   animInstance:start()
end

function newLevel(args)
   addToPersistentTable("isLoadedGame", false)
   commitPersistentTable()
   trackPlay("loadingscreen_1.ogg", 0)
   changeLocation("\\levels\\WindscreamCanyon\\Windscream_Canyon.swz")
end

function loadGameState(args)
   local item = SavegamesListBox:getFirstSelectedItem()
   if item then
      loadSaveVersionCheck(item:getID())
   end
end

function deleteGameState(args)
   local item = SavegamesListBox:getFirstSelectedItem()

   if item ~= nil then
      confirmMessage(wndLoadMenu, function()
         deleteGame(gSavegames[item:getID()].name)
         initSavegames()
      end)
   end
end

function loadLastGameState(args)
   loadSaveVersionCheck(getLastSaveID())
end

function quitGame(args)
   confirmMessage(wndMainMenu, function() exitGame() end)
end

function OnUpdate(timeDelta)
end

function cbMainMenuKeyDown(args)
   local keyArgs = CEGUI.toKeyEventArgs(args)
   local virtualKeyCode = scanCodeToVirtualKey(keyArgs.scancode, false)

   if trySkipLogos() then return end

   if virtualKeyCode == getButtonCode("ESCAPE") then
      if GUIUtils.tryDestroyDynamicWindows() then return end

      if not console:getWnd():isVisible() then
         quitGame(args)
      end
   end
end

function cbLoadMenuKeyDown(args)
   local keyArgs = CEGUI.toKeyEventArgs(args)
   local virtualKeyCode = scanCodeToVirtualKey(keyArgs.scancode, false)
   if virtualKeyCode == getButtonCode("ESCAPE") then
      if GUIUtils.tryDestroyDynamicWindows() then return end

      if not console:getWnd():isVisible() then
         mainMain(args)
      end
   end
end

function cbCreditsKeyDown(args)
   local keyArgs = CEGUI.toKeyEventArgs(args)
   local virtualKeyCode = scanCodeToVirtualKey(keyArgs.scancode, false)
   if virtualKeyCode == getButtonCode("ESCAPE") then
      mainMain(args)
   end
end

function trySkipLogos()
   if logoChangeAnim then
      if logoChangeAnim:getPosition() < 3.5 then
         logoChangeAnim:setPosition(3.5)
         earlyAccessAnim:setPosition(3.5)
         return true
      elseif logoChangeAnim:getPosition() < 6.5 then
         logoChangeAnim:setPosition(6.5)
         earlyAccessAnim:setPosition(6.5)
         return true
      elseif logoChangeAnim:getPosition() < 22.5 then
         logoChangeAnim:setPosition(22.5)
         earlyAccessAnim:setPosition(22.5)
         return true
      end
   end
end

OnInit()
