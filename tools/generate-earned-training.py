#!/usr/bin/env python3
"""Generate the paid-training repair and explicit earned era spell variants.

The pinned core trainer/rank dumps and all module migrations are replayed in an
isolated SQLite database. Only missing stock rows are restored: existing marker,
prerequisite and level gates are preserved. Helper templates are spell-mechanic
substrates, not proof of ability identity, so the exceptions below are explicit.
Requires PyYAML. Run from any directory with --core-world path/to/db_world.
"""
from __future__ import annotations

import argparse
import collections
import hashlib
import pathlib
import re
import sqlite3
import sys
from dataclasses import dataclass

import yaml

ROOT = pathlib.Path(__file__).resolve().parents[1]
SQL_NAME = "2026_10_07_00_era_earned_training.sql"
COLUMNS = "TrainerId,SpellId,MoneyCost,ReqSkillLine,ReqSkillRank,ReqAbility1,ReqAbility2,ReqAbility3,ReqLevel,VerifiedBuild"
TRAINER_CLASS = {1: 1, 2: 1, 3: 2, 4: 2, 5: 2, 6: 2, 7: 3, 8: 3,
                 9: 4, 10: 4, 11: 5, 12: 5, 13: 6, 14: 7, 15: 7,
                 **{x: 8 for x in range(16, 31)}, 31: 9, 32: 9, 33: 11, 34: 11}

# The rank chains listed here really collapse into one spell in 3.3.5a.
COLLAPSED = {"Scorpid Sting": 3043, "Seal of Righteousness": 20154,
             "Seal of Justice": 20164, "Seal of Light": 20165,
             "Seal of Wisdom": 20166, "Seal of Command": 20375,
             "Blessing of Sanctuary": 20911, "Trueshot Aura": 19506,
             "Bloodthirst": 23881, "Conflagrate": 17962,
             "Mana Tide Totem": 16190, "Windfury Totem": 8512}
REMOVED = {"Seal of the Crusader", "Seal of Blood", "Grace of Air Totem",
           "Windwall Totem", "Tranquil Air Totem", "Siphon Life", "Rampage"}
# These helpers deliberately use unrelated stock spell templates for mechanics.
EXPLICIT = {
    # Historical Prayer cannot alias the native Wrath talent.
    **{spell: 0 for spell in (948081, 948082, 948083, 948084, 948085, 948086, 948087, 949300, 949301, 949302, 949303, 949304, 949305, 949306, 949307, 948089, 949100, 949101, 949102, 949103, 949104, 949105, 949106, 949308, 949309, 949310, 949311, 949312, 949313, 949314, 949315, 949107, 949108, 949109, 949110, 949111, 949316, 949112, 949113, 949114, 949115, 949116, 949117, 949317, 949318, 949319, 949320, 949321, 949322, 949323, 949124, 949125, 949126, 949127, 949128, 949129, 949331, 949332, 949333, 949334, 949335, 949336, 949337, 949130, 949131, 949132, 949133, 949134, 949135, 949338, 949339, 949340, 949341, 949342, 949343, 949344, 949142, 949143, 949144, 949145, 949146, 949352, 949353, 949354, 949355, 949356, 949357, 949152, 949153, 949154, 949155, 949156, 949157, 949364, 949365, 949366, 949367, 949368, 949369, 949370, 949371, 949372, 949373, 949374, 949375, 949376, 949377, 949378)},
    # Preserve each actually acquired racial rank when it becomes baseline.
    948089: 6346,
    **{949152: 2944, 949153: 19276, 949154: 19277, 949155: 19278, 949156: 19279, 949157: 19280, 949364: 2944, 949365: 19276, 949366: 19277, 949367: 19278, 949368: 19279, 949369: 19280, 949370: 25467},
    932986: 17347, 932987: 17348, 932785: 18937, 932786: 18938,
    932668: 633, 932669: 2800, 932670: 10310,
    # Vanilla Holy Shield starts at L30, TBC/WotLK at L40: match real levels.
    932615: 0, 932655: 20925, 932657: 20927, 932659: 20928,
    946095: 20925, 946128: 20927, 946130: 20928, 946132: 27179,
    932746: 20271, 946084: 31801,
    **{931353 + i: s for i, s in enumerate((1535, 8498, 8499, 11314, 11315))},
    **{947310 + i: s for i, s in enumerate((1535, 8498, 8499, 11314, 11315, 25546, 25547))},
}
STOCK_DEFAULT_LEVEL = {20154: 3, 20271: 4, 20375: 20, 20911: 30,
                       19506: 40, 23881: 40, 17962: 40, 16190: 40,
                       8512: 32, 5229: 12}


