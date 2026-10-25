#ifndef MOD_ERA_TALENTS_CONFIG_H
#define MOD_ERA_TALENTS_CONFIG_H
#include <string>
class EraTalentsConfig
{
public:
    static EraTalentsConfig* instance();
    void Load();
    bool Enabled() const { return _enabled; }
    bool Debug() const { return _debug; }
    bool BotTalents() const { return _botTalents; }
    bool GlyphGate() const { return _glyphGate; }
private:
    bool _enabled = false;
    bool _debug = false;
    bool _botTalents = false;
    bool _glyphGate = true;
};
#define sEraTalentsConfig EraTalentsConfig::instance()
#endif
