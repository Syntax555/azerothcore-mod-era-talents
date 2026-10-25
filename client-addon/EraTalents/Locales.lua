-- Client language affects presentation only; IDs, ranks and protocol remain unchanged.
EraTalents = EraTalents or {}
local ET = EraTalents
ET.locale = (GetLocale and GetLocale()) or "enUS"

local deDE = {
  ["Talents"] = "Talente",
  ["Loading talent data..."] = "Talentdaten werden geladen...",
  ["Waiting for server talent data..."] = "Warten auf Talentdaten des Servers...",
  ["Install the matching EraTalents client patch and restart the game."] =
    "Installiert den passenden EraTalents-Client-Patch und startet das Spiel neu.",
  ["Install the matching EraTalents addon and reload the interface."] =
    "Installiert das passende EraTalents-Add-on und ladet die Oberfläche neu.",
  ["Pet Talents"] = "Begleitertalente",
  ["Rank %d/%d"] = "Rang %d/%d",
  ["Next rank:"] = "Nächster Rang:",
  ["Not enough talent points."] = "Nicht genügend Talentpunkte.",
  ["%s Talents: %d"] = "%s: %d",
  ["Unspent Talents: %d"] = "Freie Punkte: %d",
  ["Instant"] = "Sofort",
  ["%s sec cast"] = "%s Sek. Zauberzeit",
  ["MISSING"] = "FEHLT",
  ["|cffffd000EraTalents:|r summon a pet to view its talent tree."] =
    "|cffffd000EraTalents:|r Ruft einen Begleiter, um seine Talente anzusehen.",
  ["|cffff2020EraTalents: your client patch is generation %s but the server is %s. Replace Data/patch-V.mpq with the current one and restart the game.|r"] =
    "|cffff2020EraTalents: Euer Client-Patch hat die Generation %s, der Server jedoch %s. Ersetzt Data/patch-V.mpq durch die aktuelle Datei und startet das Spiel neu.|r",
  ["Affliction"] = "Gebrechen", ["Arcane"] = "Arkan", ["Arms"] = "Waffen",
  ["Assassination"] = "Meucheln", ["Balance"] = "Gleichgewicht",
  ["Beast Mastery"] = "Tierherrschaft", ["Combat"] = "Kampf",
  ["Demonology"] = "Dämonologie", ["Destruction"] = "Zerstörung",
  ["Discipline"] = "Disziplin", ["Elemental"] = "Elementar",
  ["Enhancement"] = "Verstärkung", ["Feral Combat"] = "Wilder Kampf",
  ["Fire"] = "Feuer", ["Frost"] = "Frost", ["Fury"] = "Furor",
  ["Holy"] = "Heilig", ["Marksmanship"] = "Treffsicherheit",
  ["Protection"] = "Schutz", ["Restoration"] = "Wiederherstellung",
  ["Retribution"] = "Vergeltung", ["Shadow"] = "Schatten",
  ["Subtlety"] = "Täuschung", ["Survival"] = "Überleben",
  ["Glyphs become available once this character has earned Wrath of the Lich King."] =
    "Glyphen stehen zur Verfügung, sobald dieser Charakter Wrath of the Lich King erspielt hat.",
  ["%s's Spellbook"] = "Zauberbuch von %s",
  ["Trainable"] = "Erlernbar",
  ["Available at level %d"] = "Verfügbar ab Stufe %d",
  ["Requires talent"] = "Benötigt Talent",
  ["Requires %s"] = "Benötigt %s",
  ["Skipped by the bot"] = "Vom Bot übersprungen",
  ["Left-click: cast. Right-click: macro."] = "Linksklick: wirken. Rechtsklick: Makro.",
  ["Shift-click: the bot skips it."] = "Umschalt-Klick: der Bot lässt ihn aus.",
  ["Training Cost"] = "Trainingskosten",
  ["No spells match your search"] = "Keine Zauber entsprechen deiner Suche",
  ["Show single page"] = "Einzelne Seite anzeigen",
  ["Show second page"] = "Zweite Seite anzeigen",
  ["Page %d/%d"] = "Seite %d/%d",
  ["Blood"] = "Blut", ["Unholy"] = "Unheilig",
}
ET.L = setmetatable(ET.locale == "deDE" and deDE or {}, {
  __index = function(_, key) return key end,
})

-- Generated talent translations are keyed by locale. A missing field/rank keeps the
-- authored English text, without substituting a different expansion's spell tooltip.
function ET.LocalizedField(data, field, rank)
  if not data then return nil end
  local localized = data.localized and data.localized[ET.locale]
  local value = localized and localized[field]
  if rank then value = type(value) == "table" and value[rank] or nil end
  if type(value) == "string" and value ~= "" then return value end
  local fallback = data[field]
  if rank then fallback = type(fallback) == "table" and fallback[rank] or nil end
  return fallback
end

function ET.TabName(tab)
  return ET.L[ET.LocalizedField(tab, "name") or "Talents"]
end
