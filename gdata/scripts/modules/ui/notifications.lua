local oo = require "loop.simple"

local f = require "fun"
local partial = f.partial
--+++++++++++++++++++++++++++++++++++++++++ Mod +++++++++++++++++++++++++++++++++++++++++++++
local CritPartialMod  = require "mods.partialcritmod"
local random = require "random"
--+++++++++++++++++++++++++++++++++++++++++ /Mod ++++++++++++++++++++++++++++++++++++++++++++
local GUIUtils = require "ui.utils"

local wndMgr
-- ......................
-- added hit here too   .
-- ......................
local TOTAL_WINDOWS = {minor = 4, major = 4, hit = 5}
local SYNC_UPON_COUNT = {minor = 3, major = 3, hit = 2}
local SHOW_TIME = {minor = 3, major = 3, hit = 1}

local NOTIFICATION_SPACING = 5
local notificationHeight

---@class CNotificationsUI
local CNotificationsUI = oo.class({})

--Methods
function CNotificationsUI:init()
   wndMgr = CEGUI.WindowManager:getSingleton()
   self.minor = {wnds = {free = {}, occupied = {}}, taskList = {}}
   self.major = {wnds = {free = {}, occupied = {}}, taskList = {}}
   self.hit   = {wnds = {free = {}, occupied = {}}, taskList = {}}
   CEGUI.AnimationManager:getSingleton():loadAnimationsFromXML("notifications.xml")

   for i=1,TOTAL_WINDOWS.minor do
      local wnd = wndMgr:loadLayoutFromFile("gameplay/notifications.layout")
      wnd:setName("MinorNotification" .. i)
      wnd:setVisible(false)
      gameplayUI.wndGameplay:addChild(wnd)
      local NotificationShow = CEGUI.AnimationManager:getSingleton():instantiateAnimation("NotificationShow")
      NotificationShow:setTargetWindow(wnd)
      local NotificationHide = CEGUI.AnimationManager:getSingleton():instantiateAnimation("NotificationHide")
      NotificationHide:setTargetWindow(wnd)
      local NotificationSlide = CEGUI.AnimationManager:getSingleton():instantiateAnimation("NotificationSlide")
      NotificationSlide:setTargetWindow(wnd)

      local wndTable = {wnd = wnd, NotificationShow = NotificationShow, NotificationHide = NotificationHide, NotificationSlide = NotificationSlide, hideTimer = nil}
      table.insert(self.minor.wnds.free, wndTable)
      GUIUtils.widgetSubscribeEventProtected(wnd, "AnimationStopped", function(args)
         self:onAnimationEnd(wndTable, "minor", args)
      end)
   end
    -- .......................
    -- added this for loop   .
    -- .......................
    for i=1,TOTAL_WINDOWS.hit do
        local wnd = wndMgr:loadLayoutFromFile("gameplay/grumblenoti.layout")
        wnd:setName("HitNotification" .. i)
        wnd:setVisible(false)
        wnd:setProperty("HorizontalAlignment", "Centre")
        gameplayUI.wndGameplay:addChild(wnd)
        local NotificationShow = CEGUI.AnimationManager:getSingleton():instantiateAnimation("NotificationShow")
        NotificationShow:setTargetWindow(wnd)
        local NotificationHide = CEGUI.AnimationManager:getSingleton():instantiateAnimation("NotificationHide")
        NotificationHide:setTargetWindow(wnd)
        local NotificationSlide = CEGUI.AnimationManager:getSingleton():instantiateAnimation("NotificationSlide")
        NotificationSlide:setTargetWindow(wnd)

        local wndTable = {wnd = wnd, NotificationShow = NotificationShow, NotificationHide = NotificationHide, NotificationSlide = NotificationSlide, hideTimer = nil}
        table.insert(self.hit.wnds.free, wndTable)
        GUIUtils.widgetSubscribeEventProtected(wnd, "AnimationStopped", function(args)
            self:onAnimationEnd(wndTable, "hit", args)
        end)
    end
   for i=1,TOTAL_WINDOWS.major do
      local wnd = wndMgr:loadLayoutFromFile("gameplay/notifications.layout")
      wnd:setName("MajorNotification" .. i)
      wnd:setVisible(false)
      wnd:setProperty("HorizontalAlignment", "Centre")
      gameplayUI.wndGameplay:addChild(wnd)
      local NotificationShow = CEGUI.AnimationManager:getSingleton():instantiateAnimation("NotificationShow")
      NotificationShow:setTargetWindow(wnd)
      local NotificationHide = CEGUI.AnimationManager:getSingleton():instantiateAnimation("NotificationHide")
      NotificationHide:setTargetWindow(wnd)
      local NotificationSlide = CEGUI.AnimationManager:getSingleton():instantiateAnimation("NotificationSlide")
      NotificationSlide:setTargetWindow(wnd)

      local wndTable = {wnd = wnd, NotificationShow = NotificationShow, NotificationHide = NotificationHide, NotificationSlide = NotificationSlide, hideTimer = nil}
      table.insert(self.major.wnds.free, wndTable)
      GUIUtils.widgetSubscribeEventProtected(wnd, "AnimationStopped", function(args)
         self:onAnimationEnd(wndTable, "major", args)
      end)
   end