@dataclass(frozen=True)
class Helper:
    era: int
    class_id: int
    spell: int
    name: str
    template: int
    explicit_level: int


def statements(source: str, table: str):
    # Every relevant statement contains numeric rows only. Comments are stripped
    # before splitting so descriptive semicolons never affect replay.
    source = re.sub(r"--[^\n]*", "", source)
    source = re.sub(r"/\*.*?\*/", "", source, flags=re.S)
    pattern = rf"(?:DELETE\s+FROM|UPDATE|INSERT(?:\s+(?:OR\s+)?IGNORE)?\s+INTO)\s+`?{table}`?\b"
    for statement in source.split(";"):
        statement = statement.strip()
        if re.match(pattern, statement, re.I):
            yield re.sub(r"^INSERT IGNORE INTO", "INSERT OR IGNORE INTO", statement, flags=re.I)


def dump_rows(source: str, arity: int):
    return [tuple(map(int, match.split(",")))
            for match in re.findall(r"\(([0-9,]+)\)", source)
            if len(match.split(",")) == arity]


def make_database(core: pathlib.Path):
    db = sqlite3.connect(":memory:")
    db.execute("CREATE TABLE trainer_spell (" + ",".join(f"{c} INTEGER" for c in COLUMNS.split(","))
               + ",PRIMARY KEY(TrainerId,SpellId))")
    db.execute("CREATE TABLE spell_ranks(first_spell_id INTEGER,spell_id INTEGER UNIQUE,rank INTEGER,"
               "PRIMARY KEY(first_spell_id,rank))")
    sources = []
    for table, arity in (("trainer_spell", 10), ("spell_ranks", 3)):
        path = core / f"{table}.sql"
        source = path.read_text(encoding="utf-8")
        sources.append((f"core/{path.name}", source))
        rows = dump_rows(source, arity)
        if not rows:
            raise ValueError(f"No {table} rows found in {path}")
        db.executemany(f"INSERT INTO {table} VALUES({','.join('?' for _ in range(arity))})", rows)
    stock_rows = {r[:2]: r for r in db.execute("SELECT * FROM trainer_spell")}
    stock_ranks = {r[1]: (r[0], r[2]) for r in db.execute("SELECT * FROM spell_ranks")}
    for path in sorted((ROOT / "data/sql/world/base").glob("*.sql")):
        if path.name == SQL_NAME:
            continue
        source = path.read_text(encoding="utf-8")
        relevant = list(statements(source, "trainer_spell")) + list(statements(source, "spell_ranks"))
        if not relevant:
            continue
        sources.append((path.name, source))
        for statement in relevant:
            try:
                db.execute(statement)
            except sqlite3.Error as error:
                raise ValueError(f"Cannot replay {path.name}: {error}: {statement[:180]}") from error
    rows = {r[:2]: r for r in db.execute("SELECT * FROM trainer_spell")}
    ranks = {r[1]: (r[0], r[2]) for r in db.execute("SELECT * FROM spell_ranks")}
    return db, stock_rows, stock_ranks, rows, ranks, sources


def load_helpers(sources):
    helpers = {}
    node_levels = {}
    for era, dirname in enumerate(("vanilla", "tbc")):
        for path in sorted((ROOT / "era-data" / dirname).glob("*.yaml")):
            source = path.read_text(encoding="utf-8")
            sources.append((f"era-data/{dirname}/{path.name}", source))
            content = yaml.safe_load(source)
            for helper in content.get("helpers", []):
                spell = helper["id"]
                h = Helper(era, int(content["class"]), spell, helper.get("name", ""),
                           int(helper.get("template", 0)),
                           int(helper.get("spellLevel", helper.get("baseLevel", 0))))
                if (era, spell) in helpers:
                    raise ValueError(f"Duplicate helper {era}/{spell}")
                helpers[era, spell] = h
            for tab in content.get("tabs", []):
                for node in tab["nodes"]:
                    for grants in node.get("grants", {}).values():
                        for spell in grants:
                            node_levels[era, spell] = 10 + 5 * int(node["tier"])
    return helpers, node_levels


