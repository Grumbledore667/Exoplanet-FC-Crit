
--local guiContext = CEGUI.System:getSingleton():getDefaultGUIContext()
local GUIUtils = require "ui.utils"
local persistence = require "persistence"
local stringx = require "pl.stringx"
local modoptions =
{
   backMenu = nil,
   wnd = nil,
   saveButton = nil,
   fonts = {},
   loadedoptions = {},
   scrollarea = nil,
}

function modoptions:init()
   local wndMgr = CEGUI.WindowManager:getSingleton()
   self.wnd = wndMgr:loadLayoutFromFile("modoptions.layout")
   self.wnd:getChild("Version"):setProperty("Text", versionStr)
   self.scrollarea = self.wnd:getChild("BlackBack/ScrollablePane")
   GUIUtils.widgetSubscribeEventProtected(self.wnd:getChild("BackButton"), "Clicked", mainMainModOptions)
   self.saveButton = self.wnd:getChild("SaveButton")
   self.saveButton:setProperty("Disabled", "true")
   GUIUtils.widgetSubscribeEventProtected(self.saveButton, "Clicked", saveModOptionsConfig)
end

function modoptions:getWnd()
   return modoptions.wnd
end

function modoptions:retrieveValue(filename, label)
 local values = persistence.load( "./modoptions/" ..  filename)
 for i, value in ipairs(values.options) do
  
  if value.label == label then
   return value.defaultvalue
  end
 end 
  
end




function saveModOptionsConfig(args)
   for i=1,#modoptions.loadedoptions do
	persistence.store("./modoptions/" ..  modoptions.loadedoptions[i].filename, modoptions.loadedoptions[i][1])
   end
   modoptions.saveButton:setProperty("Disabled", "true")
end

function mainMainModOptions(args)
   local wndMgr = CEGUI.WindowManager:getSingleton()
   local guiContext = CEGUI.System:getSingleton():getDefaultGUIContext()
   local mod_options = getFolderElements("\\modoptions\\*.lua", false, true)
   for i=1,#mod_options do
    local f, err = loadfile( "./modoptions/" ..  mod_options[i])
    if err then
      log(string.format("ERROR: Can't load option file %s:", name))
      log(err)
      return
    end
    local modoption = f()
   wndMgr:destroyWindow(scrollarea:getChild(mod_options[i] ..":".. i))  
   for j, addoption in ipairs(modoption.options) do
    wndMgr:destroyWindow(scrollarea:getChild(modoption.name..":".. j)) 
   end
  end
  guiContext:setRootWindow(wndMainMenu)
end

function modoptions:getWnd()
   return modoptions.wnd
end

function modoptions:createmenubutton()
	local button = wndMainMenu:createChild("TaharezLook/Button", "ModOptions")
	button:setProperty("Area", "{{0,0},{0.792,109},{0.326,0},{0.829,109}}")
	button:setProperty("Font", "decor-14")
	button:setText("Mod Options")
	button:setProperty("MinSize", "{{0,450},{0,0}}")
	button:setProperty("HoverImage", "game_logo/Button2")           
	button:setProperty("NormalImage", "game_logo/Button2")
	button:setProperty("PushedImage", "game_logo/Button2")
	button:setProperty("DisabledImage", "game_logo/Button1")
	button:setProperty("HoverTextColour", "tl:FFFF0000 tr:FFFF0000 bl:FFFF0000 br:FFFF0000")            
	button:setProperty("TranslationPath", "menu.buttons.modoptions")
	button:setProperty("DrawStandardImagery", "False")           
	GUIUtils.widgetSubscribeEventProtected(wndMainMenu:getChild("ModOptions"), "Clicked", ModoptionsMenu)
end

