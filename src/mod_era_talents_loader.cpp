#include "Config.h"
#include "EraBandClassifier.h"
#include "EraPersistence.h"
#include "EraTalentBots.h"
#include "EraTalentContent.h"
#include "EraTalents.h"
#include "EraTalentsConfig.h"
#include "EraTransition.h"
#include "Log.h"
#include "ScriptMgr.h"

void AddSC_era_talent_pin();
void AddSC_era_earned_training();
void AddSC_era_talents_comms();
void AddSC_era_talents_commandscript();
void AddSC_era_talent_proc_scripts();
void AddSC_era_talent_pet_scripts();
void AddSC_era_talent_totem_scripts();
void AddSC_era_glyph_gate();

class era_talents_worldscript : public WorldScript
{
public:
    era_talents_worldscript() : WorldScript("era_talents_worldscript") {}
    void OnAfterConfigLoad(bool /*reload*/) override { sEraTalentsConfig->Load(); }
    void OnStartup() override
    {
        LOG_INFO("module", "[mod-era-talents] startup (enable={})", sEraTalentsConfig->Enabled());
#ifndef MOD_PLAYERBOTS
        if (sEraTalentsConfig->BotTalents())
            LOG_WARN("module", "[mod-era-talents] EraTalents.BotTalents=1 but this build has no mod-playerbots — bot era talents are unavailable");
#endif
        sEraTalentContent->Load();
        EraTalents::LoadCache();
        EraTransition::LoadCache();
        EraBandClassifier::BuildIndex();   // Phase 9.5: reverse index for the band sweep; logs its own canary
    }
    void OnUpdate(uint32 /*diff*/) override { EraPersistence::Update(); }
    void OnAfterUnloadAllMaps() override { EraPersistence::Flush(); }
    void OnShutdown() override { EraPersistence::Flush(); }
};

void AddSC_era_talents_worldscript() { new era_talents_worldscript(); }

// Aggregated entry point invoked by the module system.
void Addmod_era_talentsScripts()
{
    AddSC_era_talents_worldscript();
    AddSC_era_talent_pin();
    AddSC_era_earned_training();
    AddSC_era_talents_comms();
    AddSC_era_talents_commandscript();
    AddSC_era_talent_proc_scripts();
    AddSC_era_talent_pet_scripts();
    AddSC_era_talent_totem_scripts();
    AddSC_era_glyph_gate();
}
