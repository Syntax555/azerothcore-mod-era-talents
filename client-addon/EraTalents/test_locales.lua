-- Run with Lua 5.1 from the module root. Locale changes affect text only.
local addon = "client-addon/EraTalents/"
GetLocale = function() return "deDE" end
dofile(addon .. "Locales.lua")
local ET = EraTalents
assert(ET.locale == "deDE")
assert(ET.L["Pet Talents"] == "Begleitertalente")
assert(ET.L["Rank %d/%d"] == "Rang %d/%d")
assert(string.format(ET.L["Rank %d/%d"], 2, 5) == "Rang 2/5")
assert(ET.TabName({ name = "Beast Mastery" }) == "Tierherrschaft")
assert(ET.TabName({ name = "Affliction" }) == "Gebrechen")
assert(ET.TabName({ name = "Arms" }) == "Waffen")
assert(ET.L["A future untranslated message"] == "A future untranslated message")

local node = { id = 18250, name = "Improved Corruption", tooltip = { "English one", "English two" },
               localized = { deDE = { name = "Verbesserte Verderbnis", tooltip = { "Deutsch eins" } } } }
assert(ET.LocalizedField(node, "name") == "Verbesserte Verderbnis")
assert(ET.LocalizedField(node, "tooltip", 1) == "Deutsch eins")
assert(ET.LocalizedField(node, "tooltip", 2) == "English two", "missing rank retains era text")
assert(ET.LocalizedField(node, "tooltip", 3) == nil)
assert(ET.TabName({ name = "Arcane", localized = { deDE = { name = "Arkan" } } }) == "Arkan")
node.localized.deDE.name = ""
assert(ET.LocalizedField(node, "name") == "Improved Corruption", "empty translation falls back")
node.localized.deDE.tooltip = "malformed"
assert(ET.LocalizedField(node, "tooltip", 1) == "English one", "invalid rank table falls back")
assert(node.id == 18250 and node.name == "Improved Corruption", "localization never mutates IDs or authored data")

