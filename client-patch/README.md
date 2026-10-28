# EraTalents client patch

The merged `Data/patch-V.mpq` supplies the 3.3.5a client with historical spell
and skill-line records, visible auras, English/German text and a generation
marker. It also retains Individual Progression's base client content. These
records support usable spells and trainer requirements as well as display.

## Install and verify

Use **`EraTalents-client-latest.zip` from the matching
[portable server release](https://github.com/Syntax555/mod-playerbots-portable/releases/latest)**.
With WoW fully closed, install both its `Interface/AddOns/EraTalents/` folder
and `Data/patch-V.mpq`. Restart the client and inspect the generation:

```lua
/run print(GetSpellInfo(932999))
```

It must report `EraTalents Gen` with the generation recorded in the package's
`README.txt` and `SOURCE_MANIFEST.json`. An addon-only update from this fork's
Latest release contains no MPQ. Keep compatible server, addon and MPQ data;
`/reload` does not replace an MPQ, and another DBC patch can override these rows.
See [complete client setup](https://github.com/Syntax555/mod-playerbots-portable/blob/main/docs/era-talents.md#install-the-matching-client-files).

## Build the portable client pack

Run from the portable assembly checkout with its documented build prerequisites:

```bash
cmake -P cmake/PrepareModules.cmake
cmake -DPACKAGE_VERSION=dev -P cmake/PackageEraClient.cmake
```

This produces `output/EraTalents-client-dev.zip` from pinned module, base MPQ,
DBC and StormLib inputs. Packaging checks generated rows, client/server
generation agreement, preserved base entries and output bytes, and includes
source hashes and dependency notices. Use this workflow for distributable
portable packages; see [building](https://github.com/Syntax555/mod-playerbots-portable/blob/main/docs/building.md).

## Source tools

`tools/era-regen.sh` regenerates dataset SQL, the band allowlist and addon data.
It also rebuilds a local merged MPQ when its MPQ tools and target archive exist;
read its output because it can skip that step. Dataset changes need a newly
verified matching client package.

`build-mpqpack.sh`, `build-client-patch.sh` and `merge-into-patch.sh` remain
upstream development tools. Their default fetch path uses unpinned upstream IP
data and is not the portable release workflow. The
[imported client-patch guide](https://github.com/lathcf/azerothcore-mod-era-talents/blob/0dac15c4a71d4393f4a2dd8553c460a18db3fbc8/client-patch/README.md)
documents their original options; [the fork README](../README.md) defines the
current supported installation and earned-play scope.
