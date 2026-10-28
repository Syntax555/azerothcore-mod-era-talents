# Validation

The fork's **Portable integration** workflow prepares the portable server's
pinned dependencies, substitutes this module's proposed commit and runs the
selected native integration fixtures. It also checks addon locale behavior and
Lua fixtures. The **Latest** workflow checks Lua 5.1 syntax and packages the
addon-only ZIP. Complete server builds and combined client-pack verification
run in the portable repository.

Before committing, follow [AGENTS.md](../AGENTS.md) and run the checks relevant
to the changed production sources and integrations. For dataset changes,
regenerate SQL, addon data and client artifacts together; see
[client packaging](../client-patch/README.md) and the
[portable check guide](https://github.com/Syntax555/mod-playerbots-portable/blob/main/docs/building.md#integration-checks).
Documentation-only work uses documentation and link checks.

Source fixtures, syntax checks and package verification do not establish full
in-game coverage of historical class spells or addon windows. Track concrete
client, training and gameplay validation in the portable
[validation list](https://github.com/Syntax555/mod-playerbots-portable/blob/main/docs/todo.md#gameplay-validation).
A report should name the server revision, addon versions, MPQ generation,
character class/race/level/earned tier and reproducible action; GM/console
`.eratalents status` and `.eratalents doctor` provide read-only state.

The [imported verification records](https://github.com/lathcf/azerothcore-mod-era-talents/blob/0dac15c4a71d4393f4a2dd8553c460a18db3fbc8/docs/verification.md)
describe earlier upstream environments. Their level-based development cases and
runtime results are not validation claims for this fork's earned progression.