function ModoptionsMenu(args)
local guiContext = CEGUI.System:getSingleton():getDefaultGUIContext()
   local headerspacing = 0 
   local optionspacing = 50
   local optionscount = 0
   scrollarea = modoptions.wnd:getChild("BlackBack/ScrollablePane")
   local mod_options = getFolderElements("\\modoptions\\*.lua", false, true)
   for i=1,#mod_options do
    
	headerspacing = 140*(i-1)
    modoptions.loadedoptions[i] = {filename = mod_options[i], persistence.load( "./modoptions/" ..  mod_options[i])}
	local labelheader = scrollarea:createChild("TaharezLook/StaticText", modoptions.loadedoptions[i].filename ..":".. i)
	     labelheader:setProperty("Area", "{{0,0},{0,0},{1,0},{0.05,0}}")
         labelheader:setProperty("FrameEnabled", "false")
		 labelheader:setProperty("FrameColours", "A000000")
         labelheader:setProperty("Font", "decor-10")
         labelheader:setProperty("MouseInputPropagationEnabled", "false")
		 labelheader:setProperty("BackgroundEnabled", "false")
		 labelheader:setProperty("TextColours", "FFFFFFFF")
         labelheader:setText(string.format(" %s ", modoptions.loadedoptions[i][1].name))
         local pos = CEGUI.UVector2(CEGUI.UDim(0,0), CEGUI.UDim(0,headerspacing+(optionspacing*optionscount)))
         labelheader:setPosition(pos)
		 
	for j, addoption in ipairs(modoptions.loadedoptions[i][1].options) do
	     local label = scrollarea:createChild("TaharezLook/StaticText", modoptions.loadedoptions[i][1].name..":".. j)
         label:setProperty("Area", "{{0,0},{0,0},{1,0},{0.05,0}}")
         label:setProperty("FrameEnabled", "false")
		 label:setProperty("BackgroundEnabled", "false")
         label:setProperty("Font", "dialog-12")
         label:setProperty("MouseInputPropagationEnabled", "false")
         label:setProperty("TextColours", "FFFFFFFF")
         label:setText(string.format(" %s ", addoption.label))
         local labelpos = CEGUI.UVector2(CEGUI.UDim(0,0), CEGUI.UDim(0,headerspacing+(optionspacing*optionscount)+50))
         label:setPosition(labelpos)
	 	 if addoption.element == "checkbox" then
		  checkboxtemplate(label, modoptions.loadedoptions[i][1].name, addoption.element, addoption.defaultvalue, j, 800, i)
		 elseif addoption.element == "radio" then
		  radiobuttontemplate(label, modoptions.loadedoptions[i][1].name, addoption.element, addoption.defaultvalue, j, 800, addoption.descriptions, addoption.groupid, i)
         elseif addoption.element == "combobox" then		 
		  comboboxtemplate(label, modoptions.loadedoptions[i][1].name, addoption.element, addoption.defaultvalue, j, 800, addoption.descriptions, i)
		 end
	     optionscount = optionscount + 1
	end
	
   end
   guiContext:setRootWindow(modoptions.wnd)
   modoptions.wnd:moveToFront()
end

function checkboxtemplate(label, name, element, defaultvalue, count, position, index)
	local checkbox = label:createChild("TaharezLook/Checkbox", name..":"..count ..":".. index)
	      checkbox:setProperty("Area", "{{0.9,0},{0,0},{1,0},{1,0}}")
		  checkbox:setProperty("MouseInputPropagationEnabled", "true")
		  checkbox:setProperty("Selected", tostring(defaultvalue))
		  local checkboxpos = CEGUI.UVector2(CEGUI.UDim(0,position), CEGUI.UDim(0,0))
          checkbox:setPosition(checkboxpos)
	      GUIUtils.widgetSubscribeEventProtected(checkbox, "MouseClick", checkboxstate)
end

