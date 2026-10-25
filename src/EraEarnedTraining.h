#ifndef MOD_ERA_EARNED_TRAINING_H
#define MOD_ERA_EARNED_TRAINING_H

#include <vector>

#include "EraTalentIP.h"

class Player;

namespace EraEarnedTraining
{
// Snapshot only spells the character actually knows before a transition/reset.
std::vector<uint32> Snapshot(Player* player);
void Restore(Player* player, EraId era, std::vector<uint32> const& acquired);
bool CanTrain(Player* player, EraId era, uint32 spellId);
}  // namespace EraEarnedTraining

#endif
