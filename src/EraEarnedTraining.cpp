/*
 * This file is part of the AzerothCore Project. See AUTHORS file for Copyright information
 *
 * This program is free software; you can redistribute it and/or modify it
 * under the terms of the GNU General Public License as published by the
 * Free Software Foundation; either version 2 of the License, or (at your
 * option) any later version.
 */

#include "EraEarnedTraining.h"

#include <algorithm>
#include <limits>

#include "DBCStores.h"
#include "EraBandClassifier.h"
#include "EraEarnedTrainingData.gen.h"
#include "EraTalentBots.h"
#include "EraTalents.h"
#include "EraTalentsConfig.h"
#include "EraTransition.h"
#include "NPCPackets.h"
#include "Player.h"
#include "ScriptMgr.h"
#include "SpellMgr.h"
#include "Trainer.h"

namespace
{
uint32 ChainRoot(uint32 spellId)
{
    uint32 first = sSpellMgr->GetFirstSpellInChain(spellId);
    return first ? first : spellId;
}

bool QuestTotemEarned(Player* player, uint32 spellId)
{
    if (player->getClass() != CLASS_SHAMAN)
        return true;
    uint32 root = ChainRoot(spellId);
    for (EraTalents::QuestTotem const& totem : EraTalents::kQuestTotems)
    {
        uint32 const variants[] = { totem.stockId, totem.vanillaId, totem.tbcId };
        bool matches = false;
        for (uint32 variant : variants)
            matches = matches || (variant && variant == root);
        if (!matches)
            continue;
        for (uint32 quest : totem.quests)
            if (quest && player->GetQuestRewardStatus(quest))
                return true;
        for (uint32 variant : variants)
            if (variant && player->HasSpell(variant))
                return true;
        return false;
    }
    return true;
}

bool StockTalentGate(Player* player, EraId era, uint32 spellId)
{
    uint32 root = ChainRoot(spellId);
    if (era == ERA_WOTLK)
        return true;
    uint32 node = 0;
    switch (root)
    {
        case 45438:  // Ice Block became baseline in TBC.
            if (era == ERA_VANILLA)
                node = 18046;
            break;
        case 15237:
            node = era == ERA_VANILLA ? 18121 : 20527;
            break;
        case 14752:
        case 27681:
            node = era == ERA_VANILLA ? 18113 : 20513;
            break;
        case 20217:
        case 25898:
            node = era == ERA_VANILLA ? 18620 : 20025;
            break;
        case 26573:
            if (era == ERA_VANILLA)
                node = 18606;
            break;
        case 16857:
            node = era == ERA_VANILLA ? 18729 : 20133;
            break;
        case 23922:
        case 16689:
        case 5229:
        case 19263:
        case 10321:        // Stock Judgement trainer wrapper.
            return false;  // These eras train their explicit custom replacement instead.
        default:
            break;
    }
    return !node || EraTalents::CurrentRank(player, era, node) > 0;
}

bool FactionAllowed(Player* player, uint32 spellId)
{
    if (spellId == 946080 || spellId == 53736)
        return player->GetTeamId() == TEAM_HORDE;
    if (spellId == 946084 || spellId == 31801)
        return player->GetTeamId() == TEAM_ALLIANCE;
    return true;
}

bool VariantAllowed(Player* player, EraId era, uint32 spellId)
{
    if (!FactionAllowed(player, spellId) || !StockTalentGate(player, era, spellId))
        return false;
    bool mapped = false;
    for (auto const& variant : EraEarnedTrainingData::kVariants)
    {
        if (variant.classId != player->getClass())
            continue;
        bool member = false;
        for (uint32 candidate : variant.spell)
            member = member || (candidate && candidate == spellId);
        if (!member)
            continue;
        mapped = true;
        if (variant.spell[uint8(era)] == spellId)
            return true;
    }
    return !mapped;
}
}  // namespace

