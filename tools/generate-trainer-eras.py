#!/usr/bin/env python3
"""Generate the expansion that first taught each later class trainer lesson.

AzerothCore's class trainers teach the WotLK lessons. A lesson whose spell a
character could not obtain on 1.12 is a TBC lesson, and one it could not obtain
on 2.4.3 either is a WotLK lesson: EraEarnedTraining keeps both away from a
character until it has earned that era. "Obtain" covers every source a player
had: class trainers, quest rewards, books and other learning items, starting
spells and spells learned together with another spell. The pinned CMaNGOS
classic-db and tbc-db dumps supply those sources; learning spells resolve to
the spell they teach through classic-db's spell_template and the WotLK
Spell.dbc. Spell IDs are stable across these clients, so a lesson keeps its ID
from the expansion that introduced it.

Run with --core-world <AzerothCore data/sql/base/db_world>, --classic-db and
--tbc-db <CMaNGOS Full_DB .sql.gz> and --spell-dbc <WotLK Spell.dbc>.
"""
from __future__ import annotations

import argparse
import gzip
import hashlib
import pathlib
import re
import struct
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "src/EraTrainerEraData.gen.h"
SPELL_EFFECT_LEARN_SPELL = 36
ITEM_SPELLTRIGGER_LEARN_SPELL_ID = 6
TRAINER_TYPE_CLASS = 0
# Death knights keep their native training: EraTalents never gives them a historical era.
CLASS_DEATH_KNIGHT = 6
# Spell.dbc columns of the WotLK client (tools/spell_dbc_columns.txt).
DBC_EFFECT, DBC_TRIGGER, DBC_NAME = 71, 116, 136
CLASS_NAMES = {1: "Warrior", 2: "Paladin", 3: "Hunter", 4: "Rogue", 5: "Priest", 7: "Shaman", 8: "Mage",
               9: "Warlock", 11: "Druid"}
SOURCE_TABLES = ("npc_trainer", "npc_trainer_template", "quest_template", "item_template",
                 "playercreateinfo_spell", "spell_learn_spell", "spell_template")


def values(text: str, start: int):
    """Rows of one INSERT statement's VALUES list, from its first parenthesis."""
    index, length = start, len(text)
    while index < length:
        while index < length and text[index] in " \n\r\t,":
            index += 1
        if index >= length or text[index] == ";":
            return
        if text[index] != "(":
            raise ValueError(f"Unexpected SQL near {text[index:index + 40]!r}")
        index += 1
        row, token, quoted, was_string = [], [], False, False
        while True:
            char = text[index]
            if quoted:
                if char == "\\":
                    token.append(text[index + 1])
                    index += 2
                elif char == "'" and text[index + 1:index + 2] == "'":
                    token.append("'")
                    index += 2
                elif char == "'":
                    quoted = False
                    index += 1
                else:
                    token.append(char)
                    index += 1
                continue
            if char == "'":
                quoted, was_string = True, True
                index += 1
                continue
            if char in ",)":
                value = "".join(token).strip()
                if was_string:
                    row.append(value)
                elif value.upper() in ("", "NULL"):
                    row.append(None)
                else:
                    row.append(float(value) if "." in value or "e" in value.lower() else int(value))
                token, was_string = [], False
                index += 1
                if char == ")":
                    yield row
                    break
                continue
            token.append(char)
            index += 1


def table_rows(text: str, table: str) -> list[dict]:
    created = re.search(rf"CREATE TABLE `{re.escape(table)}` \((.*?)\n\)", text, re.DOTALL)
    if not created:
        raise ValueError(f"Missing table {table}")
    columns = re.findall(r"^\s+`([^`]+)`", created.group(1), re.MULTILINE)
    rows = []
    for insert in re.finditer(rf"INSERT INTO `{re.escape(table)}` (?:\(([^)]*)\) )?VALUES\s*", text):
        names = [name.strip(" `") for name in insert.group(1).split(",")] if insert.group(1) else columns
        rows.extend(dict(zip(names, row)) for row in values(text, insert.end()))
    return rows


def read_dump(path: pathlib.Path) -> dict[str, list[dict]]:
    with gzip.open(path, "rt", encoding="utf-8", errors="replace") as handle:
        text = handle.read()
    return {table: table_rows(text, table) for table in SOURCE_TABLES}


