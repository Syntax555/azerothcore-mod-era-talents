#ifndef MOD_ERA_TRAINER_BOOK_H
#define MOD_ERA_TRAINER_BOOK_H

#include <vector>

#include "Define.h"

class Player;

namespace EraTrainerBook
{
// A spell a trainer lists for the character, as a spellbook shows it before it is learned.
struct Entry
{
    uint32 level = 0;
    uint32 spellId = 0;       // The spell learned, not a trainer's teaching wrapper.
    uint32 cost = 0;          // Before the trainer's reputation discount.
    uint32 previousRank = 0;
    uint32 talent = 0;        // The talent the rank chain starts from.
    uint32 required = 0;      // Another spell that must be known first.
    uint8 tree = 0;           // Talent tab 1-3; 0 for the general book.
};

// What the character's class trainers list for it, filtered exactly as the trainer window is.
std::vector<Entry> ClassBook(Player* player);
// The same for riding trainers, which only creatures reach.
std::vector<Entry> RidingBook(Player* player);
}  // namespace EraTrainerBook

#endif