namespace EraEarnedTraining
{
std::vector<uint32> Snapshot(Player* player)
{
    std::vector<uint32> acquired;
    if (!player)
        return acquired;
    for (auto const& variant : EraEarnedTrainingData::kVariants)
    {
        if (variant.classId != player->getClass())
            continue;
        for (uint32 spellId : variant.spell)
            if (spellId && player->HasSpell(spellId))
                acquired.push_back(spellId);
    }
    std::sort(acquired.begin(), acquired.end());
    acquired.erase(std::unique(acquired.begin(), acquired.end()), acquired.end());
    return acquired;
}

bool CanTrain(Player* player, EraId era, uint32 spellId)
{
    return player && uint8(era) <= uint8(ERA_WOTLK) && VariantAllowed(player, era, spellId) &&
           QuestTotemEarned(player, spellId);
}

void Restore(Player* player, EraId era, std::vector<uint32> const& acquired)
{
    if (!player || uint8(era) > uint8(ERA_WOTLK))
        return;
    bool changed = false;
    for (uint32 learned : acquired)
    {
        // Collapsed later-era ranks are ambiguous: convert to the lowest matching old rank.
        // A known rank never proves ownership of every old rank allowed at the current level.
        uint32 target = 0;
        uint8 requiredLevel = std::numeric_limits<uint8>::max();
        for (auto const& variant : EraEarnedTrainingData::kVariants)
        {
            if (variant.classId != player->getClass())
                continue;
            bool matches = false;
            for (uint32 candidate : variant.spell)
                matches = matches || (candidate && candidate == learned);
            uint32 candidate = variant.spell[uint8(era)];
            uint8 level = variant.minimumLevel[uint8(era)];
            if (matches && candidate && level < requiredLevel)
            {
                target = candidate;
                requiredLevel = level;
            }
        }
        if (!target || target == learned || player->HasSpell(target) || player->GetLevel() < requiredLevel ||
            !sSpellMgr->GetSpellInfo(target) || !VariantAllowed(player, era, target))
            continue;
        if (target >= EraTalents::ERA_CUSTOM_BAND_LOW && target < EraTalents::ERA_CUSTOM_BAND_HIGH)
        {
            if (!EraBandClassifier::IsLegit(EraBandClassifier::Classify(player, era, target).verdict))
                continue;
        }
        else
        {
            uint32 root = ChainRoot(target);
            if ((GetTalentSpellCost(root) || sSpellMgr->IsAdditionalTalentSpell(root)) && !player->HasSpell(root))
                continue;
        }
        player->learnSpell(target);
        changed = true;
    }
    if (changed)
        EraTalentBots::InvalidateSpecCache(player);  // Spell-id bridges must see variant changes immediately.
}
}  // namespace EraEarnedTraining

class era_earned_training : public PlayerScript
{
public:
    era_earned_training() : PlayerScript("era_earned_training") {}

    void OnPlayerGetTrainerSpellState(Player const* player, uint32 /*trainerId*/, uint32 spellId,
                                      Trainer::SpellState& state) override
    {
        if (!player || !sEraTalentsConfig->Enabled())
            return;
        Player* mutablePlayer = const_cast<Player*>(player);
        EraId era = EraTalentBots::EraFor(mutablePlayer);
        if (player->IsInCombat() || EraTransition::StoredEra(mutablePlayer) != era ||
            !EraEarnedTraining::CanTrain(mutablePlayer, era, spellId))
            state = Trainer::SpellState::Unavailable;
    }

    void OnPlayerBeforeReceiveSpellListFromTrainer(Player* player, Creature* /*trainer*/,
                                                   WorldPackets::NPC::TrainerList& list) override
    {
        if (!player || !sEraTalentsConfig->Enabled())
            return;
        EraId era = EraTalentBots::EraFor(player);
        auto invalid = [&](WorldPackets::NPC::TrainerListSpell const& spell)
        { return !EraEarnedTraining::CanTrain(player, era, uint32(spell.SpellID)); };
        list.Spells.erase(std::remove_if(list.Spells.begin(), list.Spells.end(), invalid), list.Spells.end());
    }
};

void AddSC_era_earned_training() { new era_earned_training(); }
