#include "EraTalentsConfig.h"
#include "Config.h"
EraTalentsConfig* EraTalentsConfig::instance() { static EraTalentsConfig i; return &i; }
void EraTalentsConfig::Load()
{
    _enabled = sConfigMgr->GetOption<bool>("EraTalents.Enable", false);
    _debug   = sConfigMgr->GetOption<bool>("EraTalents.Debug", false);
    _botTalents = sConfigMgr->GetOption<bool>("EraTalents.BotTalents", false);
    _glyphGate = sConfigMgr->GetOption<bool>("EraTalents.GlyphGate", true);
}
