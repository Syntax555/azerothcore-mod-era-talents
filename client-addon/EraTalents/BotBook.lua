-- MultiBot's bot spellbook in DragonUI's book. Window, pages, cards, section headers, tabs, search and
-- pager are DragonUI's: its spellbook module's layout functions place the cards, its atlas art and
-- strings dress them, and the card and header pieces mirror its book_slots.lua (MIT, NeticSoul), so a
-- bot's book reads like the player's. The data is the bot's: its learned spells from MultiBot and, from
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
-- Offsets of DragonUI's icon frame art around a 40-unit icon well (book_slots.lua SHAPES).
local SHAPES = {
  square = { ring = "spellbook-item-iconframe", hover = "spellbook-item-iconframe-hover",
             scroll = "spellbook-item-needtrainer-iconframe-backplate", -11, 1, 1, -7 },
  squareOff = { ring = "spellbook-item-iconframe-inactive", hover = "spellbook-item-iconframe-hover",
                scroll = "spellbook-item-needtrainer-iconframe-backplate", -10, 1, 2, -5 },
}
local SHAPE_PARTS = { "ring", "hover", "scroll" }

-- DragonUI's spellbook module and the addon around it, when they offer what the book uses.
local function DragonBook()
  local dragon = _G.DragonUI
  local book = type(dragon) == "table" and dragon.SpellbookModule
  if type(book) ~= "table" or type(book.FlowSections) ~= "function" or type(book.FitWindow) ~= "function"
      or type(book.InkLabel) ~= "function"
      or type(_G.DragonUI_NineSlice) ~= "table" then
    return nil
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

local function Matches(entry, query)
  local book = DragonBook()
  if not query then return true end
  if book and type(book.NameMatches) == "function" then return book.NameMatches(entry.name, query) end
  return entry.name ~= nil and string.find(string.lower(entry.name), query, 1, true) ~= nil
end