dofile(addon .. "Comms.lua")
ET.state = { ranks = {} }
local warnings = {}
DEFAULT_CHAT_FRAME = { AddMessage = function(_, message) table.insert(warnings, message) end }
GetSpellInfo = function(id) assert(id == 932999); return "EraTalents Gen a1b2c3d4" end
ET.CheckGeneration("a1b2c3d4")
assert(#warnings == 0, "German matching marker remains accepted")
ET.CheckGeneration("ffffffff")
assert(warnings[1]:find("Generation a1b2c3d4", 1, true))
assert(warnings[1]:find("Server jedoch ffffffff", 1, true))
assert(warnings[1]:find("Data/patch-V.mpq", 1, true), "filename remains exact")
GetSpellInfo = function() return nil end
ET.CheckGeneration("a1b2c3d4")
assert(warnings[2]:find("FEHLT", 1, true), "missing MPQ still warns in German")
local sent
SendAddonMessage = function(prefix, payload) sent = payload end
UnitName = function() return "Spieler" end
ET.Learn(18250)
assert(sent == "LEARN 18250", "wire protocol remains English and numeric")

UnitExists = function() return false end
dofile(addon .. "Hook.lua")
ET.OpenStockTalents()
assert(warnings[3]:find("Ruft einen Begleiter", 1, true))

dofile(addon .. "Tooltip.lua")
assert(ET.RewriteCastBase("Sofort", 2000, -1600, 1) == "0,4 Sek. Zauberzeit")
assert(ET.RewriteCastBase("0,4 Sek. Zauberzeit", 2000, -1600, 1) == "0,4 Sek. Zauberzeit")
assert(ET.RewriteCastBase("2 Sek. Zauberzeit", 2000, -2000, 1) == "Sofort")
assert(ET.RewriteCastBase("100 Mana", 2000, 0, 1) == nil)
-- Prefer localized templates exposed by WoW rather than assuming a German client phrasing.
SPELL_CAST_TIME_SEC = "Wirken in %.3g Sek."
SPELL_CAST_TIME_INSTANT = "Sofort"
assert(ET.RewriteCastBase("Wirken in 2 Sek.", 2000, -1600, 1) == "Wirken in 0,4 Sek.")
assert(ET.RewriteCastBase("Wirken in 0,4 Sek.", 2000, -1600, 1) == "Wirken in 0,4 Sek.")
assert(ET.RewriteCastBase("Wirken in 2 Sek.", 2000, -2000, 1) == "Sofort")
assert(ET.RewriteCastBase("6 Sek. Abklingzeit", 2000, 0, 1) == nil, "native cooldown stays untouched")

ET._classId = 9
ET.state = { isEraChar = true, era = 0, ranks = { [18250] = 4 } }
EraTalentsData = { [0] = { [9] = {
  castTimeBase = { Corruption = 2000 },
  localizedSpellNames = { deDE = { ["Verderbnis"] = "Corruption" } },
  spellMods = { Corruption = { { talent = 18250, attr = "castTime", kind = "flat",
                                vals = { -400, -800, -1200, -1600, -2000 } } } },
} } }
local function Text(value)
  return { value = value, GetText = function(self) return self.value end,
           SetText = function(self, text) self.value = text end }
end
GermanTooltipTextLeft1 = Text("Verderbnis")
GermanTooltipTextLeft2 = Text("Sofort")
local tooltip = { GetName = function() return "GermanTooltip" end,
                  NumLines = function() return 2 end, Show = function() end }
ET.ApplyToTooltip(tooltip)
assert(GermanTooltipTextLeft2:GetText() == "Wirken in 0,4 Sek.", "localized spell title resolves English mechanical key")
ET.ApplyToTooltip(tooltip)
assert(GermanTooltipTextLeft2:GetText() == "Wirken in 0,4 Sek.", "German rewrite remains idempotent")
ET.state.isEraChar = false
GermanTooltipTextLeft2:SetText("Sofort")
ET.ApplyToTooltip(tooltip)
assert(GermanTooltipTextLeft2:GetText() == "Sofort", "Wrath keeps native spell tooltip")

-- Render the actual player/inspect UI and drive the registered tooltip and click handlers.
local methods = {}
local function Object(name)
  return setmetatable({ name = name, scripts = {} }, { __index = methods })
end
for _, name in ipairs({ "SetFrameStrata", "SetPoint", "EnableMouse", "SetMovable", "RegisterForDrag",
                        "RegisterEvent", "SetAllPoints", "SetFrameLevel", "SetTexture", "SetTexCoord",
                        "SetTextColor", "SetAlpha", "EnableMouseWheel", "SetScrollChild", "SetDesaturated" }) do
  methods[name] = function() end
end
function methods:GetName() return self.name end
function methods:GetFrameLevel() return 0 end
function methods:SetWidth(value) self.width = value end
function methods:SetHeight(value) self.height = value end
function methods:SetText(value) self.text = value end
function methods:SetScript(name, fn) self.scripts[name] = fn end
function methods:Hide() self.shown = false end
function methods:Show() self.shown = true end
function methods:CreateTexture() return Object() end
function methods:CreateFontString() return Object() end
function methods:SetNormalTexture() self.normal = Object() end
function methods:GetNormalTexture() return self.normal end
CreateFrame = function(_, name) return Object(name) end
UIParent = Object("UIParent")
SetPortraitTexture = function() end
PanelTemplates_TabResize = function() end
PanelTemplates_SetNumTabs = function() end
PanelTemplates_SetTab = function() end
PanelTemplates_UpdateTabs = function() end
GameTooltip = { lines = {}, SetOwner = function() end,
                SetText = function(self, value) self.title = value; self.lines = {} end,
                AddLine = function(self, value) table.insert(self.lines, value) end,
                Show = function() end, Hide = function() end }
local errors = {}
UIErrorsFrame = { AddMessage = function(_, message) table.insert(errors, message) end }
local uiNode = { id = 18250, tab = 1, tier = 0, col = 0, name = "Improved Corruption", maxRank = 2,
                 prereqTalent = 0, prereqPoints = 0, tooltip = { "English one", "English two" },
                 localized = { deDE = { name = "Verbesserte Verderbnis", tooltip = { "Deutsch eins", "Deutsch zwei" } } } }
local tree = { tabs = { { name = "Affliction" }, { name = "Demonology" }, { name = "Destruction" } },
               talents = { uiNode } }
EraTalentsData = { [0] = { [9] = tree } }
dofile(addon .. "TalentUI.lua")
local view = ET.NewTreeView({ name = "GermanTalentFrame", chrome = true, defaultTab = 1 })
ET.RenderView(view, { era = 0, ranks = { [18250] = 1 }, availPts = 0 }, 9)
assert(view.frame.title.text == "Talente")
assert(view.frame.petTalents.text == "Begleitertalente" and view.frame.petTalents.width >= 120)
assert(view.frame.tabs[1].text == "Gebrechen")
assert(view.frame.footerSpent.text == "Gebrechen: 1")
assert(view.frame.footerUnspent.text == "Freie Punkte: 0")
local button = view.frame.pools[tree][18250]
button.scripts.OnEnter(button)
assert(GameTooltip.title == "Verbesserte Verderbnis")
assert(GameTooltip.lines[1] == "Rang 1/2")
assert(GameTooltip.lines[2] == "Deutsch eins")
assert(GameTooltip.lines[4] == "Nächster Rang:")
assert(GameTooltip.lines[5] == "Deutsch zwei")
button.scripts.OnClick(button)
assert(errors[1] == "Nicht genügend Talentpunkte.")
view.readOnly = true
button.scripts.OnEnter(button)
assert(#GameTooltip.lines == 2, "inspect has no next rank or learn action")
button.scripts.OnClick(button)
assert(#errors == 1, "inspect remains read-only")

-- Stock-granted talents retain authored historical prose: their base DBC can carry
-- English/Wrath text. Custom helpers keep the native localized DBC cost/cast headers.
local nativeLinks = {}
function GameTooltip:SetHyperlink(link)
  table.insert(nativeLinks, link)
  self.title = "Deutscher Hilfszauber"
  self.lines = { "Nativer deutscher Zauberheader" }
end
uiNode.grant = { [1] = 11069, [2] = 12338 }
button.scripts.OnEnter(button)
assert(#nativeLinks == 0, "stock-granted talent must not use untranslated/Wrath base DBC prose")
assert(GameTooltip.title == "Verbesserte Verderbnis")
assert(GameTooltip.lines[2] == "Deutsch eins", "stock grant keeps German era-authored rank text")
local localized = uiNode.localized
uiNode.localized = nil
button.scripts.OnEnter(button)
assert(#nativeLinks == 0)
assert(GameTooltip.title == "Improved Corruption" and GameTooltip.lines[2] == "English one",
       "missing stock-grant translation keeps the English historical text")
uiNode.localized = localized
uiNode.grant = { [1] = 932760, [2] = 932761 }
button.scripts.OnEnter(button)
assert(nativeLinks[1] == "spell:932760", "custom helper uses native localized DBC header")
assert(GameTooltip.title == "Deutscher Hilfszauber")
assert(GameTooltip.lines[1] == "Nativer deutscher Zauberheader" and GameTooltip.lines[2] == "Rang 1/2")

-- Other locales retain English UI and era-authored fallback; no silent switch to German.
GetLocale = function() return "frFR" end
dofile(addon .. "Locales.lua")
assert(ET.L["Pet Talents"] == "Pet Talents")
assert(ET.TabName({ name = "Beast Mastery" }) == "Beast Mastery")
assert(ET.LocalizedField(node, "name") == "Improved Corruption")
print("German locale and English fallback OK")
