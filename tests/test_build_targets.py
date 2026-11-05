#!/usr/bin/env python3

from __future__ import annotations

import copy
import importlib.util
import pathlib
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("build_targets", ROOT / "scripts/build_targets.py")
assert SPEC and SPEC.loader
build_targets = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(build_targets)


class BuildTargetTests(unittest.TestCase):
    def setUp(self) -> None:
        self.manifest = build_targets.load_manifest()
        self.workflow = build_targets.RELEASE_WORKFLOW.read_text(encoding="utf-8")

    def test_dispatch_choices_match_release_manifest(self) -> None:
        build_targets.validate_manifest(self.manifest, self.workflow)

    def test_mismatched_dispatch_choice_is_rejected(self) -> None:
        broken_workflow = self.workflow.replace("          - x86_64", "          - not_a_target")
        with self.assertRaisesRegex(ValueError, "do not match"):
            build_targets.validate_manifest(self.manifest, broken_workflow)

    def test_release_matrix_has_expected_product(self) -> None:
        matrix = build_targets.build_matrix(self.manifest, "release")
        self.assertEqual(len(matrix), len(self.manifest["release_architectures"]) * len(self.manifest["sdks"]))
        formats = {sdk["version"]: sdk["package_format"] for sdk in self.manifest["sdks"]}
        self.assertTrue(all(item["package_format"] == formats[item["sdk"]] for item in matrix))

    def test_feed_directory_does_not_replace_sdk_in_matrix(self) -> None:
        matrix = build_targets.build_matrix(self.manifest, "release", "x86_64")
        self.assertEqual(
            [item["sdk"] for item in matrix],
            [sdk["version"] for sdk in self.manifest["sdks"]],
        )

    def test_stable_sdk_requires_explicit_feed_metadata(self) -> None:
        for field in ("feed_path", "feed_aliases"):
            with self.subTest(field=field):
                manifest = copy.deepcopy(self.manifest)
                del manifest["sdks"][0][field]
                with self.assertRaisesRegex(ValueError, "feed"):
                    build_targets.validate_manifest(manifest)

    def test_unsafe_feed_paths_are_rejected(self) -> None:
        for path in ("", ".", "..", "../25.12", "/25.12", "25.12/other", "25.12,other", "25.12\tother", None):
            for field in ("feed_path", "feed_aliases"):
                with self.subTest(path=path, field=field):
                    manifest = copy.deepcopy(self.manifest)
                    manifest["sdks"][0][field] = [path] if field == "feed_aliases" else path
                    with self.assertRaisesRegex(ValueError, "invalid feed path"):
                        build_targets.validate_manifest(manifest)

    def test_duplicate_feed_destinations_are_rejected(self) -> None:
        cases = (
            {"feed_path": "24.10.8"},
            {"feed_aliases": ["25.12"]},
            {"feed_aliases": ["25.12.5", "25.12.5"]},
            {"feed_aliases": ["24.10.8"]},
        )
        for fields in cases:
            with self.subTest(fields=fields):
                manifest = copy.deepcopy(self.manifest)
                manifest["sdks"][1].update(fields)
                with self.assertRaisesRegex(ValueError, "duplicate feed path"):
                    build_targets.validate_manifest(manifest)

    def test_feed_aliases_must_be_an_array(self) -> None:
        self.manifest["sdks"][0]["feed_aliases"] = "24.10.8"
        with self.assertRaisesRegex(ValueError, "feed_aliases must be an array"):
            build_targets.validate_manifest(self.manifest)

    def test_unstable_sdk_cannot_publish_stable_feeds(self) -> None:
        for field, value in (("feed_path", "SNAPSHOT"), ("feed_aliases", [])):
            with self.subTest(field=field):
                manifest = copy.deepcopy(self.manifest)
                manifest["sdks"][-1][field] = value
                with self.assertRaisesRegex(ValueError, "unstable SDK"):
                    build_targets.validate_manifest(manifest)

    def test_pr_matrix_contains_eight_architectures_for_each_sdk(self) -> None:
        matrix = build_targets.build_matrix(self.manifest, "pr-priority") + build_targets.build_matrix(
            self.manifest, "pr-remaining"
        )
        self.assertEqual(len(matrix), len(self.manifest["pr_smoke_architectures"]) * len(self.manifest["sdks"]))

    def test_unknown_release_architecture_is_rejected(self) -> None:
        with self.assertRaisesRegex(ValueError, "unsupported architecture"):
            build_targets.build_matrix(self.manifest, "release", "unknown")


if __name__ == "__main__":
    unittest.main()
