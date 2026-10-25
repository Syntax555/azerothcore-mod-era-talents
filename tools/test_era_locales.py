"""German historical-text coverage, safety and generated-artifact regressions."""
from collections import Counter
from decimal import Decimal
import json
from pathlib import Path
import re
import sys
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parent))
import era_locales as L
import gen_era_talents as G
import build_client_dbc as B

ROOT = Path(__file__).resolve().parent.parent


def datasets():
    for line in (ROOT / "era-data/datasets.txt").read_text().splitlines():
        if line.strip() and not line.lstrip().startswith("#"):
            yield ROOT / "era-data" / line.split()[0]


def texts(data):
    for tab, node in G._nodes(data):
        yield tab["name"]
        yield node["name"]
        yield from node.get("tooltip", [])
    for helper in data.get("helpers", []):
        client = helper.get("client")
        if client:
            yield client.get("name", helper["name"])
            yield client.get("description", "")
            yield client.get("auraDescription", "")
    yield from G.build_spell_mods(data)
    yield from data.get("clientCastTimeBase", {})


class LocaleTests(unittest.TestCase):
    def test_every_authored_display_string_has_a_german_template(self):
        seen_classes, missing = set(), []
        for path in datasets():
            data = G._load(str(path))
            class_id = int(data["class"])
            seen_classes.add(class_id)
            catalog = L.catalog(class_id)
            self.assertTrue(catalog, path.name)
            for text in texts(data):
                if text and L.normalize(text)[0] not in catalog:
                    missing.append((str(path.relative_to(ROOT)), text))
        self.assertEqual(seen_classes, set(L.CLASS_NAMES))
        self.assertEqual(missing, [], f"Missing authored German text: {missing[:8]}")

    def test_numeric_values_and_tooltip_tokens_are_preserved(self):
        for path in datasets():
            data = G._load(str(path))
            for english in texts(data):
                if not english:
                    continue
                german = L.translate(english, int(data["class"]))
                original, values = L.normalize(english)
                # German uses decimal commas. Extract entire numeric values,
                # excluding client $tokens/formulas, and compare their values.
                numeric = re.compile(r"\$\{[^}]*\}|\$[a-zA-Z]+[^\s.;,]*:[^\s.;,]*;|\$[A-Za-z0-9]+|(?<![\w])(?:\d+(?:[.,]\d+)?|[.,]\d+)")
                def amounts(text):
                    return Counter(Decimal(m.group().replace(",", ".")) for m in numeric.finditer(text)
                                   if not m.group().startswith("$"))
                self.assertEqual(amounts(english), amounts(german), english)
                self.assertEqual(english.count("%"), german.count("%"), english)
                L.validate_template(original, L.catalog(int(data["class"]))[original])

    def test_translation_cannot_change_effect_parameters(self):
        cases = [("Damage {0}%.", "Schaden {1}%."),
                 ("Damage $s1%.", "Schaden $s2%."),
                 ("Damage ${$m1*$m3/100}.", "Schaden ${$m1*$m3/200}."),
                 ("Duration {0}.", "Dauer 15."),
                 ("Name", "")]
        for english, german in cases:
            with self.subTest(english=english):
                with self.assertRaises(ValueError):
                    L.validate_template(english, german)
        L.validate_template("$s1 combo $lpoint:points;.", "$s1 Combo$lpunkt:punkte;.")

    def test_rank_fallback_and_token_substitution(self):
        self.assertEqual(L.translate("Rank 7", 8), "Rang 7")
        text = "$s1% plus ${$m1*$m3/100} for 1.50 sec."
        template, values = L.normalize(text)
        self.assertEqual(values, ["1.50"])
        german = "$s1% plus ${$m1*$m3/100} für {0} Sek."
        with patch.object(L, "catalog", return_value={template: german}):
            self.assertEqual(L.translate(text, 8), "$s1% plus ${$m1*$m3/100} für 1,50 Sek.")
        self.assertEqual(L.translate(text, 8, "frFR"), text)
        self.assertEqual(L.translate("Unknown text", 99), "Unknown text")

    def test_generated_trees_are_current_and_keep_gameplay_ids(self):
        for path in datasets():
            data = G._load(str(path))
            era = "TBC" if int(data["era"]) == 1 else "Vanilla"
            output = ROOT / "client-addon/EraTalents/data/generated" / (path.stem.title() + era + ".lua")
            generated = G.emit_lua(data)
            self.assertEqual(generated, output.read_text(), output.name)
            for _, node in G._nodes(data):
                self.assertIn(f"id={int(node['id'])},", generated)
                self.assertIn(G._lua_str(L.translate(node["name"], int(data["class"]))), generated)

    def test_custom_locales_do_not_change_non_text_spell_fields(self):
        row = G._row_values({"ID": 932760, "Name_Lang_enUS": "Arcane Power",
                             "Description_Lang_enUS": "", "EffectBasePoints_1": 29})
        english = B._client_locale_fallbacks(list(row))
        german = B._client_locale_fallbacks(list(row), {"class": 8})
        localized_fields = {B._IDX[group + "_enUS"] + 3 for group in
                            ("Name_Lang", "NameSubtext_Lang", "Description_Lang", "AuraDescription_Lang")}
        for index, value in enumerate(german):
            if index not in localized_fields:
                self.assertEqual(value, english[index], index)
        self.assertEqual(german[B._IDX["Name_Lang_enUS"] + 3], "Arkane Macht")
        for offset in (B._IDX["NameSubtext_Lang_enUS"], B._IDX["Description_Lang_enUS"],
                       B._IDX["AuraDescription_Lang_enUS"]):
            self.assertEqual(german[offset + 3], english[offset])
        marker = B._sentinel_row("1234abcd")
        self.assertEqual({marker[B._IDX["Name_Lang_enUS"] + locale] for locale in range(16)},
                         {"EraTalents Gen 1234abcd"})

    def test_catalog_changes_invalidate_client_generation(self):
        from tempfile import TemporaryDirectory
        paths = [str(p) for p in datasets()]
        before = G.generation_stamp(paths)
        with TemporaryDirectory() as directory:
            path = Path(directory) / "changed.json"
            path.write_text(json.dumps({"Arcane Power": "Arkane Macht"}))
            with patch.object(L, "catalog_files", return_value=[path]):
                self.assertNotEqual(before, G.generation_stamp(paths))

    def test_helpers_do_not_inherit_other_era_descriptions(self):
        from tempfile import TemporaryDirectory
        import yaml
        data = {"era": 0, "class": 8, "tabs": [], "helpers": [
            {"id": 932760, "name": "Arcane Power", "template": 12042,
             "effects": [{"effect": 2, "basePoints": 29}],
             "client": {"name": "Arcane Power", "icon": 62}}]}
        template = G._row_values({"ID": 12042, "Description_Lang_enUS": "Wrong Wrath effect.",
                                  "AuraDescription_Lang_enUS": "Unrelated Wrath aura."})
        with TemporaryDirectory() as directory:
            path = Path(directory) / "mage.yaml"
            path.write_text(yaml.safe_dump(data))
            row = B._client_rows([str(path)], {12042: template})[932760]
            self.assertEqual(row[B._IDX["Description_Lang_enUS"]], "")
            self.assertEqual(row[B._IDX["AuraDescription_Lang_enUS"]], "")
            data["helpers"][0]["client"]["auraDescription"] = "Spell damage increased by 30%."
            path.write_text(yaml.safe_dump(data))
            row = B._client_rows([str(path)], {12042: template})[932760]
            self.assertEqual(row[B._IDX["Description_Lang_enUS"]], "Spell damage increased by 30%.")
            self.assertEqual(row[B._IDX["Description_Lang_enUS"] + 3],
                             L.translate("Spell damage increased by 30%.", 8))


if __name__ == "__main__":
    unittest.main()
