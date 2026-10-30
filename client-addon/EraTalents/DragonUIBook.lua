-- DragonUI's spellbook and level-up notice list the class spells still to learn from a fixed WotLK
-- trainer table. The server sends the character's own trainer list instead (BOOK), filtered like
-- the trainer window by earned era, talents and class quests, and it replaces that table for the
-- player's class. Without a reply DragonUI keeps its own table.
--
-- The level-up notice also lists riding, dungeons, raids, heroic modes and features by level. Riding
-- levels come from the riding trainers' own list (RIDING), and instances of a later expansion than the
-- character's earned era stay out. Glyph features follow the server's glyph gate (GLYPHS), and the
-- Dungeon Finder and dual specialization the realm's own switch and level (UNLOCKS).
EraTalents = EraTalents or {}
local ET = EraTalents

-- Learning and talent changes arrive in bursts; one request follows the last of them.
local BOOK_DELAY = 1

local function DragonBook()
  local dragon = _G.DragonUI
  local book = type(dragon) == "table" and dragon.SpellbookModule
  if type(book) ~= "table" or type(book.TrainerIndex) ~= "function" then return nil end
  return book
end

-- The shape Book.TrainerIndex returns: the records, their next ranks by previous rank, and by spell.
function ET.TrainerIndex(records)
  local after, byID = {}, {}
  for _, record in ipairs(records) do
    byID[record[2]] = record
    local previous = record[4]
    if previous ~= 0 then
      after[previous] = after[previous] or {}
      table.insert(after[previous], record)
    end
  end
  return { list = records, after = after, byID = byID }
end

local ownIndex

local function OnOwnBook(guid, kind)
  if kind ~= "class" or guid ~= UnitGUID("player") then return end
  local entry = ET.books.class[guid]
  if entry.classId == 0 then return end
  ownIndex = ET.TrainerIndex(entry.records)
  local book = DragonBook()
  if book and type(book.MarkAllDirty) == "function" then book.MarkAllDirty() end
end

local GLYPH_FEATURES = { glyphs = true, majorGlyph = true, minorGlyph = true }

-- Without a server reply a feature keeps DragonUI's native level.
local function FeatureRows(base)
  local state, rows = ET.state, {}
  for _, row in ipairs(base.features or {}) do
    local feature = row[2]
    if feature == "dualSpec" and state.dualSpecLevel then
      rows[#rows + 1] = { state.dualSpecLevel, feature }
    elseif not (GLYPH_FEATURES[feature] and state.glyphsAllowed == false)
        and not (feature == "dungeonFinder" and state.dungeonFinder == false) then
      rows[#rows + 1] = row
    end
  end
  return rows
end

local function LevelUpRows(base, key)
  if key == "features" then return FeatureRows(base) end
  if key == "riding" then
    local riding = ET.books.riding[UnitGUID("player")]
    if riding and not riding.partial then return riding.records end
    return base.riding
  end
  local era = ET.state.era
  if era == nil or era >= 2 or not (key == "dungeons" or key == "raids" or key == "heroics") then return base[key] end
  local rows = {}
  for _, row in ipairs(base[key] or {}) do
    -- A heroic row names its expansion; an instance's comes from LFGDungeons, and one the client
    -- cannot tell yet is left out rather than announced.
    local expansion = row[2]
    if key ~= "heroics" then expansion = select(8, GetLFGDungeonInfo(row[2])) end
    if expansion and expansion <= era then rows[#rows + 1] = row end
  end
  return rows
end

local function InitLevelUp(dragon)
  local base = dragon.LevelUpData
  if type(base) ~= "table" or dragon._eraLevelUp then return end
  dragon._eraLevelUp = true
  dragon.LevelUpData = setmetatable({}, { __index = function(_, key) return LevelUpRows(base, key) end })
end

function ET.InitDragonUIBook()
  local book = DragonBook()
  if not book or book._eraTrainerBook then return end
  book._eraTrainerBook = true
  InitLevelUp(_G.DragonUI)

  local trainerIndex = book.TrainerIndex
  book.TrainerIndex = function(classToken, ...)
    if ownIndex and classToken == select(2, UnitClass("player")) then return ownIndex end
    return trainerIndex(classToken, ...)
  end
  table.insert(ET.bookHandlers, OnOwnBook)

  local waited = 0
  local timer = CreateFrame("Frame")
  timer:Hide()
  timer:SetScript("OnUpdate", function(self, elapsed)
    waited = waited + elapsed
    if waited < BOOK_DELAY then return end
    self:Hide()
    ET.RequestBook(UnitGUID("player"))
  end)
  ET.RefreshOwnBook = function()
    waited = 0
    timer:Show()
  end

  -- Talent ranks (SYNC), class quests and purchases change what the trainer lists.
  local events = CreateFrame("Frame")
  events:RegisterEvent("LEARNED_SPELL_IN_TAB")
  events:SetScript("OnEvent", ET.RefreshOwnBook)
  table.insert(ET.syncHandlers, ET.RefreshOwnBook)
  ET.RefreshOwnBook()
end