def min_trainer_level(rows, spell):
    levels = [r[8] for r in rows.values() if r[1] == spell]
    return min(levels) if levels else 0


def stock_spell(helper, ranks, stock_ranks):
    if helper.spell in EXPLICIT:
        return EXPLICIT[helper.spell]
    if helper.name in REMOVED:
        return 0
    if helper.name in COLLAPSED:
        return COLLAPSED[helper.name]
    template = helper.template
    if not template:
        return 0
    # Many helpers reuse rank 1 as a substrate. Map their actual custom chain
    # rank to the real stock rank, rather than granting rank 1 for every lesson.
    if helper.spell in ranks and template in stock_ranks:
        root, rank = stock_ranks[template][0], ranks[helper.spell][1]
        candidates = [spell for spell, value in stock_ranks.items() if value == (root, rank)]
        if candidates:
            return candidates[0]
    return template


def variant_data(helpers, node_levels, stock_rows, stock_ranks, rows, ranks):
    trained = {r[1] for r in rows.values() if r[1] >= 920000}
    trained.update((932513, 932746, 932668, 932669, 932670, 948081, 949300, 948089, 949100, 949308, 949107, 949316, 949112, 949317, 949124, 949331, 949130, 949338, 949142, 949352, 949152, 949364))
    selected = [h for h in helpers.values() if h.spell in trained]
    # TBC explicitly reuses some Vanilla talent-rooted chains (Sanctuary).
    # Their trained helpers occur only in the Vanilla YAML, not in TBC's file.
    for helper in list(selected):
        root = ranks.get(helper.spell, (helper.spell, 1))[0]
        if helper.era == 0 and (1, root) in node_levels and (1, helper.spell) not in helpers:
            selected.append(Helper(1, helper.class_id, helper.spell, helper.name,
                                   helper.template, helper.explicit_level))
    # Shared Vanilla/TBC custom spell substrates (no duplicate YAML helper).
    for spell in (932513, 932746, 932668, 932669, 932670):
        base = helpers[0, spell]
        selected.append(Helper(1, base.class_id, spell, base.name, base.template, base.explicit_level))
    grouped = collections.defaultdict(lambda: {0: [], 1: []})
    mapped = set()
    for helper in selected:
        stock = stock_spell(helper, ranks, stock_ranks)
        # Use true stock rank identity; a collapsed ability retains its custom
        # rank index so earning rank 2 never creates custom ranks 3 through 8.
        rank = ranks.get(helper.spell, (helper.spell, 1))[1]
        collapsed = helper.name in COLLAPSED or helper.name in REMOVED
        key = (helper.class_id, helper.name, stock, rank if collapsed else 0)
        grouped[key][helper.era].append(helper)
        mapped.add((helper.era, helper.spell))
    variants = []
    for (class_id, name, stock, rank), eras in sorted(grouped.items()):
        if any(len(eras[e]) > 1 for e in (0, 1)):
            raise ValueError(f"Ambiguous mapping {class_id}/{name}/{stock}/{rank}: {eras}")
        values, levels = [0, 0, stock], [0, 0, 0]
        for era in (0, 1):
            if eras[era]:
                h = eras[era][0]
                values[era] = h.spell
                levels[era] = min_trainer_level(rows, h.spell) or h.explicit_level or node_levels.get((era, h.spell), 0)
            elif stock:
                # Find the same actual stock rank among talent root helpers,
                # e.g. L40 Vanilla Holy Shield's paid r2 -> TBC's talent root.
                roots = [h for h in helpers.values() if h.era == era and h.class_id == class_id
                         and h.name == name and stock_spell(h, ranks, stock_ranks) == stock
                         and (era, h.spell) in node_levels]
                if roots and name not in COLLAPSED:
                    h = min(roots, key=lambda h: h.spell)
                    values[era] = h.spell
                    levels[era] = h.explicit_level or node_levels[era, h.spell]
                elif era == 0:
                    root = stock_ranks.get(stock, (stock, 1))[0]
                    vanilla_talent = (0, root) in node_levels
                    # Prayer of Spirit is a separate stock chain whose
                    # prerequisite is the Vanilla Divine Spirit talent root.
                    if name == "Prayer of Spirit":
                        vanilla_talent = (0, 14752) in node_levels
                    if vanilla_talent:
                        values[era] = stock
                        levels[era] = min_trainer_level(stock_rows, stock) or node_levels.get((0, root), 0)
                elif era == 1 and name not in {"Seal of Vengeance", "Fire Elemental Totem", "Earth Elemental Totem"}:
                    # No clone means TBC legitimately retains the stock version,
                    # e.g. Hemorrhage and Dark Pact, not an invented custom id.
                    values[era] = stock
                    levels[era] = min_trainer_level(stock_rows, stock) or STOCK_DEFAULT_LEVEL.get(stock, 0)
        if stock:
            levels[2] = min_trainer_level(stock_rows, stock) or STOCK_DEFAULT_LEVEL.get(stock, 0)
        # Scorpid Sting loses ranks in TBC as well as WotLK. All earned Vanilla
        # ranks convert to the same paid TBC ability, never to a different Sting.
        if name == "Scorpid Sting":
            values[1], levels[1] = 948281, min_trainer_level(rows, 948281)
        # Mana Tide loses ranks in TBC: the active talent root is the replacement.
        if name == "Mana Tide Totem":
            values[1], levels[1] = 947340, node_levels[1, 947340]
        for era, spell in enumerate(values):
            if spell and not levels[era]:
                h = helpers.get((min(era, 1), spell))
                levels[era] = (h.explicit_level if h else 0) or max(1, min(x for x in levels if x))
            if not spell:
                levels[era] = 0
        variants.append((class_id, tuple(values), tuple(levels), name))
    # Standalone stock lessons that used to be auto-granted. These rows also
    # let a training hook distinguish the learned id from Judgement wrapper10321.
    roots = ((1, (932841, 947541, 23922), (40, 40, 40), "Shield Slam root"),
             (11, (932505, 946270, 16689), (10, 10, 10), "Nature's Grasp root"),
             (5, (14752, 948024, 14752), (30, 30, 30), "Divine Spirit root"),
             (2, (932700, 946000, 21084), (1, 1, 4), "Seal of Righteousness starter alias"))
    variants.extend(roots)
    extras = ((8, 45438, 30), (5, 15237, 20),
              (2, 26573, 20), (2, 20217, 20), (2, 25898, 60), (11, 16857, 18),
              (2, 53407, 28), (2, 53408, 12), (2, 53736, 66),
              (2, 27154, 69), (11, 27009, 68), (11, 53312, 78))
    represented = {spell for _, values, _, _ in variants for spell in values if spell}
    for class_id, spell, level in extras:
        if spell in represented:
            continue
        # Talent-baseline gates are enforced by C++; unchanged stock is the
        # same lesson in each era, and its introduction/level gate remains core IP.
        if spell in (53407, 53408, 53736, 27154, 27009, 53312):
            variants.append((class_id, (0, 0, spell), (0, 0, level), "WotLK stock training gate"))
        else:
            variants.append((class_id, (spell, spell, spell), (level, level, level), "Stock training gate"))
    variants = sorted(set(variants), key=lambda r: (r[0], r[1]))
    return variants, trained, mapped


