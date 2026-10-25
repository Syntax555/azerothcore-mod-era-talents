#ifndef MOD_ERA_TALENTS_H
#define MOD_ERA_TALENTS_H
#include "EraTalentIP.h"
#include <string>
#include <unordered_map>
class Player;
namespace EraTalents
{
void LoadCache();  // world startup: preload persistent rank state before map threads run
// The reserved era custom-spell band. HIGH moved 933000 -> 950000 for the TBC era (TBC node
// passives live at 936000-943999, TBC pets/helpers at 944000+; generator mirror:
// gen_era_talents.py CUSTOM_PASSIVE_BASE/END). Nothing occupies [933000, 936000).
constexpr uint32 ERA_CUSTOM_BAND_LOW = 920000;
constexpr uint32 ERA_CUSTOM_BAND_HIGH = 950000;

// Quest-taught first totems, shared by paid-training checks and the baseline reconcile.
// tbcId 0 = TBC keeps the stock id.
struct QuestTotem { uint32 stockId; uint32 vanillaId; uint32 tbcId; uint32 quests[3]; };
inline constexpr QuestTotem kQuestTotems[] = {
    { 8071, 931020, 947020, { 1518, 1521, 9451 } },  // Stoneskin      <- Call of Earth (Orc/Tauren/Draenei)
    { 3599, 931100,      0, { 1527, 9555,    0 } },  // Searing        <- Call of Fire   (TBC/WotLK: stock)
    { 5394, 931180, 947170, {   96, 9509,    0 } },  // Healing Stream <- Call of Water
};

int SpentPoints(Player* p, EraId era);
uint8 CurrentRank(Player* p, EraId era, uint32 talentId);
int AvailablePoints(Player* p, EraId era);
bool TryLearn(Player* p, uint32 talentId, std::string& err);
void Reset(Player* p, EraId era);           // strip passives + DELETE this era's rows
void ReapplyOnLogin(Player* p, EraId era);  // idempotent re-grant from stored rows

// World startup preloads existing ranks once. Map readers return copies under a mutex,
// and writes enqueue immutable FIFO SQL while holding the same mutation lock. State stays
// cached across logout so relog cannot race a pending write; character deletion evicts it.
std::unordered_map<uint32, uint8> Ranks(Player* p, EraId era);
void DeleteCache(uint32 guid);

// Deferred build writes preserve the incrementally earned rank state in one transaction.
// A scope updates the cache immediately, then reconciles the final spellbook once.
class BotBuildScope
{
public:
    BotBuildScope(Player* p, EraId era);
    ~BotBuildScope();
    BotBuildScope(BotBuildScope const&) = delete;
    BotBuildScope& operator=(BotBuildScope const&) = delete;

private:
    Player* _p;
    EraId _era;
    bool _active;
};

// Enforce era/talent ownership, retain hidden era mechanics, and translate only acquired
// spell variants. Baseline usable spells remain paid trainer purchases in every era.
void ReconcileBaselineSpells(Player* p, EraId era);

// TBC faction DPS seals (Task 5d): a paladin may hold ONLY the faction-appropriate seal —
// Blood Elf (Horde) => Seal of Blood (946080); Alliance => Seal of Vengeance (946084). Strips the
// wrong-faction seal by race if held. Must be callable from the BOT login path too: the factory
// trainer-walk (InitAvailableSpells) is class-only-gated (Trainer::IsTrainerValidForPlayer checks
// class, not faction) so it teaches a bot BOTH seals AFTER the mid-build reconcile has run — the
// login-time strip is what removes the wrong one in steady state. Safe for any paladin (no-op when
// the wrong seal isn't held); on a non-TBC character the band sweep (EraBandClassifier) strips every 946xxx seal as an
// allowlist era mismatch.
void StripWrongFactionTbcPalSeal(Player* p);
}
#endif
