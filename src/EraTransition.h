#ifndef MOD_ERA_TRANSITION_H
#define MOD_ERA_TRANSITION_H
#include "EraTalentIP.h"
class Player;
namespace EraTransition
{
void LoadCache();                           // world startup: preload all persisted era stamps
void Run(Player* p, EraId from, EraId to);  // full reset of `from`, pin/unpin for `to`
bool Detect(Player* p);                     // true only when an earned crossing is applied now
void FlushCombat(Player* p);                // apply a deferred transition on leave-combat
EraId StoredEra(Player* p);                 // era_talent_char_state.lastEra (default = EraFromIP)
void SetStoredEra(Player* p, EraId era);
void StripNativeTalents(Player* p, EraId era);  // same-era login backstop: wipe leaked core talents
bool NativeResetActive(Player* p);              // suppress the paid-era hook during native teardown
void OnLogout(Player* p);                       // drop transient combat state, retain persisted cache
void DeleteCache(uint32 guid);                  // actual character deletion, not ordinary logout
}
#endif
