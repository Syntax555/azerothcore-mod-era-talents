#ifndef MOD_ERA_TALENT_IP_H
#define MOD_ERA_TALENT_IP_H
#include "Define.h"
class Player;
enum EraId : uint8 { ERA_VANILLA = 0, ERA_TBC = 1, ERA_WOTLK = 2 };
EraId EraFromIP(Player* p);   // character earned era, clamped by Individual Progression

// Vanilla and TBC use authored historical trees; Wrath uses the native client tree.
// Existing classes with no authored old-era trees retain their native talent data.
bool EraHasTalentTrees(EraId era);
bool EraHasTalentTrees(Player* player, EraId era);

#endif
