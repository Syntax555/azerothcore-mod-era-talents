#include "EraTalentIP.h"

#include "EraTalentContent.h"
#include "IndividualProgression.h"
#include "Player.h"

EraId EraFromIP(Player* p)
{
    if (!p)
        return ERA_WOTLK;
    uint8 const era = IndividualProgression_GetEarnedEra(p);
    return era <= ERA_WOTLK ? EraId(era) : ERA_VANILLA;
}

bool EraHasTalentTrees(EraId era)
{
    // Vanilla + TBC trees are authored and shipped (all nine TBC classes real-client signed off
    // 2026-09-05). Add ERA_WOTLK only if WotLK trees are ever authored — until then a WotLK
    // character keeps the native talent frame; see the header for why.
    return era == ERA_VANILLA || era == ERA_TBC;
}

bool EraHasTalentTrees(Player* player, EraId era)
{
    return player && EraHasTalentTrees(era) && !sEraTalentContent->NodesFor(uint8(era), player->getClass()).empty();
}