end

function CNotificationsUI:getFreeWindow(importance)
   return self[importance].wnds.free[1]
end

function CNotificationsUI:getNextTask(importance)
   return self[importance].taskList[1]
end

function CNotificationsUI:addInfoTask(task, importance)
   table.insert(self[importance].taskList, task)
   self:showInfo(importance)
end

function CNotificationsUI:showInfo(importance)
   local info = self[importance]
   local task = self:getNextTask(importance)
   local wndTable = self:getFreeWindow(importance)
   if not wndTable or not task then return end

   if task.sound ~= "" then
      getPlayer():playSound(task.sound)
   end

   local wnd = wndTable.wnd
   local textWnd = wnd:getChild("InfoText")

   wnd:setWidth(wnd:getMaxSize().width)
   textWnd:setText(task.text)
   GUIUtils.adjustWindowWidthForTextChildren(wnd, getScreenSize().y * 0.02, textWnd)
   GUIUtils.adjustWindowHeightForTextChildren(wnd, getScreenSize().y * 0.01, textWnd)
   notificationHeight = wnd:getPixelSize().height

   table.remove(info.taskList, 1)
   table.remove(info.wnds.free, 1)
   table.insert(info.wnds.occupied, wndTable)
   local id = #info.wnds.occupied - 1
   wnd:setID(id)
   if importance == "minor" then
      wnd:setYPosition(CEGUI.UDim(0.7, id * (notificationHeight + NOTIFICATION_SPACING)))
   elseif importance == "major" then
      wnd:setYPosition(CEGUI.UDim(0.15, id * (notificationHeight + NOTIFICATION_SPACING)))
   elseif importance == "hit" then
       local p = CritPartialMod.impactPos
       p.y = 1 - p.y
       local x, y = p.x, p.y
       x = math.min(math.max(0.02, x), 0.98)
       y = math.min(math.max(0.01, y), 0.97)
       wnd:setPosition(CEGUI.UVector2(CEGUI.UDim(x - 0.5, 0), CEGUI.UDim(y, id * (notificationHeight + 1))))
   end

   wndTable.NotificationShow:start()

   --Reschedule hide of the notifications upon reaching a specific count
   if #info.wnds.occupied >= SYNC_UPON_COUNT[importance] then
      for _,wndT in ipairs(info.wnds.occupied) do
         if not wndT.NotificationHide:isRunning() then
            if wndT.hideTimer then
               wndT.hideTimer:stop()
            end
            wndT.hideTimer = runTimer(SHOW_TIME[importance], nil, function()
               wndT.NotificationHide:start()
            end, false)
         end
      end
      return
   else
      wndTable.hideTimer = runTimer(SHOW_TIME[importance], nil, function()
         wndTable.hideTimer = nil
         wndTable.NotificationHide:start()
      end, false)
   end
end

function CNotificationsUI:onAnimationEnd(wndTable, importance, args)
   local anim_args = args:toAnimationEventArgs()
   local instance = anim_args.instance
   local animName = instance:getDefinition():getName()

   if animName == "NotificationHide" then --Escape any possibility to be included in slideWindows
      table.remove(self[importance].wnds.occupied, 1)
   end

   runTimer(0, nil, function() --Delay everything cause event comes before the actual animation end
      if animName == "NotificationHide" then
         table.insert(self[importance].wnds.free, wndTable)
         self:slideWindows(importance)
      elseif not wndTable.NotificationHide:isRunning() then
         if wndTable.wnd:getYPosition().offset > (wndTable.wnd:getID() * (notificationHeight + NOTIFICATION_SPACING)) then
            wndTable.NotificationSlide:start()
         end
      end
      if animName == "NotificationShow" or animName == "NotificationHide" then --Initiate previously ignored one or simply next one
         self:showInfo(importance)
      end
   end,false)
end

function CNotificationsUI:slideWindows(importance)
   local id = 0
   for _,wndTable in ipairs(self[importance].wnds.occupied) do
      wndTable.wnd:setID(id)
      if not wndTable.NotificationHide:isRunning() and not wndTable.NotificationShow:isRunning() and not wndTable.NotificationSlide:isRunning() then
         wndTable.NotificationSlide:start()
      end
      id = id + 1
   end
end

return CNotificationsUI
