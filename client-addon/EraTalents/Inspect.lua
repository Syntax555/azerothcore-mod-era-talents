-- Era talents in the stock Inspect frame. When the inspected character's talent set is
-- era-managed (server says so in ISYNC), a tree view is overlaid on InspectTalentFrame and
-- the stock WotLK tree is suppressed; otherwise the stock view is left completely alone.
-- IEDIT permits manual learning only for server-authorized controlled group altbots.
--
-- Trigger: post-hooks on InspectFrame_Show / InspectFrame_UnitChanged -- the stock paths that point
-- the Inspect FRAME at a unit. NOT INSPECT_TALENT_READY: other addons' background NotifyInspect
-- (Grid2's LibTalentQuery inspects party members) fire it too and would spam INSPECT requests.
EraTalents = EraTalents or {}
local ET = EraTalents
local L = ET.L

-- Stock children the overlay replaces. The scroll frame (talent buttons + branches) and points bar
-- are never re-shown by Blizzard code, so Hide/Show is safe (OnShow guard below as a backstop). The
-- three tabs ARE re-Show()n by InspectTalentFrame_UpdateTabs on every update, so they are suppressed
-- with alpha + mouse instead (same reasoning as Hook.lua's pet-only spec tabs).
local STOCK_HIDE = { "InspectTalentFrameScrollFrame", "InspectTalentFramePointsBar" }
local STOCK_TABS = { "InspectTalentFrameTab1", "InspectTalentFrameTab2", "InspectTalentFrameTab3" }

local suppressed = false   -- stock children are only ever touched while this is true (and once to restore)

local function SetStockSuppressed(on)
  if on == suppressed then return end
  suppressed = on
  for _, n in ipairs(STOCK_HIDE) do
    local fr = _G[n]
    if fr then if on then fr:Hide() else fr:Show() end end
  end
  for _, n in ipairs(STOCK_TABS) do
    local t = _G[n]
    if t then t:SetAlpha(on and 0 or 1); t:EnableMouse(not on) end
  end
end

local function EnsureView()
  if not ET.inspectView then
    ET.inspectView = ET.NewTreeView({ name = "EraInspectTalentFrame", parent = InspectTalentFrame,
                                      chrome = false, tabStyle = "top", readOnly = true, defaultTab = 1 })
  end
  return ET.inspectView
end

-- Do not show native WotLK talents while an authoritative historical reply is
-- pending or its client data is unavailable. The stock frame remains the inspect
-- host; editing requires fresh server permission for the selected character.
local function ShowStatus(message)
  if ET.inspectView then ET.inspectView.frame:Hide() end
  if not ET.inspectStatus then
    ET.inspectStatus = InspectTalentFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    ET.inspectStatus:SetPoint("CENTER", InspectTalentFrame, "CENTER", 0, 0)
    ET.inspectStatus:SetWidth(260)
  end
  ET.inspectStatus:SetText(message)
  ET.inspectStatus:Show()
end

-- A server running EraTalents answers every HELLO with GEN. Without one inside this window
-- the realm uses native trees, so bot inspection keeps MultiBot's and the stock views.
local SERVER_REPLY_SECONDS = 5
function ET.ServesBotInspect()
  return ET.state.serverGen ~= nil or not ET.helloSentAt or GetTime() - ET.helloSentAt <= SERVER_REPLY_SECONDS
end

function ET.RefreshInspect()
  if not InspectTalentFrame then return end
  local guid = ET.inspect.current
  local e = guid and ET.inspect.cache[guid]
  local shown = guid and InspectTalentFrame:IsShown()
  local waiting = shown and not e and (ET.state.serverGen or (ET.inspect.botTarget == guid and ET.ServesBotInspect()))
  local historical = shown and e and e.managed
  if waiting or historical then
    SetStockSuppressed(true)
    if waiting or e.partial then
      ShowStatus(L["Loading talent data..."])
      return
    end
    if not ET.state.serverGen then
      ShowStatus(L["Waiting for server talent data..."])
      return
    end
    if ET.state.clientGen ~= ET.state.serverGen then
      ShowStatus(L["Install the matching EraTalents client patch and restart the game."])
      return
    end
    local byClass = EraTalentsData and EraTalentsData[e.era]
    local tree = byClass and byClass[e.classId]
    local valid = tree ~= nil
    local nodeRanks = {}
    if tree then
      for _, node in ipairs(tree.talents) do nodeRanks[node.id] = node.maxRank end
      for id, rank in pairs(e.ranks) do
        if not nodeRanks[id] or rank > nodeRanks[id] then valid = false; break end
      end
    end
    if not valid then
      ShowStatus(L["Install the matching EraTalents addon and reload the interface."])
      return
    end
    if ET.inspectStatus then ET.inspectStatus:Hide() end
    local v = EnsureView()
    if v.guid ~= guid then
      v.guid = guid
      v.activeTab = ET.PrimaryTab(tree, e.ranks, 1)
    end
    v.readOnly = not e.editable
    v.frame:Show()
    ET.RenderView(v, { era = e.era, ranks = e.ranks, availPts = e.availPts or 0 }, e.classId)
  else
    if ET.inspectView then ET.inspectView.frame:Hide() end
    if ET.inspectStatus then ET.inspectStatus:Hide() end
    SetStockSuppressed(false)
  end
end

-- Used by MultiBot's talent button. Stock InspectUnit retains its native unit,
-- distance and faction checks; ISYNC identifies the inspected character by GUID.
function ET.OpenBotInspect(unit, toggle)
  if not ET.ServesBotInspect() then return false end
  if not unit or not UnitExists(unit) or not CanInspect(unit) then return false end
  local guid = UnitGUID(unit)
  if not guid then return false end
  if InspectFrame and InspectFrame:IsShown() and InspectFrame.unit and UnitGUID(InspectFrame.unit) == guid
     and InspectTalentFrame and InspectTalentFrame:IsShown() then
    if toggle then HideUIPanel(InspectFrame) end
    return true
  end
  InspectUnit(unit)
  if not (InspectFrame and InspectFrame:IsShown() and InspectFrame.unit and UnitGUID(InspectFrame.unit) == guid) then return false end
  -- InspectUnit opens equipment; the native talent tab is disabled below level 10.
  local level = UnitLevel(unit)
  if level <= 0 or level >= 10 then InspectSwitchTabs(3) end
  ET.inspect.botTarget = guid
  ET.RefreshInspect()
  return true
end

local function OnInspectTarget()
  if not (InspectFrame and InspectFrame:IsShown()) then return end   -- CanInspect refused: no frame
  local unit = InspectFrame.unit
  local guid = unit and UnitGUID(unit)
  ET.inspect.current = guid
  if guid and not ET.inspect.cache[guid] then ET.RequestInspect(guid) end
  ET.RefreshInspect()
end

local function AttachInspect()
  if ET._inspectHooked or not InspectFrame or not InspectTalentFrame then return end
  ET._inspectHooked = true
  hooksecurefunc("InspectFrame_Show", OnInspectTarget)
  hooksecurefunc("InspectFrame_UnitChanged", OnInspectTarget)
  -- InspectFrame_Show hides the frame before re-showing it, so every fresh inspect re-requests.
  InspectFrame:HookScript("OnHide", function()
    ET.inspect.current = nil
    ET.inspect.botTarget = nil
    wipe(ET.inspect.cache)
    if ET.inspectView then
      ET.inspectView.guid = nil   -- reopening = a fresh inspect: primary tree again
      ET.inspectView.readOnly = true
    end
    ET.RefreshInspect()
  end)
  InspectTalentFrame:HookScript("OnShow", function() ET.RefreshInspect() end)
  InspectTalentFrame:HookScript("OnHide", function() ET.RefreshInspect() end)
  for _, n in ipairs(STOCK_HIDE) do
    local fr = _G[n]
    if fr then fr:HookScript("OnShow", function(self) if suppressed then self:Hide() end end) end
  end
end

function ET.InitInspect()
  if ET._inspectInit then return end
  ET._inspectInit = true
  -- Blizzard_InspectUI is load-on-demand (InspectUnit -> UIParentLoadAddOn): attach now if it is
  -- already loaded, else when it loads.
  if IsAddOnLoaded("Blizzard_InspectUI") then AttachInspect() end
  local w = CreateFrame("Frame")
  w:RegisterEvent("ADDON_LOADED")
  w:SetScript("OnEvent", function(_, _, name)
    if name == "Blizzard_InspectUI" then AttachInspect() end
  end)
end
