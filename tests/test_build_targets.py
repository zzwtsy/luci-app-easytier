#!/usr/bin/env python3

from __future__ import annotations

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