def generate_sql(stock_rows, rows, helpers):
    missing = [r for key, r in sorted(stock_rows.items()) if key not in rows]
    restored = sorted({r[1] for r in missing})
    out = ["-- GENERATED by tools/generate-earned-training.py. Do not edit.",
           "-- Restore paid stock lessons removed to support automatic era spell grants.",
           "-- INSERT IGNORE preserves existing marker/prerequisite gates and core IP overrides.",
           "-- EraEarnedTraining validates the character's era/talents before listing or purchasing.",
           "", "INSERT IGNORE INTO `trainer_spell` (" + ",".join(f"`{c}`" for c in COLUMNS.split(",")) + ") VALUES"]
    out.extend("(" + ",".join(map(str, r)) + ")" + (";" if i == len(missing) - 1 else ",")
               for i, r in enumerate(missing))
    out.extend(("", "-- Shared Judgement/LoH are paid in both Vanilla and TBC; dynamic era gating",
                "-- replaces the Vanilla-only rank-1 marker. Higher-rank prerequisites remain intact.",
                "UPDATE `trainer_spell` SET `ReqAbility1`=0 WHERE `SpellId` IN (932746,932668)",
                "  AND `ReqAbility1`=932749;", "",
                "-- Enrage has the real stock level and cost; never learned solely by reaching L12."))
    enrage = [r for r in stock_rows.values() if r[1] == 5229]
    if not enrage:
        raise ValueError("Stock Enrage trainer lesson is absent")
    out.append("INSERT IGNORE INTO `trainer_spell` (" + ",".join(f"`{c}`" for c in COLUMNS.split(",")) + ") VALUES")
    for i, r in enumerate(enrage):
        custom = list(r)
        custom[1] = 932513
        out.append("(" + ",".join(map(str, custom)) + ")" + (";" if i == len(enrage) - 1 else ","))
    # General Vanilla trainers are the authoritative established prices. The
    # special Trainer6 wrapper and TBC substrate used an accidental L*1000 curve.
    canonical = {spell: r[2] for (trainer, spell), r in rows.items() if trainer == 3}
    base_curve = collections.defaultdict(collections.Counter)
    for r in stock_rows.values():
        if r[0] == 3 and r[3] == 0 and r[2] > 0:
            base_curve[r[8]][r[2]] += 1
    curve = {level: min(counter, key=lambda value: (-counter[value], -value))
             for level, counter in base_curve.items()}
    vanilla_by_name_level = {}
    for (era, spell), h in helpers.items():
        if era == 0 and h.class_id == 2 and spell in canonical and h.name.startswith("Seal of"):
            vanilla_by_name_level[h.name, min_trainer_level(rows, spell)] = canonical[spell]
    prices = {}
    for (era, spell), h in sorted(helpers.items()):
        if h.class_id != 2 or not h.name.startswith("Seal of") or not any(r[1] == spell for r in rows.values()):
            continue
        level = min_trainer_level(rows, spell)
        if era == 0:
            price = canonical.get(spell)
        else:
            price = vanilla_by_name_level.get((h.name, level))
            if price is None:
                lower = max(x for x in curve if x <= level)
                price = curve[lower]
        if price is not None:
            prices[spell] = price
    # LoH/Judgement specialized wrapper should share normal class trainer prices.
    for spell in (932746, 932668, 932669, 932670):
        prices[spell] = canonical[spell]
    out.extend(("", "-- Match shared seal ranks to the established Vanilla prices on general trainers.",
                "-- New TBC ranks use the modal stock paladin price at the same level, or nearest",
                "-- lower populated level. Only MoneyCost changes; faction/marker/rank gates remain."))
    for spell, price in sorted(prices.items()):
        out.append(f"UPDATE `trainer_spell` SET `MoneyCost`={price} WHERE `SpellId`={spell};")
    return "\n".join(out) + "\n", missing, restored, prices


