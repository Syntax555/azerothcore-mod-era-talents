-- Feed historical talent data into DragonUI's existing window and tree renderer.
EraTalents = EraTalents or {}
local ET = EraTalents
local L = ET.L

local function DragonTalents()
  local dragon = _G.DragonUI
  local module = type(dragon) == "table" and dragon.TalentModule
  local ns = type(module) == "table" and module.ns
  if type(ns) ~= "table" or type(ns.ExternalTalentView) ~= "function" then return nil end
  return module, ns
end

local function InspectMatches(unit, guid)
  return guid and ET.inspect.current == guid and InspectFrame and InspectFrame:IsShown()
      and InspectFrame.unit and UnitGUID(InspectFrame.unit) == guid and UnitGUID(unit) == guid
end

local function Describe(ns, own)
  local unit = not own and ns.inspectUnit or nil
  local state, classId, guid = ET.state, ET._classId
  if unit then
    guid = UnitGUID(unit)
    state = guid and ET.inspect.cache[guid]
    if state and not state.managed then return nil end
    if not state and not (ET.state.serverGen or (ET.inspect.botTarget == guid and ET.ServesBotInspect())) then
      return nil
    end
    classId = state and state.classId
  elseif not state.isEraChar then
    return nil
  end

  local tree, status, byId = ET.TalentData(state, classId)
  if unit and not InspectMatches(unit, guid) then tree, status = nil, L["Loading talent data..."] end
  local view = {
    count = 0, trees = {}, guid = guid, era = state and state.era, classId = classId,
    depth = state and state.era == 0 and 7 or 9,
    classToken = tree and tree.className or select(2, UnitClass(unit or "player")),
    title = unit and (GetUnitName(unit, true) or UnitName(unit) or "") or TALENTS,
    available = state and state.availPts or 0, status = status,
    state = state, byId = byId, readOnly = unit ~= nil and not (state and state.editable),
  }
  if not tree then return view end
  view.count, view.depth = 3, 1
  local spent = ET.SpecPoints(tree, state.ranks)
  for tab = 1, 3 do
    view.trees[tab] = { name = ET.TabName(tree.tabs[tab]), points = spent[tab], talents = {} }
  end
  for _, node in ipairs(tree.talents) do
    local rank = state.ranks[node.id] or 0
    local reachable = ET.IsReachable(node, spent[node.tab], state.ranks, byId)
    local color = rank >= node.maxRank and "yellow" or reachable and "green" or "locked"
    if reachable and (view.available < 1 or view.readOnly) then color = rank > 0 and "yellow" or "gray" end
    local links, pre = {}, byId[node.prereqTalent]
    if pre then
      links[1] = { tier = pre.tier + 1, column = pre.col + 1,
                   active = (state.ranks[pre.id] or 0) >= pre.maxRank }
    end
    local entries = view.trees[node.tab].talents
    entries[#entries + 1] = {
      index = node.id, name = ET.LocalizedField(node, "name"), icon = "Interface\\Icons\\" .. node.icon,
      tier = node.tier + 1, column = node.col + 1, rank = rank, state = color,
      exceptional = node.maxRank == 1,
      spendable = not view.readOnly and view.available > 0 and reachable, links = links,
    }
    view.depth = math.max(view.depth, node.tier + 1)
  end
  return view
end

local function FreshNode(ns, node, painted)
  if not (ns.win and ns.win:IsShown()) or ns.GlyphView() or ns.PetView() then return nil end
  local view = Describe(ns)
  if not view or view.status or not painted or view.guid ~= painted.guid
     or view.era ~= painted.era or view.classId ~= painted.classId then return nil end
  local talent = view.byId and view.byId[node.index]
  if talent and talent.tab == node.tree then return talent, view end
end

function ET.RefreshDragonTalents()
  local module, ns = DragonTalents()
  if module and module.applied then ns.Refresh() end
end

function ET.DragonInspectShown(unit)
  local module, ns = DragonTalents()
  if not (module and module.applied and ns.win and ns.win:IsShown() and ns.inspectUnit) then return false end
  return not unit or UnitGUID(ns.inspectUnit) == UnitGUID(unit)
end

function ET.ShowDragonInspect(unit)
  local module, ns = DragonTalents()
  if not (module and module.applied and ns.win) then return false end
  ns.ShowInspect(unit)
  return true
end

function ET.HideDragonInspect()
  local module, ns = DragonTalents()
  if module and module.applied and ns.win and ns.inspectUnit then ns.win:Hide() end
end

function ET.InitDragonUI()
  if ET._dragonHooked then return end
  local module, ns = DragonTalents()
  if not module then return end
  ET._dragonHooked = true
  ns.ExternalTalents = function(own)
    local view = Describe(ns, own)
    if not view then return nil end
    view.Tooltip = function(node, painted)
      local talent, fresh = FreshNode(ns, node, painted)
      if talent then ET.ShowTalentTooltip(node, talent, fresh.state, fresh.readOnly) end
    end
    view.Click = function(node, button, painted)
      if button ~= "LeftButton" then return end
      local talent, fresh = FreshNode(ns, node, painted)
      if not talent or fresh.readOnly or fresh.available < 1
         or (fresh.state.ranks[talent.id] or 0) >= talent.maxRank then return end
      if not ET.IsReachable(talent, fresh.trees[talent.tab].points, fresh.state.ranks, fresh.byId) then return end
      if fresh.guid then ET.LearnInspect(fresh.guid, talent.id) else ET.Learn(talent.id) end
    end
    return view
  end

  local toggle = ET.TogglePanel
  ET.TogglePanel = function(...)
    if module.applied then return ns.ToggleTalents() end
    return toggle(...)
  end

  local showInspect, leaveInspect = ns.ShowInspect, ns.LeaveInspect
  local inspected
  ns.ShowInspect = function(unit, ...)
    if module.applied and unit and UnitExists(unit) then
      inspected = UnitGUID(unit)
      if ET.inspect.current ~= inspected and ET.RefreshInspectTarget then ET.RefreshInspectTarget() end
    end
    local result = showInspect(unit, ...)
    if ET.RefreshInspect then ET.RefreshInspect() end
    return result
  end
  ns.LeaveInspect = function(...)
    local result = leaveInspect(...)
    if inspected then
      ET.inspect.cache[inspected] = nil
      if ET.inspect.current == inspected then ET.inspect.current = nil end
      if ET.inspect.botTarget == inspected then ET.inspect.botTarget = nil end
      inspected = nil
    end
    return result
  end

  local openStock = ET.OpenStockTalents
  ET.OpenStockTalents = function(...)
    if not (module.applied and ns.win and UnitExists("pet")) then return openStock(...) end
    ns.LeaveInspect()
    ns.SetGlyphPage(false)
    ns.wantPet = true
    if ns.win:IsShown() then ns.Repaint() else ns.win:Show() end
  end
end
