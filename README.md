## mod-playerbots-portable fork

This fork carries what [mod-playerbots-portable](https://github.com/Syntax555/mod-playerbots-portable) needs on top of [lathcf/azerothcore-mod-era-talents](https://github.com/lathcf/azerothcore-mod-era-talents). Work happens on `main`; every push publishes `EraTalents-addon-latest.zip` in the [Latest release](https://github.com/Syntax555/azerothcore-mod-era-talents/releases/latest).

For a quick addon update, close WoW and extract the ZIP into `Interface/AddOns/` so that `Interface/AddOns/EraTalents/EraTalents.toc` exists. The merged `Data/patch-V.mpq` must match the server's data generation and comes only with `EraTalents-client-latest.zip` from the server release; install that package whenever the server is updated.

The server module and its client addon are built together by [mod-playerbots-portable](https://github.com/Syntax555/mod-playerbots-portable), which pins a tested commit of this branch.

Changes on `main`:

- Selects historical trees, training, glyph rules and point budgets from each character's own earned Individual Progression tier.
- Keeps TBC and WotLK class trainer lessons from characters who have not earned that expansion, as their trainers, quests and books first taught them.
- Merges German names, descriptions and aura text into the historical spell rows and translates the addon.
- Keeps historical spells in their native spell groups and trains priest racial spells through their class quests.
- Shows inspected bots' historical trees and lets owners train their controlled altbots.
- Shows Vanilla and TBC trees inside DragonUI's talent window for your character, inspected players and MultiBot altbots, using each character's own earned era.
- Sends each character's trainer list to DragonUI's spellbook and level-up notice, closes the glyph page before earned Wrath and shows MultiBot bot spellbooks in DragonUI's own book, filled with the bot's spells and trainer list.

The server pins a tested commit of `main` in its `versions.lock.json`. Upstream updates are merged into `main`; the original README follows.

---

# mod-era-talents

## AzerothCore Module

**Historical talent trees for characters earning their way through the expansions.** While a
character is in the Vanilla or TBC era (as decided by
[mod-individual-progression](https://github.com/ZhengPeiRu21/mod-individual-progression)), the
stock WotLK talent window is fenced off and replaced by that era's real trees for its class — and
the server implements the restored talent mechanics. Data comes from Vanilla 1.12.1 and TBC
Classic 2.5.4; this is not a complete reconstruction of every original-expansion mechanic.

Individual Progression gives every character its own expansion timeline on a single WotLK realm,
but it does not touch the talent system: a "Vanilla" character still gets WotLK's 71-point trees
and glyphs. This module closes that gap. It depends on IP for a character's era and never edits IP's
data.

> Looking for a complete server instead of a module? This mod was developed for, and is installed
> automatically by, **[azerothcore-playerbots-docker-automated](https://github.com/lathcf/azerothcore-playerbots-docker-automated)**
> — a Docker deployment of AzerothCore + playerbots + Individual Progression with this and several
> other custom mods pre-wired.

### What you get
* **Era trees for all nine original classes, in both Vanilla (51 points) and TBC (61 points)**,
  authored from each era's own data. WotLK-era characters and Death Knights keep the stock trees.
* **Correct talents, not cosmetic ones.** Where WotLK kept a talent's behaviour and numbers the
  stock passive is reused; where WotLK retuned or removed it the module ships its own server-side
  version — restored abilities (the Vanilla seal/judgement system, Bloodthirst, Conflagrate, the
  Vanilla Vampiric Embrace, TBC Mangle, the full Vanilla/TBC totem set, …), procs and per-rank
  passives: about 3,600 custom spell rows in a reserved id band. Era markers select historical
  mechanics while later-era characters keep their corresponding spell variants.
  See **[Era talents — class by class](docs/era-talents-classes.md)**.
* **Era-correct spellbooks and glyphs.** WotLK-only talents and their spells are stripped in earlier
  eras, and glyphs are WotLK-only (`EraTalents.GlyphGate`; Death Knights exempt).
* **Earned expansion transitions.** Actual IP milestone/quest completion moves a character into
  the next expansion and refunds their level-earned points once for its changed tree. No gossip
  forces a stage, and ordinary relogs or bot refreshes never give a free respec.
* **Bots too (optional).** With mod-playerbots installed and `EraTalents.BotTalents = 1`, bots
  use their own earned IndividualProgression milestones for Vanilla/TBC trees. Level alone never
  advances an expansion. Random bots' authored builds spend newly earned points without routine
  free resets; altbots and SelfBot characters keep unspent points for their owner.

## Requirements

* AzerothCore 3.3.5a, Individual Progression and the earned integration patches pinned by the
  portable project's `versions.lock.json`.
* The matching EraTalents addon and merged client MPQ for every human client.
* Playerbots for autonomous bot builds; the Multibot bridge is optional.

Use the portable profiles together. Upstream per-player bypass settings and manual expansion
advance patches are not part of this earned adaptation.

## Portable installation

This source is the earned adaptation packaged by `mod-playerbots-portable`. Its parent project's
`versions.lock.json` pins the module, server, IP and playerbots revisions plus adaptation patches.
Use the complete portable build or its documented source workflow; do not replace modules with
unreviewed latest clones or apply the upstream manual-advance IP patch. Source preparation runs
`cmake -P cmake/PrepareModules.cmake` from the portable repository before the normal build.

The core DB updater applies module world/character SQL on startup. The adaptation restores paid
trainer rows and does not run the three upstream character-spell cleanup migrations. Enable the
module explicitly or apply the portable startup profiles; the module's own default is disabled.

### Client install (each player)
Two pieces, both required for the intended experience:
* **The EraTalents addon** — copy `client-addon/EraTalents/` to
  `World of Warcraft/Interface/AddOns/EraTalents/`. With the matching DragonUI addon, the normal
  talent button/key opens historical trees in DragonUI's window. Without DragonUI, EraTalents
  provides its own talent panel and stock inspect overlay.
* **`patch-V.mpq`** — copy to `World of Warcraft/Data/`. This is IP's own client patch with this
  module's custom spell and skill-line rows merged in. It is required: the client must know the
  historical usable spells, trainer requirements and aura descriptions, not only cosmetic icons.
  Use the matching client artifacts from the complete portable package. The addon warns when the
  MPQ generation is stale; never install another module's conflicting `patch-V.mpq` over it.

## Configuration (`conf/mod_era_talents.conf.dist`)
| Key | Default | Meaning |
|-----|---------|---------|
| `EraTalents.Enable` | 0 | Opt-in master switch; the portable profile enables it. |
| `EraTalents.Debug` | 0 | Log each addon request/reply and every reconcile to the console. |
| `EraTalents.BotTalents` | 0 | Bots use their own earned IP era; random bots incrementally spend level-earned points. |
| `EraTalents.GlyphGate` | 1 | Blocks glyph use before earned Wrath while preserving existing paid glyph rows. |
| `EraTalents.AdvanceGossip` | 0 | Compatibility key; force-advance gossip is disabled. |

Normal IP boss-credit and quest paths remain authoritative for every character. An actual
expansion crossing refunds the previous tree once; relogs and routine bot refreshes preserve
spent points. Vanilla-to-TBC still requires earned Naxxramas progression and the actual
Into the Breach quest, and Wrath requires the earned TBC completion path. No gossip copies or
forces another character's progression.

## Playerbots (optional)

Bots use their own **earned IP progression**, exactly as human characters do. Turn on
`EraTalents.BotTalents = 1` after installing the portable integration patches. Bot AI resolves
known historical spell variants and uses the existing tree when adding new earned points.
Usable class spells are paid trainer lessons or actual earned talent/quest grants; level alone
never gives a trained spell rank. Existing known variants transfer conservatively across eras.

The portable project applies pinned source patches through its module preparation workflow;
do not apply the upstream manual-advance patch. Humans need the matching talent addon and client
MPQ. Bots use server data and need no client artifact of their own.

## Commands (GM / console)
`.eratalents status|doctor|reset|learn <character>` — **`doctor` is the first stop for any "this
talent doesn't work" report**: it prints the character's era, spent ranks, every expected era spell
and whether it is known, orphaned band spells, and (with playerbots) the AI's spell resolution.

## Authoring and contributing
Read **[docs/era-talents-framework.md](docs/era-talents-framework.md)** first — it is the decision
tree, field-semantics table and verification checklist for every era spell. One YAML per
(era, class) under `era-data/` is the source of truth; `tools/era-regen.sh` is the **only** way to
ship a change (it regenerates SQL, the band allowlist header, the addon Lua and — when the MPQ tools
are built — the client patch under one generation stamp). `tools/era_audit.py` must be clean and
`uv run --with pyyaml --with pytest python -m pytest tools` green. Running the pipeline needs the base
DBCs once: `client-patch/build-mpqpack.sh` then `tools/fetch-base-dbc.sh` (stages IP's server-side
`Spell.dbc`/`SkillLineAbility.dbc` into the gitignored `client-patch/base/`). Patch inventory and regeneration:
[docs/patches.md](docs/patches.md).

## Compatibility
All ten patches were cut against the commit ids under *Requirements*. On 2026-09-07 the six core
patches and the IP patch also applied cleanly to **stock `azerothcore-wotlk` master `c80c4b9`**, and
every module translation unit compiled there without mod-playerbots (`docs/verification.md`). Core
patches are inert
until a character is in an era band, so a stock server behaves identically until then. If a patch
stops applying after an upstream change, `apply-patches.sh` names it; regenerate with the matching
`tools/regen-*.sh` (see `docs/patches.md`) or open an issue with your commit ids.

## License and credits
MIT (see `LICENSE`). The core patches modify AzerothCore (AGPL-3.0) source and carry that licence.
Companion project: [azerothcore-playerbots-docker-automated](https://github.com/lathcf/azerothcore-playerbots-docker-automated)
(the full Docker server this module ships in).
Thanks to AzerothCore, ZhengPeiRu21's mod-individual-progression, the mod-playerbots project,
wago.tools (TBC 2.5.4 talent data) and Daribon's 1.12.1 talent calculator data.
