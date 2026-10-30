-- MultiBot's bot spellbook in DragonUI's book. Window, pages, cards, section headers, tabs, search and
-- pager are DragonUI's: its spellbook module's layout functions place the cards and its shared
-- builders draw the paper, frame, card faces and section headers, so a bot's book reads like the
-- player's. The data is the bot's: its learned spells from MultiBot and, from
-- the server's trainer list for that bot (BOOK), the spells it can still learn, by talent tree. Cards
-- keep MultiBot's actions: left-click casts, right-click makes a macro and shift-click puts the spell on
-- the bot's skip list. Without DragonUI's spellbook module, or with it off, MultiBot keeps its own window.
EraTalents = EraTalents or {}
local ET = EraTalents
local L = ET.L

-- DragonUI's category ids; its tabs show the general book first.
local CLASS, GENERAL = 1, 2
local TAB_ORDER = { GENERAL, CLASS }
local CLASS_IDS = {
  WARRIOR = 1, PALADIN = 2, HUNTER = 3, ROGUE = 4, PRIEST = 5, DEATHKNIGHT = 6,
  SHAMAN = 7, MAGE = 8, WARLOCK = 9, DRUID = 11,
}
-- Talent tabs in TalentTab.dbc order, as the server's tree index counts them.
local TREES = {
  [1] = { "Arms", "Fury", "Protection" }, [2] = { "Holy", "Protection", "Retribution" },
  [3] = { "Beast Mastery", "Marksmanship", "Survival" }, [4] = { "Assassination", "Combat", "Subtlety" },
  [5] = { "Discipline", "Holy", "Shadow" }, [6] = { "Blood", "Frost", "Unholy" },
  [7] = { "Elemental", "Enhancement", "Restoration" }, [8] = { "Arcane", "Fire", "Frost" },
  [9] = { "Affliction", "Demonology", "Destruction" }, [11] = { "Balance", "Feral Combat", "Restoration" },
}
-- What the bot book takes from DragonUI's spellbook module; without any of it MultiBot keeps its own
-- window.
local BUILDERS = {
  "FlowSections", "FitWindow", "WindowSize", "StageShift", "OnBook", "PageLeft", "NameMatches",
  "InkLabel", "CreateCardFace", "PaintCardFrame", "CreateSectionHeader", "CreatePaperArt", "LayoutPaperArt",
  "CreateChrome", "DressCloseButton", "CreateModeButton", "PaintModeButton", "CreatePageCorner", "PaintCorner",
  "CreateSearchBox", "CreatePager", "DressPageArrow", "CreateEmptyLine", "PlaceControlsOn", "PlaceTabs",
}

-- DragonUI's spellbook module and the addon around it, when they offer what the book uses.
local function DragonBook()
  local dragon = _G.DragonUI
  local book = type(dragon) == "table" and dragon.SpellbookModule
  if type(book) ~= "table" or type(_G.DragonUI_NineSlice) ~= "table" then return nil end
  for _, name in ipairs(BUILDERS) do
    if type(book[name]) ~= "function" then return nil end
  end
  return book, dragon
end

-- The bot's book looks like the player's: DragonUI's while its spellbook module is on.
local function DragonBookOn()
  local book, dragon = DragonBook()
  if not book then return false end
  return type(dragon.IsModuleEnabled) ~= "function" or dragon:IsModuleEnabled("spellbook")
end

-- DragonUI's own wording, so both books say the same; EraTalents' strings otherwise.
local function Text(key)
  local _, dragon = DragonBook()
  local text = dragon and type(dragon.L) == "table" and rawget(dragon.L, key) or nil
  if type(text) == "string" then return text end
  return L[key]
end

local function ByLevelThenName(a, b)
  if a.level ~= b.level then return a.level < b.level end
  if a.name ~= b.name then return a.name < b.name end
  return a.spellID < b.spellID
end

