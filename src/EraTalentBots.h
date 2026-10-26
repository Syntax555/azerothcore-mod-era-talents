#ifndef MOD_ERA_TALENT_BOTS_H
#define MOD_ERA_TALENT_BOTS_H
#include "EraTalentIP.h"
class Player;

namespace EraTalentBots
{
    // True for a playerbot without its own client (session flag OR attached AI — see the .cpp
    // comment on login order). A SelfBot is a human player.
    bool IsBot(Player* p);

    // Humans and bots use the same actually earned IP milestones. Level only determines
    // the point budget and never unlocks expansion talents or class spells.
    EraId BotEra(Player* bot);
    EraId EraFor(Player* p);

    // THE "is this character's talent set era-managed" rule (its Vanilla/TBC era tree replaces
    // its native talents): module enabled, not a bot while EraTalents.BotTalents is off, and
    // EraFor(p)'s era has authored trees. Shared by the spec-tab bridge and inspect
    // (EraTalentsComms) so the two can never disagree. Exists in EVERY build (IsBot is false
    // without playerbots, so it reduces to the real-player rule).
    bool IsEraManaged(Player* p);

    // Extend a random bot's existing build with newly level-earned points; an altbot keeps its
    // points for its owner. An actual expansion transition refunds the previous tree once in
    // EraTransition; routine refreshes retain it.
    // Returns true while a managed era or pending transition owns the talent pool.
    bool FactoryReconcile(Player* bot, int specTab);

    void OnBotLogin(Player* bot);          // re-grant persisted era passives from startup cache
    void OnBotLevelChanged(Player* bot);   // spend new points after earned transitions
    void OnLogout(Player* p);              // drop the spec-tab cache entry (players: no-op erase)
    void InvalidateSpecCache(Player* p);   // era rows changed outside this unit (player TryLearn/
                                           // Reset) — the spec-tab bridge serves players too
}

#ifdef MOD_PLAYERBOTS
// Only the playerbots patches call these; they exist only when mod-playerbots is compiled in.
// C++-linkage bridges for fork patch 0020. Each is declared extern in the patched fork file
// with this EXACT signature — keep in sync with the patch or the fork fails to link.
//
// PlayerbotFactory::InitTalentsTree: era build instead of the WotLK template (see .cpp).
bool EraTalentBots_FactoryReconcile(Player* bot, int specTab);
// AiFactory::GetPlayerSpecTabs: a managed-era character's talents live in era_character_talent,
// not the native talent map (stripped by the era system) — every spec consumer
// (GetPlayerSpecTab, IsTank/IsHeal, ResetStrategies, StatsWeightCalculator gear scoring, raid
// triggers) counts native talents and would read the character as untalented. This reports the
// era build's per-tab points instead — for BOTS and for era-managed real PLAYERS (the master's
// role auto-detect in .raidroster login reads IsTank/IsHeal(master); an era player otherwise
// reads as tab 0 — a Shadow-built priest master was detected as the group healer). tabs3 =
// uint32[3], written only on a true return. CACHED per guid (GetPlayerSpecTabs runs on
// per-second AI paths; era rows are a DB read — one query per character per session,
// invalidated on every era-row mutation: bot paths in EraTalentBots, player TryLearn/Reset via
// InvalidateSpecCache, and logout).
// Returns false (native path) for unmanaged bands, no rows, or (bots) knob off.
bool EraTalentBots_SpecTabs(Player* bot, uint32* tabs3);
// Stable authored random-druid intent: 1 = bear, 3 = cat, -1 = no seeded feral role.
int EraTalentBots_FeralSpec(Player* bot);
// Era-transparent spell lookup for the bot AI's hardcoded stock-id tables (patch 0021).
// Semantics: the spell id this character KNOWS for stock spell `stockSpellId` —
//   * knows the stock id itself -> stockSpellId (native bots, WotLK band, knob off);
//   * managed-era bot that doesn't -> the highest-id KNOWN same-name spell in the era
//     custom band [920000, 950000) (era clones keep stock names; ids ascend with rank),
//     passives included (Thick Hide-style discriminators need them);
//   * otherwise 0 ("doesn't know it", exactly like a false HasSpell).
// So `if (Resolve(bot, id))` is a drop-in for `if (bot->HasSpell(id))`, and the result is
// the id to cast/compare (totem UNIT_CREATED_BY_SPELL identity checks included). CACHED
// per (guid, stockId) — hot AI paths never re-scan; invalidated with the spec-tab cache.
uint32 EraTalentBots_ResolveSpellId(Player* bot, uint32 stockSpellId);
#endif   // MOD_PLAYERBOTS

#endif