def read_spell_dbc(path: pathlib.Path) -> tuple[dict[int, tuple], bytes]:
    data = path.read_bytes()
    magic, count, fields, size, _ = struct.unpack_from("<4s4I", data)
    if magic != b"WDBC" or fields != 234:
        raise ValueError(f"{path} is not a WotLK Spell.dbc")
    records = {}
    for index in range(count):
        record = struct.unpack_from(f"<{fields}I", data, 20 + index * size)
        records[record[0]] = record
    return records, data[20 + count * size:]


def spell_name(dbc, spell_id: int) -> str:
    records, strings = dbc
    record = records.get(spell_id)
    if not record:
        return "?"
    offset = record[DBC_NAME]
    return strings[offset:strings.index(b"\0", offset)].decode("utf-8", errors="replace")


def learned_by(spell_id: int, templates: dict[int, dict], dbc) -> list[int]:
    """The spells a learning spell teaches; empty when it teaches nothing."""
    template = templates.get(spell_id)
    if template is not None:
        return [template[f"EffectTriggerSpell{k}"] for k in (1, 2, 3)
                if template.get(f"Effect{k}") == SPELL_EFFECT_LEARN_SPELL and template.get(f"EffectTriggerSpell{k}")]
    record = dbc[0].get(spell_id)
    if record is None:
        return []
    return [record[DBC_TRIGGER + k] for k in range(3)
            if record[DBC_EFFECT + k] == SPELL_EFFECT_LEARN_SPELL and record[DBC_TRIGGER + k]]


def obtainable(dump: dict[str, list[dict]], dbc) -> set[int]:
    """Every spell a character of that expansion could learn."""
    templates = {row["Id"]: row for row in dump["spell_template"]}
    spells: set[int] = set()

    def direct(spell_id):
        if spell_id:
            spells.add(spell_id)
            spells.update(learned_by(spell_id, templates, dbc))

    for table in ("npc_trainer", "npc_trainer_template"):
        for row in dump[table]:
            direct(row["spell"])
    for row in dump["quest_template"]:
        direct(row.get("RewSpell"))
        direct(row.get("RewSpellCast"))
    for row in dump["item_template"]:
        for k in range(1, 6):
            spell_id = row.get(f"spellid_{k}")
            if not spell_id:
                continue
            if row.get(f"spelltrigger_{k}") == ITEM_SPELLTRIGGER_LEARN_SPELL_ID:
                direct(spell_id)
            else:
                # A book's use spell only counts through the spell it teaches.
                spells.update(learned_by(spell_id, templates, dbc))
    for row in dump["playercreateinfo_spell"]:
        direct(row.get("Spell"))
    for row in dump["spell_learn_spell"]:
        direct(row.get("SpellID"))
    return spells


def class_lessons(core_world: pathlib.Path) -> dict[tuple[int, int], int]:
    """(class, trainer spell) of every class trainer lesson, with its lowest level."""
    trainers = table_rows((core_world / "trainer.sql").read_text(encoding="utf-8"), "trainer")
    classes = {row["Id"]: row["Requirement"] for row in trainers if row["Type"] == TRAINER_TYPE_CLASS}
    lessons: dict[tuple[int, int], int] = {}
    for row in table_rows((core_world / "trainer_spell.sql").read_text(encoding="utf-8"), "trainer_spell"):
        class_id = classes.get(row["TrainerId"])
        if class_id is None or class_id == CLASS_DEATH_KNIGHT:
            continue
        key = (class_id, row["SpellId"])
        lessons[key] = min(lessons.get(key, 255), row["ReqLevel"])
    if not lessons:
        raise ValueError("No class trainer lessons found")
    return lessons


def classify(lessons, vanilla: set[int], tbc: set[int], dbc) -> list[tuple[int, int, int, int]]:
    """(spell, class, era, level) of every lesson a Vanilla character could not obtain."""
    later = []
    for (class_id, spell_id), level in sorted(lessons.items(), key=lambda item: (item[0][1], item[0][0])):
        taught = set(learned_by(spell_id, {}, dbc)) | {spell_id}
        if taught & vanilla:
            continue
        later.append((spell_id, class_id, 1 if taught & tbc else 2, level))
    return later


