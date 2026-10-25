/*
 * This file is part of the AzerothCore Project. See AUTHORS file for Copyright
 * information
 *
 * This program is free software; you can redistribute it and/or modify it
 * under the terms of the GNU General Public License as published by the
 * Free Software Foundation; either version 2 of the License, or (at your
 * option) any later version.
 */

#include "EraGlyphGate.h"

#include "DBCStores.h"
#include "EraTalentBots.h"
#include "EraTalentIP.h"
#include "EraTalentsConfig.h"
#include "EraTransition.h"
#include "Player.h"
#include "ScriptMgr.h"
#include "Spell.h"
#include "SpellAuras.h"
#include "SpellInfo.h"
#include "SpellMgr.h"

namespace EraGlyphGate
{
bool Allowed(Player* player)
{
    if (!player || !sEraTalentsConfig->Enabled() || !sEraTalentsConfig->GlyphGate())
        return true;
    if (player->getClass() == CLASS_DEATH_KNIGHT)
        return true;  // Preserve existing hero-class characters; strict creation is
                      // gated elsewhere.
    return EraTalentBots::EraFor(player) == ERA_WOTLK && EraTransition::StoredEra(player) == ERA_WOTLK;
}

bool IsOwnedGlyphSpell(Player* player, uint32 spellId)
{
    if (!player)
        return false;
    for (uint8 slot = 0; slot < MAX_GLYPH_SLOT_INDEX; ++slot)
        if (GlyphPropertiesEntry const* glyph = sGlyphPropertiesStore.LookupEntry(player->GetGlyph(slot)))
            if (glyph->SpellId == spellId)
                return true;
    return false;
}

void StripIfDisallowed(Player* player)
{
    if (!player)
        return;
    bool const allowed = Allowed(player);
    bool changed = false;
    for (uint8 slot = 0; slot < MAX_GLYPH_SLOT_INDEX; ++slot)
    {
        uint32 const glyphId = player->GetGlyph(slot);
        uint32 const visible = allowed ? glyphId : 0;
        if (player->GetUInt32Value(PLAYER_FIELD_GLYPHS_1 + slot) != visible)
        {
            // GetGlyph reads the persisted per-spec ownership array. Hide only the
            // client field; SetGlyph(0) would consume an earned glyph and overwrite
            // saved ownership.
            player->SetUInt32Value(PLAYER_FIELD_GLYPHS_1 + slot, visible);
            changed = true;
        }
        GlyphPropertiesEntry const* glyph = sGlyphPropertiesStore.LookupEntry(glyphId);
        if (!glyph)
            continue;
        if (allowed)
        {
            GlyphSlotEntry const* glyphSlot = sGlyphSlotStore.LookupEntry(player->GetGlyphSlot(slot));
            SpellInfo const* info = sSpellMgr->GetSpellInfo(glyph->SpellId);
            if (glyphSlot && glyphSlot->TypeFlags == glyph->TypeFlags && info && !player->HasAura(glyph->SpellId))
                player->CastSpell(player, glyph->SpellId,
                                  TriggerCastFlags(TRIGGERED_FULL_MASK &
                                                   ~(TRIGGERED_IGNORE_SHAPESHIFT | TRIGGERED_IGNORE_CASTER_AURASTATE)));
            continue;
        }

        player->RemoveAurasDueToSpell(glyph->SpellId);
        Unit::AuraMap& owned = player->GetOwnedAuras();
        for (Unit::AuraMap::iterator it = owned.begin(); it != owned.end();)
        {
            Aura* aura = it->second;
            if (SpellInfo const* trigger = aura->GetTriggeredByAuraSpellInfo())
            {
                if (trigger->Id == glyph->SpellId)
                {
                    player->RemoveOwnedAura(it);
                    continue;
                }
            }
            ++it;
        }
    }
    if (changed)
        player->SendTalentsInfoData(false);
}
}  // namespace EraGlyphGate

class era_glyph_gate : public PlayerScript
{
public:
    era_glyph_gate() : PlayerScript("era_glyph_gate") {}

    [[nodiscard]] bool OnPlayerCanUseItem(Player* player, ItemTemplate const* item, InventoryResult& result) override
    {
        if (!player || !item || item->Class != ITEM_CLASS_GLYPH || EraGlyphGate::Allowed(player))
            return true;
        result = EQUIP_ERR_CANT_DO_RIGHT_NOW;
        return false;
    }

    void OnPlayerLogin(Player* player) override { EraGlyphGate::StripIfDisallowed(player); }

    void OnPlayerAfterSpecSlotChanged(Player* player, uint8 /*newSlot*/) override
    {
        EraGlyphGate::StripIfDisallowed(player);
    }
};

// Core shapeshift handling and spec activation can recast stored glyph auras.
// Reject those casts before effects execute, while keeping the player's earned
// ownership arrays intact.
class era_glyph_spell_gate : public AllSpellScript
{
public:
    era_glyph_spell_gate() : AllSpellScript("era_glyph_spell_gate") {}

    [[nodiscard]] bool CanPrepare(Spell* spell, SpellCastTargets const* /*targets*/,
                                  AuraEffect const* /*triggeredByAura*/) override
    {
        if (!spell || !spell->GetCaster())
            return true;
        Player* player = spell->GetCaster()->ToPlayer();
        return !player || EraGlyphGate::Allowed(player) ||
               !EraGlyphGate::IsOwnedGlyphSpell(player, spell->GetSpellInfo()->Id);
    }
};

void AddSC_era_glyph_gate()
{
    new era_glyph_gate();
    new era_glyph_spell_gate();
}