-- Cards by tree (0 is the general book): the bot's learned spells in MultiBot's order, then the
-- first rank of every trainer chain it has not started, by level. `spells` are MultiBot's
-- {id, name, rank, icon, link}; `book` is the bot's BOOK entry; `level` may be unknown.
function ET.BotBookModel(spells, book, level)
  local index = book and book.classId ~= 0 and ET.TrainerIndex(book.records) or nil
  local known, memo = {}, {}
  for _, spell in ipairs(spells) do known[spell[1]] = true end
  -- A bot that learned a higher rank may no longer list the lower one.
  local function knownInChain(id)
    if memo[id] ~= nil then return memo[id] end
    memo[id] = false
    local answer = known[id] == true
    for _, record in ipairs(index and index.after[id] or {}) do
      answer = answer or knownInChain(record[2])
    end
    memo[id] = answer
    return answer
  end
  local function treeOf(id)
    local record = index and (index.byID[id] or (index.after[id] or {})[1])
    return record and record[8] or 0
  end
  local trees = { [0] = {}, {}, {}, {} }
  for _, spell in ipairs(spells) do
    table.insert(trees[treeOf(spell[1])], { spellID = spell[1], name = spell[2], rank = spell[3], icon = spell[4],
                                             link = spell[5] })
  end
  if not index then return trees end
  local greys = { [0] = {}, {}, {}, {} }
  for _, record in ipairs(index.list) do
    local root = record[4] ~= 0 and record[4] or record[2]
    local first = record[4] == 0 or not index.byID[record[4]]
    local name, rank, icon = GetSpellInfo(record[2])
    if first and name and not knownInChain(root) and greys[record[8]] then
      local state = "later"
      if record[5] ~= 0 and not knownInChain(record[5]) then
        state = "talent"
      elseif record[7] ~= 0 and not knownInChain(record[7]) then
        state = "spell"
      elseif level and record[1] <= level then
        state = "ready"
      end
      table.insert(greys[record[8]], { grey = true, spellID = record[2], name = name, rank = rank or "", icon = icon,
                                       level = record[1], cost = record[3], state = state, needs = record[7],
                                       higherRank = record[4] ~= 0 })
    end
  end
  for tree = 0, 3 do
    table.sort(greys[tree], ByLevelThenName)
    for _, entry in ipairs(greys[tree]) do table.insert(trees[tree], entry) end
  end
  return trees
end

-- The line under a card's name, worded like DragonUI's.
function ET.BotBookSubtitle(entry, active)
  if not entry.grey then
    if not active then return "|cffff2020" .. L["Skipped by the bot"] .. "|r" end
    return entry.rank or ""
  end
  if entry.state == "talent" then
    local text = Text("Requires talent")
    if entry.higherRank and entry.rank ~= "" then return entry.rank .. "  (" .. text .. ")" end
    return text
  end
  if entry.state == "spell" then
    local name = GetSpellInfo(entry.needs) or ""
    return ITEM_REQ_SKILL and ITEM_REQ_SKILL:format(name) or string.format(L["Requires %s"], name)
  end
  if entry.state == "ready" then return Text("Trainable") end
  return string.format(Text("Available at level %d"), entry.level)
end