def header(later, dbc, digests: dict[str, str]) -> str:
    out = ["// GENERATED by tools/generate-trainer-eras.py. Do not edit.",
           "// Class trainer lessons a character could not obtain before TBC (era 1) or WotLK (era 2).",
           "// Every other stock lesson is a Vanilla one. Inputs (SHA-256):"]
    out += [f"//   {name}: {digest}" for name, digest in digests.items()]
    out += ["#pragma once", "", '#include "Define.h"', "", "namespace EraTrainerEraData", "{",
            "    struct Lesson", "    {", "        uint32 spellId;", "        uint8 classId;", "        uint8 era;",
            "    };", "", "    // Sorted by spell for lookup.", "    inline constexpr Lesson kLaterLessons[] =", "    {"]
    for spell_id, class_id, era, level in later:
        out.append(f"        {{ {spell_id}, {class_id}, {era} }},  // {CLASS_NAMES[class_id]} L{level} "
                   f"{spell_name(dbc, spell_id)}")
    out += ["    };", "}", ""]
    return "\n".join(out)


def check(later, lessons) -> None:
    eras = {(spell_id, class_id): era for spell_id, class_id, era, _ in later}
    # Lessons whose history is certain; a regression in any source shows here first.
    expected = {(34428, 1): 1,     # Victory Rush, TBC
                (51722, 4): 2,     # Dismantle, WotLK
                (57994, 7): 2,     # Wind Shear, WotLK
                (5938, 4): 1,      # Shiv, TBC
                (19801, 3): None,  # Tranquilizing Shot: a Molten Core book in 1.12
                (21562, 5): None,  # Prayer of Fortitude: a Dire Maul book in 1.12
                (1757, 4): None,   # Sinister Strike rank 2: trained in 1.12
                (8998, 11): None}  # Cower: trained in 1.12
    for key, era in expected.items():
        if (key[1], key[0]) not in lessons:
            raise ValueError(f"Expected class trainer lesson is absent: {key}")
        if eras.get(key) != era:
            raise ValueError(f"Lesson {key} classified as {eras.get(key)}, expected {era}")
    if len(later) * 3 > len(lessons) * 2:
        raise ValueError("Implausibly many later lessons; a source table was not read")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--core-world", type=pathlib.Path, required=True)
    parser.add_argument("--classic-db", type=pathlib.Path, required=True)
    parser.add_argument("--tbc-db", type=pathlib.Path, required=True)
    parser.add_argument("--spell-dbc", type=pathlib.Path, required=True)
    parser.add_argument("--check", action="store_true", help="check the committed header without writing")
    args = parser.parse_args()
    inputs = {"AzerothCore trainer.sql": args.core_world / "trainer.sql",
              "AzerothCore trainer_spell.sql": args.core_world / "trainer_spell.sql",
              "CMaNGOS classic-db Full_DB": args.classic_db,
              "CMaNGOS tbc-db Full_DB": args.tbc_db,
              "WotLK Spell.dbc": args.spell_dbc}
    digests = {name: hashlib.sha256(path.read_bytes()).hexdigest() for name, path in inputs.items()}
    dbc = read_spell_dbc(args.spell_dbc)
    lessons = class_lessons(args.core_world)
    vanilla = obtainable(read_dump(args.classic_db), dbc)
    tbc = obtainable(read_dump(args.tbc_db), dbc)
    later = classify(lessons, vanilla, tbc, dbc)
    check(later, lessons)
    content = header(later, dbc, digests)
    if args.check:
        if not OUTPUT.exists() or OUTPUT.read_text(encoding="utf-8") != content:
            raise SystemExit(f"Generated output differs: {OUTPUT.relative_to(ROOT)}")
    else:
        OUTPUT.write_text(content, encoding="utf-8")
    tbc_count = sum(1 for _, _, era, _ in later if era == 1)
    print(f"Classified {len(lessons)} class trainer lessons: {tbc_count} TBC, {len(later) - tbc_count} WotLK")


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError) as error:
        sys.exit(f"generate-trainer-eras: {error}")