def generate_header(variants, restored, digest):
    out = ["// GENERATED by tools/generate-earned-training.py. Do not edit.",
           f"// Input SHA-256: {digest}", "// Zero spell id means the ability has no equivalent in that era.",
           "#pragma once", "", '#include "Define.h"', "", "namespace EraEarnedTrainingData", "{",
           "    struct Variant", "    {", "        uint8 classId;", "        uint32 spell[3];",
           "        uint8 minimumLevel[3];", "    };", "", "    inline constexpr Variant kVariants[] =", "    {"]
    for class_id, values, levels, name in variants:
        out.append(f"        {{ {class_id}, {{ {', '.join(map(str, values))} }}, "
                   f"{{ {', '.join(map(str, levels))} }} }}, // {name}")
    out.extend(("    };", "", "    inline constexpr uint32 kRestoredStockSpellIds[] =", "    {"))
    for i in range(0, len(restored), 8):
        out.append("        " + ", ".join(map(str, restored[i:i + 8])) + ",")
    out.extend(("    };", "}", ""))
    return "\n".join(out)


def verify(db, stock_rows, before, sql, variants, trained, mapped, prices):
    db.execute("SAVEPOINT existing_override")
    absent = next(r for key, r in stock_rows.items() if key not in before)
    override = list(absent)
    override[8] = 71
    override[5] = 123456
    db.execute("INSERT INTO trainer_spell VALUES(?,?,?,?,?,?,?,?,?,?)", override)
    for statement in statements(sql.replace("INSERT IGNORE", "INSERT OR IGNORE"), "trainer_spell"):
        db.execute(statement)
    if db.execute("SELECT * FROM trainer_spell WHERE TrainerId=? AND SpellId=?", absent[:2]).fetchone() != tuple(override):
        raise ValueError("Restoration overwrote an existing core IP/prerequisite override")
    db.execute("ROLLBACK TO existing_override")
    db.execute("RELEASE existing_override")
    db.executescript(sql.replace("INSERT IGNORE", "INSERT OR IGNORE"))
    after = {r[:2]: r for r in db.execute("SELECT * FROM trainer_spell")}
    missing = set(stock_rows) - set(after)
    if missing:
        raise ValueError(f"Stock trainer rows still absent: {sorted(missing)}")
    for key, previous in before.items():
        current = after[key]
        wanted = list(previous)
        if previous[1] in prices:
            wanted[2] = prices[previous[1]]
        if previous[1] in (932746, 932668) and previous[5] == 932749:
            wanted[5] = 0
        if tuple(wanted) != current:
            raise ValueError(f"Existing trainer gate changed unexpectedly: {key}")
    represented = {(era, spell) for _, spells, _, _ in variants for era, spell in enumerate(spells) if spell >= 920000}
    unrepresented = mapped - represented
    if unrepresented:
        raise ValueError(f"Trained helper variants missing: {sorted(unrepresented)}")
    actual_trained = {row[1] for row in before.values() if row[1] >= 920000}
    if actual_trained - {spell for _, spell in mapped}:
        raise ValueError(f"No helper mapping for trained custom spells: {sorted(actual_trained - {spell for _, spell in mapped})}")
    lesson_classes = {(class_id, spell) for class_id, spells, _, _ in variants for spell in spells if spell}
    for key, row in stock_rows.items():
        if key in before:
            continue
        learned = 20271 if row[1] == 10321 else row[1]
        if (TRAINER_CLASS[row[0]], learned) not in lesson_classes:
            raise ValueError(f"Restored stock lesson lacks an earned/gated mapping: {key}")
    # Re-application must not alter any restored lesson or requirement.
    db.executescript(sql.replace("INSERT IGNORE", "INSERT OR IGNORE"))
    if after != {r[:2]: r for r in db.execute("SELECT * FROM trainer_spell")}:
        raise ValueError("Generated migration is not idempotent")
    for _, spells, levels, _ in variants:
        for spell, level in zip(spells, levels):
            if bool(spell) != bool(level) or not 0 <= level <= 80:
                raise ValueError(f"Invalid variant minimum level: {spells}/{levels}")
    # Identity regressions: unrelated mechanic templates must never become lessons.
    expected = {932700: (946000, 20154), 932725: (946034, 20165),
                932737: (946050, 20166), 931353: (947310, 1535),
                931320: (947270, 0), 932669: (932669, 2800)}
    for vanilla, pair in expected.items():
        matching = [spells for _, spells, _, _ in variants if spells[0] == vanilla]
        if pair not in [values[1:] for values in matching]:
            raise ValueError(f"Identity regression for {vanilla}: {matching}")
    for _, spells, _, name in variants:
        if name in REMOVED and spells[2]:
            raise ValueError(f"Removed ability {name} has a WotLK lesson")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--core-world", type=pathlib.Path, required=True)
    parser.add_argument("--check", action="store_true", help="check committed generated output without writing")
    args = parser.parse_args()
    db, stock_rows, stock_ranks, rows, ranks, sources = make_database(args.core_world)
    helpers, node_levels = load_helpers(sources)
    variants, trained, mapped = variant_data(helpers, node_levels, stock_rows, stock_ranks, rows, ranks)
    sql, missing, restored, prices = generate_sql(stock_rows, rows, helpers)
    verify(db, stock_rows, rows, sql, variants, trained, mapped, prices)
    digest = hashlib.sha256("\n".join(name + "\n" + data for name, data in sources).encode()).hexdigest()
    header = generate_header(variants, restored, digest)
    outputs = ((ROOT / "src/EraEarnedTrainingData.gen.h", header),
               (ROOT / "data/sql/world/base" / SQL_NAME, sql))
    for path, content in outputs:
        if args.check:
            if not path.exists() or path.read_text(encoding="utf-8") != content:
                raise ValueError(f"Generated output differs: {path.relative_to(ROOT)}")
        else:
            path.write_text(content, encoding="utf-8")
    print(f"Validated {len(variants)} explicit earned variants, {len(missing)} restored stock rows "
          f"({len(restored)} spell IDs), {len(prices)} corrected paid spell prices; all existing gates preserved.")
    print("Former auto-grants restored as paid stock lessons: " + ", ".join(map(str, restored)))


if __name__ == "__main__":
    try:
        main()
    except (ValueError, sqlite3.Error) as error:
        print(f"error: {error}", file=sys.stderr)
        sys.exit(1)
