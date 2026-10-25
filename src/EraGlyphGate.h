/*
 * This file is part of the AzerothCore Project. See AUTHORS file for Copyright
 * information
 *
 * This program is free software; you can redistribute it and/or modify it
 * under the terms of the GNU General Public License as published by the
 * Free Software Foundation; either version 2 of the License, or (at your
 * option) any later version.
 */

#ifndef MOD_ERA_GLYPH_GATE_H
#define MOD_ERA_GLYPH_GATE_H

#include "Define.h"
class Player;

namespace EraGlyphGate
{
// Glyph effects and new glyph purchases are available after the earned Wrath
// transition. Existing hero-class characters and disabled gates retain ordinary
// core behavior.
bool Allowed(Player* player);
bool IsOwnedGlyphSpell(Player* player, uint32 spellId);

// Hide/suppress early-era glyphs without modifying either spec's persisted
// ownership. Once allowed, restore the active spec's owned slots and ordinary
// glyph effects.
void StripIfDisallowed(Player* player);
}  // namespace EraGlyphGate

#endif
