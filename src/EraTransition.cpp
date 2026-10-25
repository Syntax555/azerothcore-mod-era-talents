#include "EraTransition.h"

#include <mutex>
#include <unordered_map>
#include <unordered_set>

#include "DatabaseEnv.h"
#include "EraEarnedTraining.h"
#include "EraGlyphGate.h"
#include "EraPersistence.h"
#include "EraTalents.h"
#include "EraTalentsComms.h"
#include "EraTalentsConfig.h"
#include "Field.h"
#include "Log.h"
#include "Player.h"
#include "QueryResult.h"
#include "ScriptMgr.h"

namespace
{
std::unordered_map<uint32, EraId> g_storedEra;
std::mutex g_storedEraMutex;
thread_local std::unordered_set<uint32> g_nativeResets;

class NativeResetScope
{
public:
    explicit NativeResetScope(Player* p)
        : _guid(p->GetGUID().GetCounter()), _inserted(g_nativeResets.insert(_guid).second)
    {
    }
    ~NativeResetScope()
    {
        if (_inserted)
            g_nativeResets.erase(_guid);
    }

private:
    uint32 _guid;
    bool _inserted;
};

    std::unordered_map<ObjectGuid, EraId> g_pending;   // deferred target era while in combat
    std::mutex g_pendingMutex;   // Detect/FlushCombat run per-player inside Map::Update — maps
                                 // tick in parallel, so this shared map needs the same locking
                                 // as the era caches (prod rehash-race segfault, 2026-08-26)
}

namespace EraTransition
{
void LoadCache()
{
    std::unordered_map<uint32, EraId> loaded;
    if (QueryResult result = CharacterDatabase.Query("SELECT guid,lastEra FROM era_talent_char_state"))
    {
        do
        {
            Field* fields = result->Fetch();
            uint8 era = fields[1].Get<uint8>();
            if (era <= ERA_WOTLK)
                loaded.emplace(fields[0].Get<uint32>(), EraId(era));
        } while (result->NextRow());
    }
    std::lock_guard<std::mutex> guard(g_storedEraMutex);
    g_storedEra = std::move(loaded);
}

    EraId StoredEra(Player* p)
    {
        if (!p)
            return ERA_WOTLK;
        std::lock_guard<std::mutex> guard(g_storedEraMutex);
        auto it = g_storedEra.find(p->GetGUID().GetCounter());
        if (it != g_storedEra.end())
            return it->second;
        return EraFromIP(p);   // first sighting: adopt current era, no reset
    }

    void SetStoredEra(Player* p, EraId era)
    {
        if (!p)
            return;
        uint32 guid = p->GetGUID().GetCounter();
        std::lock_guard<std::mutex> guard(g_storedEraMutex);
        auto [it, inserted] = g_storedEra.try_emplace(guid, era);
        if (!inserted && it->second == era)
            return;
        it->second = era;
        EraPersistence::Queue({"REPLACE INTO era_talent_char_state (guid,lastEra) VALUES (" + std::to_string(guid) +
                               "," + std::to_string(uint32(era)) + ")"});
    }

    bool NativeResetActive(Player* p) { return p && g_nativeResets.count(p->GetGUID().GetCounter()) != 0; }

    static void Pin(Player* p, EraId era)
    {
        if (EraHasTalentTrees(p, era))
        {
            p->SetFreeTalentPoints(0);
            p->SendTalentsInfoData(false);
        }
    }