function comboboxtemplate(label, name, element, defaultvalue, count, position, descriptions, index)
	local ListItemColour = CEGUI.Colour:new_local(1.0,1.0,1.0,1.0)
    local ListItemSelectedColour = CEGUI.Colour:new_local(1.0,1.0,1.0,0.8)
	local combobox = label:createChild("TaharezLook/Combobox", name..":"..count ..":".. index)
	      combobox:setProperty("Area", "{{0.9,0},{0,0},{1,0},{1,0}}")
		  combobox:setProperty("MouseInputPropagationEnabled", "false")
		  combobox:setProperty("Font", "dialog-12")
		  combobox:setProperty("ReadOnly", "true")
		  combobox:setProperty("AutoSizeListHeight", "true")
		  combobox:setProperty("AlwaysOnTop", "true")
		  combobox:setProperty("ClippedByParent", "false")
		  combobox:setHeight(CEGUI.UDim(0.0,1000))
		  local comboboxpos = CEGUI.UVector2(CEGUI.UDim(0,position), CEGUI.UDim(0,0))
	      combobox:setPosition(comboboxpos)
	      combobox = CEGUI.toCombobox(combobox)
		  combobox:resetList()
		  for i, description in ipairs(descriptions) do
            if defaultvalue == description then
			 combobox:setText(defaultvalue)
			end
		    local item = CEGUI.createListboxTextItem(description)
		    item:setTextColours(ListItemColour)
            item:setSelectionColours(ListItemSelectedColour)
            item:setSelectionBrushImage("TaharezLook/TextSelectionBrush")
		    item:setFont("dialog-12")
		    item:setID(i)
		    combobox:addItem(item)
          end		
		  GUIUtils.widgetSubscribeEventProtected(combobox, "ListSelectionAccepted", comboboxstate)
end

function radiobuttontemplate(label, name, element, defaultvalue, count, position, descriptions, groupid, index)
	local counting = 1
	for i, description in ipairs(descriptions) do
	 local radio = label:createChild("TaharezLook/RadioButton", name..":"..count.. ":" .. description .. ":" .. index)
	 radio:setProperty("MouseInputPropagationEnabled", "true")
	 if defaultvalue == description then
	  radio:setProperty("Selected", "true")
	 else
	  radio:setProperty("Selected", "false")
	 end
	 radio:setProperty("GroupID", tostring(groupid))
	 radio:setProperty("ID", tostring(groupid+counting))
	 radio:setProperty("Font", "dialog-10")
     radio:setProperty("MousePassThroughEnabled", "false")
     radio:setText(string.format(" %s ", description))
	 local font  = radio:getFont()
     local width = font:getTextExtent( radio:getText() ) * 1.5
     radio:setWidth( CEGUI.UDim(0.0,width) )
     local radiopos = CEGUI.UVector2(CEGUI.UDim(0,position+(100*(counting-1))), CEGUI.UDim(0,0))
	 radio:setPosition(radiopos)
	 counting = counting + 1
	 GUIUtils.widgetSubscribeEventProtected(radio, "MouseClick", radiostate)
	end
end

function checkboxstate(args)
local click_args = CEGUI.toMouseEventArgs(args)
   if click_args.button == CEGUI.LeftButton then
	  local className = click_args.window:getName()
	  local parenttemp = click_args.window:getParent():getName()
	  local state = click_args.window:getProperty("Selected") == "true"
	  modoptions.loadedoptions[tonumber(stringx.split(className, ":")[3])][1].options[tonumber(stringx.split(className, ":")[2])].defaultvalue = state
	  modoptions.wnd:getChild("BlackBack/ScrollablePane/".. parenttemp.. "/" .. className):setProperty("Selected", tostring(state))
	  modoptions.saveButton:setProperty("Disabled", "false")
   end
end

function radiostate(args)
local click_args = CEGUI.toMouseEventArgs(args)
   if click_args.button == CEGUI.LeftButton then
      local className = click_args.window:getName()
	  local labelname = stringx.split(className, ":")[1]..":"..stringx.split(className, ":")[2]
	  local elementname = labelname ..":"..stringx.split(className, ":")[3] .. ":" .. stringx.split(className, ":")[4]
	  local state = click_args.window:getProperty("Selected") == "true"
	  modoptions.loadedoptions[tonumber(stringx.split(className, ":")[4])][1].options[tonumber(stringx.split(className, ":")[2])].defaultvalue = stringx.split(className, ":")[3]
	  modoptions.wnd:getChild("BlackBack/ScrollablePane/".. labelname.. "/" .. elementname):setProperty("Selected", tostring(state))
	  modoptions.saveButton:setProperty("Disabled", "false")
   end
end

function comboboxstate(args)
 local click_args = CEGUI.toMouseEventArgs(args)
 local className = click_args.window:getName()
 modoptions.loadedoptions[tonumber(stringx.split(className, ":")[3])][1].options[tonumber(stringx.split(className, ":")[2])].defaultvalue = click_args.window:getText()
 modoptions.saveButton:setProperty("Disabled", "false")
end

return modoptions






