#ifndef MOD_ERA_PERSISTENCE_H
#define MOD_ERA_PERSISTENCE_H

#include <string>
#include <vector>

namespace EraPersistence
{
// Immutable SQL snapshots only. Call while holding the owning cache's mutation lock so
// snapshots of that cache enter the FIFO in the same order as the in-memory changes.
void Queue(std::vector<std::string> statements);
void Update();  // world thread: at most one ordered asynchronous transaction in flight
void Flush();   // world shutdown: wait for outstanding transactions before DB teardown
}  // namespace EraPersistence

#endif