-- The sections DragonUI flows onto pages: a titled one per talent tree in the class book, one
-- untitled section in the general book. `names` are the trees' display names; `query` is DragonUI's.
function ET.BotBookSections(trees, cat, names, query)
  local book = DragonBook()
  local sections = {}
  local function add(title, entries)
    local kept = {}
    for _, entry in ipairs(entries) do
      if book.NameMatches(entry.name, query) then kept[#kept + 1] = entry end
    end
    if #kept > 0 then sections[#sections + 1] = { title = title, entries = kept } end
  end
  if cat == GENERAL then
    add(nil, trees[0])
  else
    for tree = 1, 3 do add(names[tree], trees[tree]) end
  end
  return sections
end

-- Until a tab is clicked the book opens on the class book, or on the general book while the class
-- book is empty: without the bot's trainer book no spell has a tree yet.
local view = { name = nil, cat = CLASS, page = 1, picked = false, query = nil, wide = nil }
local frame

-- The skip list is MultiBot's: false marks a spell the bot leaves out, "ss" sends the whole list.
local function ToggleSkip(name, spellID)
  local spells = MultiBot.spells[name]
  spells[spellID] = not spells[spellID]
  local action = ""
  for id, state in pairs(spells) do
    if state == false then action = action .. (action == "" and "ss +" or ", +") .. id end
  end
  MultiBot.ActionToTarget(action == "" and "ss -" .. spellID or action, name)
end

local function BotUnit(name)
  return MultiBot.toUnit and MultiBot.toUnit(name) or nil
end

local function SetSpellbookButton(name, enabled)
  local units = MultiBot.frames and MultiBot.frames["MultiBar"] and MultiBot.frames["MultiBar"].frames["Units"]
  local unit = units and units.frames and units.frames[name or ""]
  local button = unit and unit.getButton and unit.getButton("Spellbook")
  local set = button and button[enabled and "setEnable" or "setDisable"]
  if set then set() end
end

local function CurrentModel()
  local unit = BotUnit(view.name)
  local guid = unit and UnitGUID(unit)
  local book = guid and ET.books.class[guid]
  if book and book.partial then book = nil end
  local level = unit and UnitLevel(unit) or nil
  local classId = book and book.classId ~= 0 and book.classId or (unit and CLASS_IDS[select(2, UnitClass(unit))])
  return ET.BotBookModel(MultiBot.spellbook.spells, book, level), classId, unit
end

-- Window size and content scale -------------------------------------------------------------------

-- DragonUI's own choice: its scale, and two pages unless they do not fit or one page was chosen.
local function Placement()
  local book = DragonBook()
  local config = type(book.Config) == "function" and book.Config() or {}
  local wanted = math.min(1.2, math.max(0.5, tonumber(config.scale) or 0.8))
  local wantWide = view.wide
  if wantWide == nil then wantWide = not config.minimized end
  return book.FitWindow(wantWide, view.wide ~= nil or config.forceWide, wanted,
                        UIParent:GetWidth(), UIParent:GetHeight())
end

-- Cards -------------------------------------------------------------------------------------------

local function PaintHover(card)
  local live = card.entry ~= nil and not card.entry.grey
  card.plate:SetAlpha(live and card.over and 1 or 0.25)
  card.hover:SetAlpha(live and card.over and 0.35 or 0)
end

local function CardEnter(card)
  local entry = card.entry
  if not entry then return end
  card.over = true
  PaintHover(card)
  GameTooltip:SetOwner(card, "ANCHOR_RIGHT")
  GameTooltip:SetHyperlink("spell:" .. entry.spellID)
  if entry.grey then
    local gold = NORMAL_FONT_COLOR or { r = 1, g = 0.82, b = 0 }
    local unit = BotUnit(view.name)
    local level = unit and UnitLevel(unit) or 0
    local line = level < entry.level and TRAINER_REQ_LEVEL_RED or TRAINER_REQ_LEVEL
    if REQUIRES_LABEL and line then
      GameTooltip:AddLine(REQUIRES_LABEL .. " " .. line:format(entry.level), gold.r, gold.g, gold.b)
    else
      GameTooltip:AddLine(string.format(Text("Available at level %d"), entry.level), gold.r, gold.g, gold.b)
    end
    GameTooltip:AddLine(Text("Training Cost") .. ": " .. GetCoinTextureString(entry.cost), 1, 1, 1)
  else
    GameTooltip:AddLine(L["Left-click: cast. Right-click: macro."], 0.6, 0.6, 0.6)
    GameTooltip:AddLine(L["Shift-click: the bot skips it."], 0.6, 0.6, 0.6)
  end
  GameTooltip:Show()
end

local function CardLeave(card)
  card.over = false
  PaintHover(card)
  GameTooltip_Hide()
end

local Render

local function CardClick(card, button)
  local entry = card.entry
  if not entry or entry.grey then return end
  if IsShiftKeyDown and IsShiftKeyDown() then
    ToggleSkip(view.name, entry.spellID)
    Render()
  elseif button == "RightButton" then
    MultiBot.SpellToMacro(view.name, entry.spellID, entry.icon)
  else
    SendChatMessage("cast " .. entry.spellID, "WHISPER", nil, view.name)
  end
end

local function BuildCard(grid)
  local card = CreateFrame("Button", nil, frame.stage)
  card:SetSize(grid.cardW, grid.cardH)
  card:SetFrameLevel(frame.stage:GetFrameLevel() + 3)
  card:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  local rings = DragonBook().CreateCardFace(card, grid.iconButton, grid.iconSize, grid.cardW - grid.iconButton - 14,
                                            card:GetFrameLevel() + 2)
  card.hover = rings:CreateTexture(nil, "OVERLAY")
  card.hover:SetBlendMode("ADD")
  card:SetScript("OnEnter", CardEnter)
  card:SetScript("OnLeave", CardLeave)
  card:SetScript("OnClick", CardClick)
  return card
end

local function PaintCard(card, entry, skips)
  card.entry = entry
  local grey = entry.grey
  local active = grey or skips[entry.spellID] ~= false
  DragonBook().PaintCardFrame(card, grey and "squareOff" or "square", grey and entry.state == "ready")
  local icon = entry.icon or "Interface\\Icons\\INV_Misc_QuestionMark"
  if not string.find(icon, "[/\\]") then icon = "Interface\\Icons\\" .. icon end
  card.icon:SetTexture(icon)
  card.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  card.icon:SetDesaturated(grey or not active)
  local alpha = (grey or not active) and 0.6 or 1
  card.icon:SetAlpha(alpha)
  card.name:SetAlpha(alpha)
  card.sub:SetAlpha(alpha)
  card.name:SetText(entry.name)
  card.sub:SetText(ET.BotBookSubtitle(entry, active))
  PaintHover(card)
end

local function BuildHeader(grid)
  return DragonBook().CreateSectionHeader(frame.stage, grid.viewW, grid.headerH, frame.stage:GetFrameLevel() + 2)
end

-- Layout: DragonUI's window at its content scale --------------------------------------------------

local function Layout(wide, scale)
  local book = DragonBook()
  frame.wide, frame.scale = wide, scale
  frame:SetSize(book.WindowSize(wide, scale))
  local stage = frame.stage
  stage:SetSize(wide and book.WIDE_W or book.NARROW_W, book.HEIGHT)
  stage:SetScale(scale)
  stage:ClearAllPoints()
  stage:SetPoint("TOPLEFT", frame, "TOPLEFT", book.StageShift("TOPLEFT", scale))
  book.LayoutPaperArt(frame.art, stage, wide)
  book.PaintModeButton(frame.mode)
  -- Search, pager and page corner stay at scale 1 on the scaled book, like DragonUI's.
  book.PlaceControlsOn(frame, scale, { top = frame.search, pager = frame.pager, corner = frame.corner,
                                       arrows = { frame.next, frame.prev } })
end

-- DragonUI skins the tabs and hangs them from the wood strip in its order. Blizzard's OnShow resize
-- undoes the width, and DragonUI calls this again afterwards, as it does for its own book.
local function PlaceTabs()
  if not frame.scale then return end
  local faces = {}
  for index, cat in ipairs(TAB_ORDER) do faces[index] = frame.tabs[cat] end
  DragonBook().PlaceTabs(frame, faces, frame.scale)
end

-- Drawing -----------------------------------------------------------------------------------------

Render = function()
  if not frame or not frame:IsShown() then return end
  local book = DragonBook()
  local wide, scale = Placement()
  if wide ~= frame.wide or scale ~= frame.scale then Layout(wide, scale) end
  local trees, classId, unit = CurrentModel()
  local names = {}
  for tree = 1, 3 do names[tree] = L[(TREES[classId or 0] or {})[tree] or "Talents"] end
  if not view.picked then
    view.cat = #ET.BotBookSections(trees, CLASS, names, nil) > 0 and CLASS or GENERAL
  end
  local className = unit and UnitClass(unit) or nil
  frame.tabs[CLASS]:SetText(className or L["Talents"])
  frame.tabs[GENERAL]:SetText(_G.GENERAL)
  PlaceTabs()
  for _, cat in ipairs(TAB_ORDER) do
    local tab = frame.tabs[cat]
    if cat == view.cat then PanelTemplates_SelectTab(tab) else PanelTemplates_DeselectTab(tab) end
  end
  frame.selected = view.cat
  local spreads = book.FlowSections(ET.BotBookSections(trees, view.cat, names, view.query), wide and 2 or 1,
                                    wide and book.WIDE_W or book.NARROW_W)
  view.page = math.max(1, math.min(view.page, #spreads))
  local spread = spreads[view.page]
  frame.pageText:SetFormattedText(Text("Page %d/%d"), view.page, #spreads)
  if view.page > 1 then frame.prev:Enable() else frame.prev:Disable() end
  if view.page < #spreads then frame.next:Enable() else frame.next:Disable() end
  frame.empty:SetText(#spread.cards == 0 and view.query and Text("No spells match your search") or "")
  local grid, skips = book.GRID, MultiBot.spells[view.name] or {}
  for slot = 1, math.max(#spread.cards, #frame.cards) do
    local cell, card = spread.cards[slot], frame.cards[slot]
    if cell then
      card = card or BuildCard(grid)
      frame.cards[slot] = card
      card:ClearAllPoints()
      card:SetPoint("TOPLEFT", frame.stage, "TOPLEFT", cell.x, cell.y)
      PaintCard(card, cell.entry, skips)
      card:Show()
    elseif card then
      card:Hide()
      card.entry, card.over = nil, false
    end
  end
  for slot = 1, math.max(#spread.headers, #frame.headers) do
    local item, header = spread.headers[slot], frame.headers[slot]
    if item then
      header = header or BuildHeader(grid)
      frame.headers[slot] = header
      header:ClearAllPoints()
      header:SetPoint("TOPLEFT", frame.stage, "TOPLEFT", item.x, item.y)
      header.title:SetText(item.title)
      header:Show()
    elseif header then
      header:Hide()
    end
  end
end
ET.RenderBotBook = Render

local function Turn(step)
  view.page = view.page + step
  if view.page < 1 then view.page = 1 end
  PlaySound("igAbiliityPageTurn")
  Render()
end

-- Window ------------------------------------------------------------------------------------------

-- DragonUI's frame, page corner at rest, close and page-mode buttons, search, pager and empty line.
local function BuildControls(book)
  local level = frame:GetFrameLevel()
  frame.portrait, frame.title = book.CreateChrome(frame, level + 11, level + 12)
  frame.corner = book.CreatePageCorner(frame, level + 2)
  book.PaintCorner(frame.corner, 1)
  local close = CreateFrame("Button", nil, frame)
  book.DressCloseButton(close, frame, level + 13)
  close:SetScript("OnClick", function() frame:Hide() end)
  frame.close = close
  -- One or two pages; the choice holds for the bot book this session.
  frame.mode = book.CreateModeButton(frame, level + 13, function() return frame.wide end, function()
    view.wide = not frame.wide
    Render()
  end)
  frame.search = book.CreateSearchBox(frame, function(query)
    if query == view.query then return end
    view.query, view.page = query, 1
    Render()
  end)
  frame.search:SetFrameLevel(level + 3)
  frame.pager, frame.pageText = book.CreatePager(frame)
  frame.pager:SetFrameLevel(level + 3)
  local function arrow(direction, step)
    local turner = CreateFrame("Button", nil, frame)
    book.DressPageArrow(turner, direction)
    turner:SetFrameLevel(level + 4)
    turner:SetScript("OnClick", function() Turn(step) end)
    return turner
  end
  frame.next = arrow("Next", 1)
  frame.prev = arrow("Prev", -1)
  frame.empty = book.CreateEmptyLine(frame.stage, frame.stage)
end

-- DragonUI levels a tab one above its parent, four while selected. The tabs' own holder sits above
-- the paper, as in DragonUI's book, so the tab not selected stays in front of the wood strip.
local function BuildTabs()
  local holder = CreateFrame("Frame", nil, frame)
  holder:SetAllPoints(frame)
  holder:SetFrameLevel(frame:GetFrameLevel() + 3)
  frame.tabs = {}
  for _, cat in ipairs(TAB_ORDER) do
    local tab = CreateFrame("Button", "EraTalentsBotBookFrameTab" .. cat, holder, "CharacterFrameTabButtonTemplate")
    tab:SetID(cat)
    tab:SetFrameLevel(holder:GetFrameLevel() + 1)
    tab._duiRelayout = PlaceTabs
    tab:SetScript("OnClick", function(self)
      view.cat, view.page, view.picked = self:GetID(), 1, true
      PlaySound("igCharacterInfoTab")
      Render()
    end)
    frame.tabs[cat] = tab
  end
end

local function BuildFrame()
  frame = CreateFrame("Frame", "EraTalentsBotBookFrame", UIParent)
  frame:SetFrameStrata("HIGH")
  frame:SetToplevel(true)
  frame:EnableMouse(true)
  frame:SetMovable(true)
  frame:SetClampedToScreen(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", frame.StartMoving)
  frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
  frame:SetPoint("CENTER", UIParent, "CENTER", 0, 20)
  frame:Hide()
  table.insert(UISpecialFrames, "EraTalentsBotBookFrame")
  local fill = frame:CreateTexture(nil, "BACKGROUND")
  fill:SetTexture(0.03, 0.04, 0.03, 1)
  fill:SetPoint("TOPLEFT", frame, "TOPLEFT", 2, -21)
  fill:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -2, 2)
  frame.stage = CreateFrame("Frame", nil, frame)
  local book = DragonBook()
  frame.art = book.CreatePaperArt(frame.stage, frame.stage:GetFrameLevel() + 1)
  frame.cards, frame.headers = {}, {}
  BuildControls(book)
  BuildTabs()
  frame:EnableMouseWheel(true)
  frame:SetScript("OnMouseWheel", function(_, delta) Turn(-delta) end)
  frame:SetScript("OnShow", Render)
  -- MultiBot shows a bot's spellbook button pressed while its book is open.
  frame:SetScript("OnHide", function()
    SetSpellbookButton(view.name, false)
  end)
end

function ET.ShowBotBook(name)
  if not frame then BuildFrame() end
  local changed = name ~= view.name
  view.name = name
  if changed then view.cat, view.page, view.picked = CLASS, 1, false end
  frame.title:SetText(string.format(L["%s's Spellbook"], name))
  local unit = BotUnit(name)
  local token = unit and select(2, UnitClass(unit))
  local _, dragon = DragonBook()
  if token then frame.portrait:SetTexture(dragon._dir .. "ClassIcons\\" .. token) end
  local guid = unit and UnitGUID(unit)
  if guid then ET.RequestBook(guid) end
  frame:Show()
  SetSpellbookButton(name, true)
  Render()
end

local function OnBotBook(guid, kind)
  if kind ~= "class" or not (frame and frame:IsShown()) then return end
  local unit = BotUnit(view.name)
  if unit and UnitGUID(unit) == guid then Render() end
end

function ET.InitBotBook()
  local book, dragon = DragonBook()
  local spellbook = type(MultiBot) == "table" and MultiBot.spellbook
  if type(spellbook) ~= "table" or not book or spellbook._eraBotBook then return end
  spellbook._eraBotBook = true
  local show, hide, visible = spellbook.Show, spellbook.Hide, spellbook.IsVisible
  spellbook.Show = function(self, ...)
    if not DragonBookOn() then
      if frame then frame:Hide() end
      show(self, ...)
      SetSpellbookButton(self.name, true)
      return
    end
    if visible(self) then hide(self) end
    ET.ShowBotBook(self.name)
  end
  spellbook.Hide = function(self, ...)
    if frame then frame:Hide() end
    return hide(self, ...)
  end
  spellbook.IsVisible = function(self, ...)
    return (frame ~= nil and frame:IsShown()) or visible(self, ...)
  end
  -- DragonUI can change the running book without a reload; keep an open bot book on that route.
  local function syncBook()
    if frame and frame:IsShown() or visible(spellbook) then spellbook:Show() end
  end
  for _, action in ipairs({ "RefreshSpellbookSystem", "RestoreSpellbookSystem" }) do
    if type(dragon[action]) == "function" then hooksecurefunc(dragon, action, syncBook) end
  end
  if type(book.ApplyScale) == "function" then hooksecurefunc(book, "ApplyScale", Render) end
  table.insert(ET.bookHandlers, OnBotBook)
end
