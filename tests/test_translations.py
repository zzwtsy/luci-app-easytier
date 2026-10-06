#!/usr/bin/env python3

from __future__ import annotations

import importlib.util
import pathlib
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("check_translations", ROOT / "scripts/check_translations.py")
assert SPEC and SPEC.loader
check_translations = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(check_translations)


class TranslationCheckTests(unittest.TestCase):
    def test_new_javascript_string_fails_until_both_catalogs_register_it(self) -> None:
        new_key = ("", "New untranslated string")
        extracted = {new_key}
        catalogs = {
            "POT": set(),
            "Chinese PO": set(),
        }
        self.assertEqual(
            check_translations.missing_catalog_keys(extracted, catalogs),
            {"POT": {new_key}, "Chinese PO": {new_key}},
        )

    def test_registered_key_passes(self) -> None:
        key = ("", "Registered string")
        self.assertEqual(check_translations.missing_catalog_keys({key}, {"POT": {key}, "Chinese PO": {key}}), {})


if __name__ == "__main__":
    unittest.main()