-- The sections DragonUI flows onto pages: a titled one per talent tree in the class book, one
-- untitled section in the general book. `names` are the trees' display names.
function ET.BotBookSections(trees, cat, names, query)
  local sections = {}
  local function add(title, entries)
    local kept = {}
    for _, entry in ipairs(entries) do
      if Matches(entry, query) then kept[#kept + 1] = entry end
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

local function Atlas(texture, name, useSize)
  if texture and texture.SetAtlasTexture then texture:SetAtlasTexture(name, useSize) end
end

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

local function OnWell(piece, well, shape, grow)
  piece:ClearAllPoints()
  piece:SetPoint("TOPLEFT", well, "TOPLEFT", shape[1] * grow, shape[2] * grow)
  piece:SetPoint("BOTTOMRIGHT", well, "BOTTOMRIGHT", shape[3] * grow, shape[4] * grow)
end

local function InkLabel(parent, layer, fontObject, size)
  return DragonBook().InkLabel(parent, layer, fontObject, size)
end

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
  card.grow = grid.iconButton / 40
  local well = CreateFrame("Frame", nil, card)
  well:SetSize(grid.iconButton, grid.iconButton)
  well:SetPoint("LEFT", card, "LEFT", 0, 0)
  card.well = well
  card.plate = card:CreateTexture(nil, "BACKGROUND")
  Atlas(card.plate, "spellbook-item-backplate", true)
  card.plate:SetPoint("CENTER", card, "CENTER", 5, -5)
  card.halo = card:CreateTexture(nil, "BORDER")
  Atlas(card.halo, "spellbook-item-needtrainer-shadow")
  card.halo:SetSize(56 * card.grow, 56 * card.grow)
  card.halo:SetPoint("CENTER", well, "CENTER", 0, 0)
  card.scroll = card:CreateTexture(nil, "ARTWORK")
  card.icon = card:CreateTexture(nil, "OVERLAY")
  card.icon:SetSize(grid.iconSize, grid.iconSize)
  card.icon:SetPoint("CENTER", well, "CENTER", 0, 0)
  local textWidth = grid.cardW - grid.iconButton - 14
  card.name = InkLabel(card, "OVERLAY", "GameFontHighlightLarge", 16)
  card.name:SetWidth(textWidth)
  card.name:SetPoint("TOPLEFT", well, "TOPRIGHT", 10, -1)
  card.sub = InkLabel(card, "OVERLAY", "GameFontNormalSmall", 13)
  card.sub:SetWidth(textWidth)
  card.sub:SetPoint("TOPLEFT", card.name, "BOTTOMLEFT", 0, -2)
  local rings = CreateFrame("Frame", nil, card)
  rings:SetFrameLevel(card:GetFrameLevel() + 2)
  rings:SetAllPoints(card)
  card.ring = rings:CreateTexture(nil, "ARTWORK")
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
  local shape = SHAPES[grey and "squareOff" or "square"]
  for _, part in ipairs(SHAPE_PARTS) do
    OnWell(card[part], card.well, shape, card.grow)
    Atlas(card[part], shape[part])
  end
  local trainable = grey and entry.state == "ready"
  if trainable then card.halo:Show(); card.scroll:Show() else card.halo:Hide(); card.scroll:Hide() end
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
  local header = CreateFrame("Frame", nil, frame.stage)
  header:SetSize(grid.viewW, grid.headerH)
  header:SetFrameLevel(frame.stage:GetFrameLevel() + 2)
  local plate = header:CreateTexture(nil, "BACKGROUND")
  Atlas(plate, "spellbook-list-backplate")
  plate:SetSize(416, 106)
  plate:SetPoint("LEFT", header, "LEFT", -85, 10)
  plate:SetAlpha(0.65)
  local rule = header:CreateTexture(nil, "BORDER")
  Atlas(rule, "spellbook-divider")
  rule:SetHeight(11)
  rule:SetPoint("BOTTOMLEFT", header, "BOTTOMLEFT", -32, 0)
  rule:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT", -60, 0)
  header.title = InkLabel(header, "ARTWORK", "GameFontNormalHuge", 24)
  header.title:SetPoint("TOPLEFT", header, "TOPLEFT", -8, 0)
  header.title:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT", -60, 0)
  header.title:SetJustifyV("MIDDLE")
  return header
end

-- Layout: DragonUI's window at its content scale --------------------------------------------------

local function Layout(wide, scale)
  local book = DragonBook()
  frame.wide, frame.scale = wide, scale
  frame:SetSize(book.WindowSize(wide, scale))
  local width = wide and book.WIDE_W or book.NARROW_W
  local stage = frame.stage
  stage:SetSize(width, book.HEIGHT)
  stage:SetScale(scale)
  stage:ClearAllPoints()
  stage:SetPoint("TOPLEFT", frame, "TOPLEFT", book.StageShift("TOPLEFT", scale))
  local art = frame.art
  if wide then art.left:Show(); art.ribbon:Show() else art.left:Hide(); art.ribbon:Hide() end
  art.right:ClearAllPoints()
  if wide then
    art.right:SetPoint("TOPLEFT", stage, "TOP", 1, -82)
    art.right:SetPoint("BOTTOMRIGHT", stage, "BOTTOMRIGHT", -2, 2)
  else
    art.right:SetPoint("TOPLEFT", stage, "TOPLEFT", 2, -82)
    art.right:SetPoint("BOTTOMRIGHT", stage, "BOTTOMRIGHT", 0, 2)
  end
  Atlas(art.wood, wide and "spellbook-background-evergreen-header" or "spellbook-header-left-half")
  Atlas(frame.mode:GetNormalTexture(), wide and "redbutton-condense" or "redbutton-expand")
  Atlas(frame.mode:GetPushedTexture(), (wide and "redbutton-condense" or "redbutton-expand") .. "-pressed")
  -- Pager, page corner, search and tabs stay at scale 1 on the scaled book, like DragonUI's.
  local x, y = book.OnBook("BOTTOMRIGHT", -75, 40, scale)
  frame.pager:ClearAllPoints()
  frame.pager:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", x, y)
  frame.next:ClearAllPoints()
  frame.next:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", x, y)
  frame.prev:ClearAllPoints()
  frame.prev:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", x - 40, y)
  frame.corner:ClearAllPoints()
  frame.corner:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", book.OnBook("BOTTOMRIGHT", -15, 6, scale))
  local searchX, searchY = book.OnBook("TOPRIGHT", -14, -55, scale)
  frame.search:ClearAllPoints()
  frame.search:SetPoint("RIGHT", frame, "TOPRIGHT", searchX, searchY)
end

-- Tabs hang from the wood strip in DragonUI's order, each as wide as its label.
local function PlaceTabs(scale)
  local book = DragonBook()
  local tabX, tabY = book.OnBook("TOPLEFT", 70, -83, scale)
  tabX = math.max(tabX, 60)
  for _, cat in ipairs(TAB_ORDER) do
    local tab = frame.tabs[cat]
    tab:ClearAllPoints()
    tab:SetPoint("BOTTOMLEFT", frame, "TOPLEFT", tabX, tabY)
    tabX = tabX + (tab:GetWidth() or 0) + 1
  end
end

-- DragonUI's tab art and width, then their places. Blizzard's OnShow resize undoes the width, and
-- DragonUI calls this again afterwards, as it does for its own book.
local function SkinTabs()
  local panel = _G.DragonUI and _G.DragonUI.CharacterPanel
  for _, cat in ipairs(TAB_ORDER) do
    local tab = frame.tabs[cat]
    if panel and panel.ReskinTab then panel.ReskinTab(tab, true) else PanelTemplates_TabResize(tab, 0) end
  end
  if frame.scale then PlaceTabs(frame.scale) end
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
  SkinTabs()
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

local function BuildPaper(stage)
  local paper = CreateFrame("Frame", nil, stage)
  paper:SetAllPoints(stage)
  local art = {}
  art.left = paper:CreateTexture(nil, "BACKGROUND")
  Atlas(art.left, "spellbook-background-evergreen-left")
  art.left:SetPoint("TOPLEFT", stage, "TOPLEFT", 2, -82)
  art.left:SetPoint("BOTTOMRIGHT", stage, "BOTTOM", -1, 2)
  art.right = paper:CreateTexture(nil, "BACKGROUND")
  Atlas(art.right, "spellbook-background-evergreen-right")
  art.ribbon = paper:CreateTexture(nil, "BORDER")
  Atlas(art.ribbon, "spellbook-background-evergreen-ribbon")
  art.ribbon:SetWidth(102)
  art.ribbon:SetPoint("TOP", stage, "TOP", 0, -82)
  art.ribbon:SetPoint("BOTTOM", stage, "BOTTOM", 0, 2)
  art.wood = paper:CreateTexture(nil, "ARTWORK")
  art.wood:SetHeight(58)
  art.wood:SetPoint("TOPLEFT", stage, "TOPLEFT", 8, -26)
  art.wood:SetPoint("TOPRIGHT", stage, "TOPRIGHT", -8, -26)
  return art
end

-- The page corner shows the first frame of its flipbook, as DragonUI's does at rest.
local function BuildCorner()
  local holder = CreateFrame("Frame", nil, frame)
  holder:SetAllPoints(frame)
  holder:SetFrameLevel(frame:GetFrameLevel() + 2)
  local corner = holder:CreateTexture(nil, "ARTWORK")
  Atlas(corner, "spellbook-corner-flipbook-evergreen")
  corner:SetSize(150, 155)
  local _, dragon = DragonBook()
  local atlas = dragon.atlasinfo and dragon.atlasinfo["spellbook-corner-flipbook-evergreen"]
  if atlas then
    corner:SetTexCoord(atlas[4], atlas[4] + (atlas[5] - atlas[4]) / 4, atlas[6], atlas[6] + (atlas[7] - atlas[6]) / 2)
  end
  return corner
end

local function BuildChrome()
  local _, dragon = DragonBook()
  local chrome = CreateFrame("Frame", nil, frame)
  chrome:SetAllPoints(frame)
  chrome:SetFrameLevel(frame:GetFrameLevel() + 11)
  DragonUI_NineSlice.ApplyLayout(chrome, DragonUI_NineSlice.GetLayout("PortraitFrameTemplateMinimizable"))
  frame.portrait = chrome:CreateTexture(nil, "ARTWORK")
  frame.portrait:SetSize(57, 57)
  frame.portrait:SetPoint("TOPLEFT", frame, "TOPLEFT", -3, 6)
  local band = CreateFrame("Frame", nil, frame)
  band:SetAllPoints(frame)
  band:SetFrameLevel(frame:GetFrameLevel() + 12)
  frame.title = band:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  frame.title:SetPoint("TOPLEFT", frame, "TOPLEFT", 58, -6)
  frame.title:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -24, -6)
  frame.title:SetJustifyH("CENTER")
  local close = CreateFrame("Button", nil, frame)
  close:SetSize(24, 24)
  close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 1, 0)
  close:SetFrameLevel(frame:GetFrameLevel() + 13)
  close:SetNormalTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Up")
  close:SetPushedTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Down")
  close:SetHighlightTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Highlight", "ADD")
  close:SetScript("OnClick", function() frame:Hide() end)
  local panel = dragon.CharacterPanel
  if panel and panel.ModernizeCloseButton then panel.ModernizeCloseButton(close, frame, 1, 0) end
  frame.close = close
  -- One or two pages, like DragonUI's red button; the choice holds for the bot book this session.
  local mode = CreateFrame("Button", nil, frame)
  mode:SetSize(24, 24)
  mode:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -24, 0)
  mode:SetFrameLevel(frame:GetFrameLevel() + 13)
  local sheet = dragon.atlasinfo and dragon.atlasinfo["redbutton-highlight"]
  for _, setter in ipairs({ "SetNormalTexture", "SetPushedTexture", "SetHighlightTexture" }) do
    mode[setter](mode, sheet and sheet[1] or "Interface\\Buttons\\UI-Panel-MinimizeButton-Up")
  end
  Atlas(mode:GetHighlightTexture(), "redbutton-highlight")
  mode:SetScript("OnClick", function()
    view.wide = not frame.wide
    Render()
  end)
  mode:SetScript("OnEnter", function()
    GameTooltip:SetOwner(mode, "ANCHOR_LEFT")
    GameTooltip:SetText(frame.wide and Text("Show single page") or Text("Show second page"))
    GameTooltip:Show()
  end)
  mode:SetScript("OnLeave", GameTooltip_Hide)
  frame.mode = mode