    // Core resetTalents(true) only wipes the ACTIVE spec (it skips any talent whose specMask lacks
    // GetActiveSpecMask()). A WotLK dual-spec character down-transitioned into a managed era therefore
    // keeps stock talents in its INACTIVE spec — and a later spec switch makes m_usedTalentCount
    // nonzero, so a trainer reset would then run BOTH the pin hook's charge AND the core's (double
    // charge / era-reset-paid-but-native-reset-refused), and the inactive spec would hand an era
    // character live WotLK talents. Reset EVERY spec so no native talent survives in either.
    //
    // The dual-spec STRUCTURE is deliberately preserved (specsCount unchanged): a managed era hides
    // and pins the native talent frame, so the second spec is merely dormant plumbing, and an
    // up-transition back to WotLK restores both specs to re-spend (this doesn't strip a thing IP
    // otherwise permits — IP does not gate dual spec by era). ActivateSpec is the battle-tested
    // per-spec teardown/apply path (the dual-spec trainer's own flow); Run() only reaches this branch
    // out of combat (it defers in-combat), which is exactly ActivateSpec's precondition. A single-spec
    // character takes the same path resetTalents(true) always did.
    static void ResetAllSpecs(Player* p)
    {
        NativeResetScope nativeReset(p);
        uint8 const specs = p->GetSpecsCount();
        if (specs <= 1)
        {
            p->resetTalents(true);
            return;
        }

        uint8 const original = p->GetActiveSpec();
        for (uint8 s = 0; s < specs; ++s)
        {
            if (p->GetActiveSpec() != s)
                p->ActivateSpec(s);
            p->resetTalents(true);   // clears the now-active spec; era re-entry into the pin hook stays inert
        }
        if (p->GetActiveSpec() != original)
            p->ActivateSpec(original);   // leave them on the spec they had active (both are empty now)
    }

    // Heals characters that PREDATE the mod. StoredEra()'s first-sighting fallback adopts the
    // current era with no reset, so a character that leveled with native WotLK talents and was
    // ALREADY inside a managed era when the mod first deployed got stamped without ever
    // crossing — Run()'s down-transition reset never fires for it, and its stock talents stay
    // live under the era trees (a Vanilla priest still proccing Body and Soul). Called from the
    // same-era login path (bot-gated by the caller, and login is never in combat); inert for any
    // character with no live core talent — every normal era char — so it doubles as a permanent
    // backstop against any future path that leaks native talents into a managed era.
    void StripNativeTalents(Player* p, EraId era)
    {
        if (!p || !sEraTalentsConfig->Enabled() || !EraHasTalentTrees(p, era))
            return;

        bool leaked = false;
        for (auto const& [spellId, talent] : p->GetTalentMap())
            if (talent->State != PLAYERSPELL_REMOVED)
            {
                leaked = true;
                break;
            }
        if (!leaked)
            return;

        ResetAllSpecs(p);   // every spec, same as the down-transition path (see ResetAllSpecs)
        Pin(p, era);
        LOG_INFO("module", "[mod-era-talents] stripped leaked native talents from {} (pre-mod character in a managed era)",
                 p->GetName());
    }

