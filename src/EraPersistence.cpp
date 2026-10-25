#include "EraPersistence.h"

#include <algorithm>
#include <chrono>
#include <deque>
#include <memory>
#include <mutex>
#include <utility>

#include "DatabaseEnv.h"
#include "Log.h"
#include "Transaction.h"

namespace
{
constexpr std::size_t MaxSnapshotsPerTransaction = 100;
std::mutex g_queueMutex;
std::deque<std::vector<std::string>> g_pending;

// These are touched only by the world update/shutdown thread. Keeping a failed batch at
// the front prevents a retry from overtaking a later reset, allocation, or era stamp.
std::unique_ptr<TransactionCallback> g_inFlight;
std::size_t g_submitted = 0;
bool g_reportedFailure = false;
std::chrono::steady_clock::time_point g_retryAfter;

void Submit()
{
    CharacterDatabaseTransaction transaction = CharacterDatabase.BeginTransaction();
    {
        std::lock_guard<std::mutex> guard(g_queueMutex);
        g_submitted = std::min(MaxSnapshotsPerTransaction, g_pending.size());
        for (std::size_t i = 0; i < g_submitted; ++i)
            for (std::string const& statement : g_pending[i])
                transaction->Append(statement);
    }
    if (!g_submitted)
        return;

    g_inFlight = std::make_unique<TransactionCallback>(CharacterDatabase.AsyncCommitTransaction(transaction));
    g_inFlight->AfterComplete(
        [](bool success)
        {
            if (success)
            {
                std::lock_guard<std::mutex> guard(g_queueMutex);
                for (std::size_t i = 0; i < g_submitted; ++i)
                    g_pending.pop_front();
                g_reportedFailure = false;
            }
            else if (!g_reportedFailure)
            {
                LOG_ERROR("module",
                          "[mod-era-talents] character persistence failed; retaining and retrying the ordered batch");
                g_reportedFailure = true;
            }
            if (!success)
                g_retryAfter = std::chrono::steady_clock::now() + std::chrono::seconds(5);
        });
}
}  // namespace

namespace EraPersistence
{
void Queue(std::vector<std::string> statements)
{
    if (statements.empty())
        return;
    std::lock_guard<std::mutex> guard(g_queueMutex);
    g_pending.push_back(std::move(statements));
}

void Update()
{
    if (g_inFlight)
    {
        if (!g_inFlight->InvokeIfReady())
            return;
        g_inFlight.reset();
    }
    if (std::chrono::steady_clock::now() >= g_retryAfter)
        Submit();
}

void Flush()
{
    // Players/maps have stopped mutating before OnAfterUnloadAllMaps/OnShutdown. No
    // callback retains a Player pointer, so a logout never cancels an earned DB change.
    Update();
    if (!g_inFlight)
        Submit();  // shutdown bypasses the normal retry delay for one final attempt
    while (g_inFlight)
    {
        g_inFlight->m_future.wait();
        g_inFlight->InvokeIfReady();
        g_inFlight.reset();
        if (g_reportedFailure)
        {
            LOG_ERROR("module",
                      "[mod-era-talents] shutdown could not persist character talent changes; check character database "
                      "errors");
            return;
        }
        Submit();
    }
}
}  // namespace EraPersistence
