"""Authored historical text translations; numeric values come from the dataset.

Catalogs contain normalized English templates rather than one copy per rank.
Only display text is translated. Spell IDs, mechanics and protocol keys stay
unchanged, and an untranslated locale uses the authored English text.
"""
from __future__ import annotations

from collections import Counter
from functools import lru_cache
import json
from pathlib import Path
import re

LOCALE_ROOT = Path(__file__).resolve().parent.parent / "era-data" / "locales"
CLASS_NAMES = {1: "warrior", 2: "paladin", 3: "hunter", 4: "rogue",
               5: "priest", 7: "shaman", 8: "mage", 9: "warlock", 11: "druid"}
TOKEN_RE = re.compile(r"\$\{[^}]*\}|\$[a-zA-Z]+[^\s.;,]*:[^\s.;,]*;|\$[A-Za-z0-9]+|(?<![\w])(?:\d+(?:\.\d+)?|\.\d+)")
PLACEHOLDER_RE = re.compile(r"(?<!\$)\{(\d+)\}")


def normalize(text: str) -> tuple[str, list[str]]:
    values = []

    def replace(match):
        token = match.group()
        if token.startswith("$"):
            return token
        values.append(token)
        return "{" + str(len(values) - 1) + "}"

    return TOKEN_RE.sub(replace, text), values


def validate_template(english: str, translated: str) -> None:
    if not isinstance(translated, str) or not translated.strip():
        raise ValueError(f"Empty or invalid German translation: {english}")
    if Counter(PLACEHOLDER_RE.findall(english)) != Counter(PLACEHOLDER_RE.findall(translated)):
        raise ValueError(f"Translation changed numeric placeholders: {english}")
    def tokens(value):
        result = Counter()
        for match in TOKEN_RE.finditer(value):
            token = match.group()
            if not token.startswith("$"):
                continue
            # $l chooses singular/plural display words. Translate the words but
            # preserve the client operator; numeric and spell-reference tokens
            # (including ${...} formulas) remain byte-for-byte identical.
            if re.fullmatch(r"\$l[^:;]+:[^:;]+;", token):
                token = "$l:;"
            result[token] += 1
        return result
    if tokens(english) != tokens(translated):
        raise ValueError(f"Translation changed WoW tooltip tokens: {english}")
    # Numbers are supplied by the authored text, never hard-coded into a catalog.
    without_placeholders = PLACEHOLDER_RE.sub("", translated)
    if any(not m.group().startswith("$") for m in TOKEN_RE.finditer(without_placeholders)):
        raise ValueError(f"Translation introduced a literal numeric value: {english}")


def _unique_entries(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError(f"Duplicate German catalog key: {key}")
        result[key] = value
    return result


@lru_cache(maxsize=9)
def catalog(class_id: int) -> dict[str, str]:
    name = CLASS_NAMES.get(int(class_id))
    if name is None:
        return {}
    path = LOCALE_ROOT / "deDE" / (name + ".json")
    if not path.is_file():
        return {}
    result = json.loads(path.read_text(encoding="utf-8"), object_pairs_hook=_unique_entries)
    if not isinstance(result, dict):
        raise ValueError(f"Invalid German catalog: {path.name}")
    for english, translated in result.items():
        validate_template(english, translated)
    return result


def translate(text: str, class_id: int, locale: str = "deDE") -> str:
    if not text or locale != "deDE":
        return text
    template, values = normalize(text)
    if template in ("Passive", "Shapeshift"):
        translated = {"Passive": "Passiv", "Shapeshift": "Gestaltwandlung"}[template]
    elif re.fullmatch(r"Rank \{0\}", template):
        translated = "Rang {0}"
    else:
        translated = catalog(class_id).get(template)
    if translated is None:
        return text
    # Avoid str.format: WoW has its own ${...} expressions containing braces.
    def replace(match):
        value = values[int(match.group(1))]
        if value.startswith("."):
            value = "0" + value
        return value.replace(".", ",")

    return PLACEHOLDER_RE.sub(replace, translated)


def catalog_files() -> list[Path]:
    return sorted((LOCALE_ROOT / "deDE").glob("*.json"))
