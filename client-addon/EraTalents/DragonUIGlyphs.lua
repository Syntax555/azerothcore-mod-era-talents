-- Before earned Wrath the server's glyph gate holds and it says so after every SYNC (GLYPHS 0).
-- DragonUI's glyph key, glyph tab and USE_GLYPH would open a page that cannot take a glyph, so
-- for such a character they show the gate instead and the glyph tab stays hidden. Without a
-- GLYPHS reply (a realm without EraTalents) DragonUI keeps its glyph page.
EraTalents = EraTalents or {}
local ET = EraTalents
local L = ET.L

local function DragonTalents()
  local dragon = _G.DragonUI
  local module = type(dragon) == "table" and dragon.TalentModule
  local ns = type(module) == "table" and module.ns
  if type(ns) ~= "table" or type(ns.SetGlyphPage) ~= "function" then return nil end
  return module, ns
end

function ET.InitDragonUIGlyphs()
  local module, ns = DragonTalents()
  if not module or ns._eraGlyphGate then return end
  ns._eraGlyphGate = true

  local function Blocked() return module.applied and ET.state.glyphsAllowed == false end
  local function Refuse()
    UIErrorsFrame:AddMessage(L["Glyphs become available once this character has earned Wrath of the Lich King."],
                             1.0, 0.1, 0.1, 1.0)
  end

  if type(ns.OpenGlyphs) == "function" then
    local openGlyphs = ns.OpenGlyphs
    ns.OpenGlyphs = function(...)
      if Blocked() then return Refuse() end
      return openGlyphs(...)
    end
  end
  local setGlyphPage = ns.SetGlyphPage
  ns.SetGlyphPage = function(on, ...)
    if on and Blocked() then
      Refuse()
      on = false
    end
    return setGlyphPage(on, ...)
  end
  if type(ns.RefreshTabs) == "function" then
    hooksecurefunc(ns, "RefreshTabs", function()
      local glyphTab = _G.DragonUI_TalentFrameTab4
      if glyphTab and Blocked() then glyphTab:Hide() end
    end)
  end
end
