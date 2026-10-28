# Native integration

The portable server builds the core and modules from fork commits recorded in
[its dependency manifest](https://github.com/Syntax555/mod-playerbots-portable/blob/main/versions.lock.json).
Era talent hooks and mechanics are integrated into those forks. Do not run this
repository's imported `apply-patches.sh` on the prepared portable sources or
apply its manual-advance IP patch.

Use the portable [source-build workflow](https://github.com/Syntax555/mod-playerbots-portable/blob/main/docs/building.md)
and [contributing guide](https://github.com/Syntax555/mod-playerbots-portable/blob/main/CONTRIBUTING.md).
Changes to core, Playerbots, IP or MultiBot Bridge belong in their own fork,
with matching pins and the relevant integration checks. Preserve personal earned
era, paid training/respecs and manual talent choices for human-controlled
characters.

The imported patch files and regeneration scripts remain upstream development
references. The [original patch inventory](https://github.com/lathcf/azerothcore-mod-era-talents/blob/0dac15c4a71d4393f4a2dd8553c460a18db3fbc8/docs/patches.md)
describes their historical targets and options; its revisions and standalone
installation assumptions do not define the portable build.