end

local function BuildSearch()
  local _, dragon = DragonBook()
  local finder = CreateFrame("EditBox", nil, frame)
  finder:SetSize(220, 22)
  finder:SetFrameLevel(frame:GetFrameLevel() + 3)
  finder:SetAutoFocus(false)
  finder:SetFontObject(ChatFontNormal)
  finder:SetTextInsets(18, 20, 0, 0)
  local border = "Interface\\Common\\Common-Input-Border"
  local capLeft = finder:CreateTexture(nil, "BACKGROUND")
  capLeft:SetTexture(border)
  capLeft:SetTexCoord(0, 0.0625, 0, 0.625)
  capLeft:SetSize(8, 20)
  capLeft:SetPoint("LEFT", finder, "LEFT", -5, 0)
  local capRight = finder:CreateTexture(nil, "BACKGROUND")
  capRight:SetTexture(border)
  capRight:SetTexCoord(0.9375, 1, 0, 0.625)
  capRight:SetSize(8, 20)
  capRight:SetPoint("RIGHT", finder, "RIGHT", 0, 0)
  local span = finder:CreateTexture(nil, "BACKGROUND")
  span:SetTexture(border)
  span:SetTexCoord(0.0625, 0.9375, 0, 0.625)
  span:SetHeight(20)
  span:SetPoint("TOPLEFT", capLeft, "TOPRIGHT", 0, 0)
  span:SetPoint("BOTTOMRIGHT", capRight, "BOTTOMLEFT", 0, 0)
  local glass = finder:CreateTexture(nil, "OVERLAY")
  glass:SetTexture((dragon._dir or "") .. "Collections\\UI-Searchbox-Icon")
  glass:SetSize(14, 14)
  glass:SetPoint("LEFT", finder, "LEFT", 2, -1.5)
  local hint = finder:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
  hint:SetPoint("LEFT", finder, "LEFT", 20, 0)
  hint:SetText(SEARCH)
  finder:SetScript("OnEditFocusGained", function() hint:Hide() end)
  finder:SetScript("OnEditFocusLost", function() if (finder:GetText() or "") == "" then hint:Show() end end)
  finder:SetScript("OnEscapePressed", function()
    finder:SetText("")
    finder:ClearFocus()
  end)
  finder:SetScript("OnEnterPressed", finder.ClearFocus)
  finder:SetScript("OnTextChanged", function(self)
    local book = DragonBook()
    local text = self:GetText()
    local query = nil
    if text and text ~= "" then
      query = type(book.NormalizeQuery) == "function" and book.NormalizeQuery(text) or string.lower(text)
    end
    if query == view.query then return end
    view.query, view.page = query, 1
    Render()
  end)
  frame.search = finder
