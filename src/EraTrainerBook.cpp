/*
 * This file is part of the AzerothCore Project. See AUTHORS file for Copyright information
 *
 * This program is free software; you can redistribute it and/or modify it
 * under the terms of the GNU General Public License as published by the
 * Free Software Foundation; either version 2 of the License, or (at your
 * option) any later version.
 */

#include "EraTrainerBook.h"

#include <algorithm>
#include <array>
#include <stdexcept>
#include <unordered_map>
#include <unordered_set>

#include "DBCStores.h"
#include "EraTalentBots.h"
#include "EraTalentContent.h"
#include "EraTalentIP.h"
#include "NPCPackets.h"
#include "ObjectMgr.h"
#include "Player.h"
#include "ScriptMgr.h"
#include "SpellInfo.h"
#include "SpellMgr.h"
#include "Trainer.h"

namespace
{
// Talent tabs in TalentTab.dbc order, so a book tree matches GetTalentTabInfo on the client.
constexpr std::array<std::array<uint32, 3>, MAX_CLASSES> kTreeSkills = {{
    {},
    { SKILL_ARMS, SKILL_FURY, SKILL_PROTECTION },
    { SKILL_HOLY2, SKILL_PROTECTION2, SKILL_RETRIBUTION },
    { SKILL_BEAST_MASTERY, SKILL_MARKSMANSHIP, SKILL_SURVIVAL },
    { SKILL_ASSASSINATION, SKILL_COMBAT, SKILL_SUBTLETY },
    { SKILL_DISCIPLINE, SKILL_HOLY, SKILL_SHADOW },
    { SKILL_DK_BLOOD, SKILL_DK_FROST, SKILL_DK_UNHOLY },
    { SKILL_ELEMENTAL_COMBAT, SKILL_ENHANCEMENT, SKILL_RESTORATION },
    { SKILL_ARCANE, SKILL_FIRE, SKILL_FROST },
    { SKILL_AFFLICTION, SKILL_DEMONOLOGY, SKILL_DESTRUCTION },
    {},
    { SKILL_BALANCE, SKILL_FERAL_COMBAT, SKILL_RESTORATION2 },
}};

uint8 BookTree(uint8 classId, uint32 spellId)
{
    if (classId >= MAX_CLASSES)
        return 0;
    SkillLineAbilityMapBounds abilities = sSpellMgr->GetSkillLineAbilityMapBounds(spellId);
    for (auto ability = abilities.first; ability != abilities.second; ++ability)
        for (uint8 tree = 0; tree < 3; ++tree)
            if (kTreeSkills[classId][tree] && ability->second->SkillLine == kTreeSkills[classId][tree])
                return tree + 1;
    return 0;
}

// Stock talents come from Talent.dbc; historical ones are the era tree's own rank spells.
bool IsTalentSpell(Player* player, EraId era, uint32 spellId)
{
    if (GetTalentSpellCost(spellId) || sSpellMgr->IsAdditionalTalentSpell(spellId))
        return true;
    for (EraTalentNode const* node : sEraTalentContent->NodesFor(uint8(era), player->getClass()))
        for (uint32 rankSpell : node->rankSpell)
            if (rankSpell && rankSpell == spellId)
                return true;
    return false;
}

// A trainer's quote before its creature's reputation discount; the cost hook ignores the trainer.
uint32 BaseCost(Player* player, Trainer::Spell const& spell)
{
    uint32 cost = spell.MoneyCost;
    sScriptMgr->OnPlayerGetTrainerSpellCost(player, nullptr, spell.SpellId, cost);
    return cost;
}

// The trainer window's list for these trainers: its packet entries go through the same list hook,
// which judges the character and not the creature, and the survivors map back to their rows.
std::vector<Trainer::Spell const*> ListedSpells(Player* player, std::vector<Trainer::Trainer const*> const& trainers)
{
    // One row per spell, the lowest level any of these trainers asks for, in trainer order.
    std::vector<std::pair<Trainer::Trainer const*, Trainer::Spell const*>> rows;
    std::unordered_map<uint32, size_t> placed;
    for (Trainer::Trainer const* trainer : trainers)
    {
        if (!trainer->IsTrainerValidForPlayer(player))
            continue;
        for (Trainer::Spell const& spell : trainer->GetSpells())
        {
            if (!player->IsSpellFitByClassAndRace(spell.SpellId))
                continue;
            auto [slot, fresh] = placed.emplace(spell.SpellId, rows.size());
            if (fresh)
                rows.emplace_back(trainer, &spell);
            else if (spell.ReqLevel < rows[slot->second].second->ReqLevel)
                rows[slot->second] = { trainer, &spell };
        }
    }
    WorldPackets::NPC::TrainerList list;
    for (auto const& [trainer, spell] : rows)
    {
        WorldPackets::NPC::TrainerListSpell& entry = list.Spells.emplace_back();
        entry.SpellID = spell->SpellId;
        // The state itself is private to the trainer; this is what its public checks show.
        entry.Usable = AsUnderlyingType(trainer->CanTeachSpell(player, spell) ? Trainer::SpellState::Available
                                        : player->HasSpell(spell->SpellId)    ? Trainer::SpellState::Known
                                                                              : Trainer::SpellState::Unavailable);
        entry.MoneyCost = int32(BaseCost(player, *spell));
        entry.ReqLevel = spell->ReqLevel;
        entry.ReqSkillLine = spell->ReqSkillLine;
        entry.ReqSkillRank = spell->ReqSkillRank;
        std::copy(spell->ReqAbility.begin(), spell->ReqAbility.end(), entry.ReqAbility.begin());
    }
    sScriptMgr->OnPlayerBeforeReceiveSpellListFromTrainer(player, nullptr, list);
    std::vector<Trainer::Spell const*> listed;
    for (WorldPackets::NPC::TrainerListSpell const& entry : list.Spells)
        if (auto slot = placed.find(uint32(entry.SpellID)); slot != placed.end())
            listed.push_back(rows[slot->second].second);
    return listed;
}

std::vector<EraTrainerBook::Entry> Book(Player* player, std::vector<Trainer::Trainer const*> const& trainers)
{
    std::vector<EraTrainerBook::Entry> book;
    EraId era = EraTalentBots::EraFor(player);
    std::unordered_map<uint32, size_t> placed;
    for (Trainer::Spell const* spell : ListedSpells(player, trainers))
    {
        uint32 cost = BaseCost(player, *spell);
        std::vector<uint32> taught;
        for (SpellEffectInfo const& effect : sSpellMgr->AssertSpellInfo(spell->SpellId)->GetEffects())
            if (effect.IsEffect(SPELL_EFFECT_LEARN_SPELL) && effect.TriggerSpell)
                taught.push_back(effect.TriggerSpell);
        if (taught.empty())
            taught.push_back(spell->SpellId);
        for (uint32 spellId : taught)
        {
            EraTrainerBook::Entry entry;
            entry.level = spell->ReqLevel;
            entry.spellId = spellId;
            entry.cost = cost;
            entry.previousRank = sSpellMgr->GetPrevSpellInChain(spellId);
            uint32 root = sSpellMgr->GetFirstSpellInChain(spellId);
            if (root && root != spellId && IsTalentSpell(player, era, root))
                entry.talent = root;
            for (uint32 ability : spell->ReqAbility)
                if (!entry.required && ability && ability != entry.previousRank && ability != entry.talent)
                    entry.required = ability;
            for (auto const& [learned, required] : sSpellMgr->GetSpellsRequiredForSpellBounds(spell->SpellId))
                if (!entry.required && required != entry.previousRank && required != entry.talent)
                    entry.required = required;
            entry.tree = BookTree(player->getClass(), spellId);
            auto [slot, fresh] = placed.emplace(spellId, book.size());
            if (fresh)
                book.push_back(entry);
            else if (entry.level < book[slot->second].level)
                book[slot->second] = entry;
        }
    }
    std::sort(book.begin(), book.end(), [](EraTrainerBook::Entry const& a, EraTrainerBook::Entry const& b)
              { return a.level != b.level ? a.level < b.level : a.spellId < b.spellId; });
    return book;
}
}  // namespace

namespace EraTrainerBook
{
std::vector<Entry> ClassBook(Player* player)
{
    if (!player)
        return {};
    try
    {
        return Book(player, sObjectMgr->GetClassTrainers(player->getClass()));
    }
    catch (std::out_of_range const&)
    {
        return {};  // A world database without trainers for this class.
    }
}

std::vector<Entry> RidingBook(Player* player)
{
    if (!player)
        return {};
    std::vector<Trainer::Trainer const*> trainers;
    std::unordered_set<Trainer::Trainer const*> seen;
    for (auto const& [entry, creature] : *sObjectMgr->GetCreatureTemplates())
    {
        Trainer::Trainer const* trainer = sObjectMgr->GetTrainer(entry);
        if (trainer && trainer->GetTrainerType() == Trainer::Type::Mount && seen.insert(trainer).second)
            trainers.push_back(trainer);
    }
    return Book(player, trainers);
}
}  // namespace EraTrainerBook