    void Run(Player* p, EraId from, EraId to)
    {
        if (!p || !sEraTalentsConfig->Enabled())
            return;

        // A deferred combat target or a stale caller must never authorize a new tree. The
        // character's currently earned IP milestones, for humans and bots, are authoritative.
        if (to != EraFromIP(p))
            return;
        from = StoredEra(p);

        if (p->IsInCombat())
        {
            std::lock_guard<std::mutex> guard(g_pendingMutex);
            g_pending[p->GetGUID()] = to;   // don't mutate spellbook mid-fight; flush on leave-combat
            return;
        }

        // Mutate talents ONLY on an actual era crossing. A same-era call (every login, and the
        // first sighting of a new char) must NOT reset — the caller's pin()/ReapplyOnLogin do the
        // idempotent re-grant. Without this guard a plain login would wipe a WotLK main's tree
        // (resetTalents) or delete an era char's spent talents (Reset's DELETE).
        if (from != to)
        {
            auto earnedSpells = EraEarnedTraining::Snapshot(p);
            bool const fromManaged = EraHasTalentTrees(p, from);
            bool const toManaged = EraHasTalentTrees(p, to);

            // A real expansion crossing refunds only the departing historical tree. Ordinary
            // login, level gains, and factory maintenance retain the existing allocated build.
            if (fromManaged)
                EraTalents::Reset(p, from);

            if (toManaged)
            {
                // Entering a managed era: clear any stock WotLK talents so the era char starts
                // clean, in EVERY spec (a dual-spec char keeps talents in the inactive one otherwise
                // — see ResetAllSpecs). Points are then pinned to 0 by Pin() + the deferred-zero PlayerScript.
                ResetAllSpecs(p);
                Pin(p, to);   // deferred-zero PlayerScript keeps it pinned thereafter
            }
            else if (fromManaged)
            {
                // Leaving a historical tree for Wrath: restore the native frame and the
                // talent pool earned through the character's actual levels. resetTalents
                // only REFUNDS spent core talents — an era char has none (its talents were era
                // passives), and its core pool was pinned to 0, so refunding leaves 0.
                // InitTalentForLevel() re-grants the pool (points stick: the target era is not
                // managed, so the pin hook's OnPlayerFreeTalentPointsChanged bails instead of zeroing).
                NativeResetScope nativeReset(p);
                p->resetTalents(true);
                p->InitTalentForLevel();
                p->SendTalentsInfoData(false);
            }
            // A class with no authored historical tree stays native and keeps its existing spec.

            // Publish the settled stamp before callbacks reconcile or describe the new tree.
            // The talent refund above has completed, so a second Detect cannot reset it again.
            SetStoredEra(p, to);

            // Tell the addon the era flipped so it swaps panels live (no relog). Safe on login
            // too — the addon just re-parses; on a real crossing this is what updates isEraChar.
            EraTalentsComms::SendSync(p);

            // Reconcile the new era's ownership rules and translate only spell variants that
            // this character actually acquired before crossing. New usable ranks stay paid.
            EraTalents::ReconcileBaselineSpells(p, to);
            EraEarnedTraining::Restore(p, to, earnedSpells);

            if (sEraTalentsConfig->Debug())
                LOG_INFO("module", "[mod-era-talents] transition {}->{} for {}", uint8(from), uint8(to), p->GetName());
        }

        // Persist the era stamp in BOTH cases (crossing AND same-era). This is what lets a LATER
        // crossing be detected: StoredEra() falls back to the live IP era when no row exists, so
        // if we never persisted, stored would always equal now and a real crossing would be missed.
        SetStoredEra(p, to);

        // Suppress saved glyph effects before Wrath; restore the owned effects when earned.
        // The glyph reconciler retains saved IDs and never consumes inventory.
        EraGlyphGate::StripIfDisallowed(p);
    }

    bool Detect(Player* p)
    {
        if (!p || !sEraTalentsConfig->Enabled())
            return false;
        EraId stored = StoredEra(p);
        EraId now = EraFromIP(p);
        if (stored != now)
        {
            bool applied = !p->IsInCombat();
            Run(p, stored, now);
            return applied;
        }
        return false;
    }

    void FlushCombat(Player* p)
    {
        if (!p)
            return;
        {
            std::lock_guard<std::mutex> guard(g_pendingMutex);
            auto it = g_pending.find(p->GetGUID());
            if (it == g_pending.end())
                return;
            g_pending.erase(it);
        }
        Run(p, StoredEra(p), EraFromIP(p));  // revalidate earned state after combat, outside the lock
    }

    void OnLogout(Player* p)
    {
        if (!p)
            return;
        std::lock_guard<std::mutex> guard(g_pendingMutex);
        g_pending.erase(p->GetGUID());
        // Keep g_storedEra: an immediate relog must observe the latest queued era stamp,
        // rather than reread an older DB row while the transaction is still in flight.
    }

    void DeleteCache(uint32 guid)
    {
        std::lock_guard<std::mutex> guard(g_storedEraMutex);
        g_storedEra.erase(guid);
        EraPersistence::Queue({"DELETE FROM era_talent_char_state WHERE guid=" + std::to_string(guid)});
    }
}
