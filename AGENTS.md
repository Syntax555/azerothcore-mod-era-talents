# Repository guidance

This fork belongs to [AzerothCore Playerbots Portable](https://github.com/Syntax555/mod-playerbots-portable/blob/main/README.md).
Before editing, read its [repository rules](https://github.com/Syntax555/mod-playerbots-portable/blob/main/AGENTS.md), the shared
skills those rules require, [README](https://github.com/Syntax555/mod-playerbots-portable/blob/main/README.md),
[contributing guide](https://github.com/Syntax555/mod-playerbots-portable/blob/main/CONTRIBUTING.md) and
[Historical talents and client setup](https://github.com/Syntax555/mod-playerbots-portable/blob/main/docs/era-talents.md). Those rules also apply when working in this
fork alone and take precedence over imported upstream contribution instructions.

Commit validated changes on `main`; pin the commit in the assembly's
`versions.lock.json` and record fixture-covered behavior commits in `forkChanges`.
Keep original upstream history, licenses and file notices. Never rewrite a
commit pinned by the assembly. Validate native changes with the assembly's
prepared core and relevant production fixtures before committing.

For addon or Lua changes, read the [WoW 3.3.5a addon wiki](https://github.com/NeticSoul/wow-335a-addon-wiki/blob/main/index.md)
and relevant pages. Target Lua 5.1 and Interface 30300, verify the pinned
client APIs and check each changed Lua file with Lua 5.1. See the assembly's
[client setup](https://github.com/Syntax555/mod-playerbots-portable/blob/main/docs/era-talents.md#install-the-matching-client-files).