end

local function BuildPager()
  local pager = CreateFrame("Frame", nil, frame)
  pager:SetSize(146, 32)
  pager:SetFrameLevel(frame:GetFrameLevel() + 3)
  frame.pageText = pager:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  frame.pageText:SetPoint("RIGHT", pager, "RIGHT", -76, 0)
  frame.pageText:SetJustifyH("RIGHT")
  frame.pageText:SetTextColor(0, 0, 0)
  frame.pageText:SetShadowOffset(0, 0)
  frame.pager = pager
  local function arrow(direction, step)
    local turner = CreateFrame("Button", nil, frame)
    turner:SetSize(32, 32)
    turner:SetFrameLevel(frame:GetFrameLevel() + 4)
    local art = "Interface\\Buttons\\UI-SpellbookIcon-" .. direction .. "Page-"
    turner:SetNormalTexture(art .. "Up")
    turner:SetPushedTexture(art .. "Down")
    turner:SetDisabledTexture(art .. "Disabled")
    turner:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
    turner:SetScript("OnClick", function() Turn(step) end)
    return turner
  end
  frame.next = arrow("Next", 1)
  frame.prev = arrow("Prev", -1)
  frame.empty = InkLabel(frame.stage, "ARTWORK", "GameFontHighlightLarge", 16)
  frame.empty:SetJustifyH("CENTER")
  local book = DragonBook()
  frame.empty:SetPoint("CENTER", frame.stage, "TOPLEFT", book.PageLeft(1) + book.GRID.viewW / 2,
                       book.GRID.viewTop - book.GRID.viewH / 2)
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
    tab._duiRelayout = SkinTabs
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
  frame.art = BuildPaper(frame.stage)
  frame.cards, frame.headers = {}, {}
  BuildChrome()
  frame.corner = BuildCorner()
  BuildSearch()
  BuildPager()
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
  local spellbook = type(MultiBot) == "table" and MultiBot.spellbook
  if type(spellbook) ~= "table" or not DragonBookOn() or spellbook._eraBotBook then return end
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
  table.insert(ET.bookHandlers, OnBotBook)
end
