# Era Talents for Playerbots Portable

Historical talents and selected class spell variants for
[AzerothCore Playerbots Portable](https://github.com/Syntax555/mod-playerbots-portable).
This fork uses each character's own earned Individual Progression era. A level,
account unlock or party leader cannot advance another character's talent system.

| Personal progression | Trees | Maximum earned points |
| --- | --- | ---: |
| Tiers 0–7 | Vanilla 1.12.1, nine original classes | 51 at level 60 |
| Tiers 8–12 | TBC Classic 2.5.4, nine original classes | 61 at level 70 |
| Tier 13+ | Native Wrath | Core rules |

This remains a Wrath core and 3.3.5a client. TBC Classic data includes balance
changes from original 2.4.3; the module does not recreate every historical combat
formula or class subsystem. Existing death knights use native trees.

## Install

Use the portable server's
[Latest release](https://github.com/Syntax555/mod-playerbots-portable/releases/latest)
and [source-build instructions](https://github.com/Syntax555/mod-playerbots-portable/blob/main/docs/building.md).
The server compiles this module with the matching core, Individual Progression,
Playerbots and MultiBot Bridge revisions in its
[manifest](https://github.com/Syntax555/mod-playerbots-portable/blob/main/versions.lock.json).
SQL loads through the normal core database updater.

Every player needs the server release's **`EraTalents-client-latest.zip`**, which
contains the matching addon and merged MPQ. With WoW completely closed:

1. Replace `Interface/AddOns/EraTalents/`; the final path must contain
   `Interface/AddOns/EraTalents/EraTalents.toc`.
2. Copy the package's `Data/patch-V.mpq` into the client's `Data/` folder.
3. Start WoW 3.3.5a, build 12340, enable EraTalents and open the talent window.

The fork's [Latest release](https://github.com/Syntax555/azerothcore-mod-era-talents/releases/latest)
publishes **`EraTalents-addon-latest.zip` only**. It is useful for addon updates
and contains no MPQ. Keep its generation compatible with the installed server
and client pack; a matching combined package is the normal installation route.
Client updates are manual, and `/reload` cannot load a replacement MPQ. See
[client setup and generation checks](https://github.com/Syntax555/mod-playerbots-portable/blob/main/docs/era-talents.md#install-the-matching-client-files).
Bots use the server data without a client installation of their own.

## Supported behavior

- Talent purchases use real level-earned points, rank prerequisites and the
  character's earned era. Native Wrath purchases are blocked while a historical
  tree is active.
- Random bots extend their existing build. Humans, SelfBot characters and
  controlled altbots keep their points for manual choices. With the matching
  MultiBot addon, owners can spend grouped altbots' historical points within
  normal inspect range; other inspected trees are read-only.
- Class lessons require ordinary paid trainer purchases or their earned
  talent/quest source. Later-expansion lessons wait for the character's era.
  Ordinary respecs use a paid class trainer. An earned expansion crossing refunds
  the departing tree once, after combat, without granting levels or trained ranks.
- Glyph effects and new use wait until earned Wrath; owned glyph IDs remain
  stored. Historical spell and talent text includes English and German.
- The matching DragonUI fork hosts historical talents, inspect views and
  MultiBot bot spellbooks in its own windows. Its trainer list follows the
  subject's server eligibility. Historical talents fall back to EraTalents and
  bot spellbooks to MultiBot when their DragonUI modules are disabled, including
  live spellbook switches.

Install DragonUI's `DragonUI` and `DragonUI_Options` folders separately from its
[Latest package](https://github.com/Syntax555/DragonUI/releases/latest).
DragonUI and EraTalents have separate addon versions; update compatible addons
together and retain the MPQ matching the server generation.

## Configuration and diagnostics

The module's [configuration template](conf/mod_era_talents.conf.dist) is opt-in:

| Key | Module default | Portable profile |
| --- | ---: | ---: |
| `EraTalents.Enable` | 0 | 1 |
| `EraTalents.Debug` | 0 | 0 |
| `EraTalents.BotTalents` | 0 | 1 |
| `EraTalents.GlyphGate` | 1 | 1 |

`EraTalents.AdvanceGossip` is a compatibility key with no force-advance behavior.
Use the earned IP boss/quest chain. Preserve the portable strict-progression
profile and do not apply the imported manual-advance patch.

GM/console `.eratalents status [character]` and `.eratalents doctor [character]`
inspect an online character's era, allocation and spell state. Administrative
`learn` and `reset` commands change state and are not diagnostic steps. Include
server revision, character details, generation and diagnostic output in a
[problem report](https://github.com/Syntax555/mod-playerbots-portable/issues).
Automated source and Lua checks do not establish complete in-game class coverage;
see [validation limits](https://github.com/Syntax555/mod-playerbots-portable/blob/main/docs/todo.md#gameplay-validation).

## Sources and contributing

Work on this fork's `main` branch under [AGENTS.md](AGENTS.md) and the portable
[contributing guide](https://github.com/Syntax555/mod-playerbots-portable/blob/main/CONTRIBUTING.md).
Native integrations are committed in their respective forks and pinned together;
the portable build does not apply this repository's imported source patches.
See [integration](docs/patches.md), [validation](docs/verification.md) and
[client packaging](client-patch/README.md).

For dataset work, use [the authoring framework](docs/era-talents-framework.md)
and regenerate SQL, addon data and client artifacts with `tools/era-regen.sh`.
Portable packaging builds and verifies the merged client pack from pinned inputs.
Imported class notes and authoring records describe upstream implementations;
check them against current source and the earned-play rules before use.

This fork retains Lewis Thrasher's work from
[lathcf/azerothcore-mod-era-talents](https://github.com/lathcf/azerothcore-mod-era-talents)
at [`0dac15c4a71d`](https://github.com/lathcf/azerothcore-mod-era-talents/commit/0dac15c4a71d4393f4a2dd8553c460a18db3fbc8).
The [imported README](https://github.com/lathcf/azerothcore-mod-era-talents/blob/0dac15c4a71d4393f4a2dd8553c460a18db3fbc8/README.md)
records the original project and credits: AzerothCore, ZhengPeiRu21's Individual
Progression, Playerbots, wago.tools and Daribon's talent data.
The upstream module uses [MIT](LICENSE); integration files retain their own
GPL notices, and AzerothCore modifications retain the core's terms. See the
portable [third-party notices](https://github.com/Syntax555/mod-playerbots-portable/blob/main/THIRD_PARTY_NOTICES.md).
