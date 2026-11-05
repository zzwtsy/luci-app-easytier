#!/usr/bin/env python3
"""Exercise feed assembly with opaque package/signature fixtures, without signing."""

from __future__ import annotations

import gzip
import hashlib
import json
import pathlib
import shutil
import subprocess
import tempfile
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]
REQUIRED_PACKAGES = (
    "easytier",
    "easytier-noweb",
    "luci-app-easytier",
    "luci-i18n-easytier-zh-cn",
)


class FeedSiteTests(unittest.TestCase):
    def setUp(self) -> None:
        temporary = tempfile.TemporaryDirectory(prefix="easytier-feed-test-")
        self.addCleanup(temporary.cleanup)
        self.repo = pathlib.Path(temporary.name) / "repo"
        for name in (
            ".github/scripts/assemble-feed-site.sh",
            ".github/workflows/build.yml",
            ".github/pages/index.html",
            ".github/pages/keys/easytier-opkg.pub",
            ".github/pages/keys/easytier-apk.pem",
            "scripts/build_targets.py",
            "config/build-targets.json",
        ):
            destination = self.repo / name
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(ROOT / name, destination)

        self.manifest_path = self.repo / "config/build-targets.json"
        self.manifest = json.loads(self.manifest_path.read_text(encoding="utf-8"))
        self.artifacts = self.repo / "artifacts"
        self.artifacts.mkdir()
        for arch in self.manifest["release_architectures"]:
            for sdk in self.manifest["sdks"]:
                self._write_artifact(arch, sdk)

    def _write_artifact(self, arch: str, sdk: dict) -> None:
        artifact = self.artifacts / f"{arch}-{sdk['version']}"
        artifact.mkdir()
        records = []
        for package in REQUIRED_PACKAGES:
            filename = f"{package}{sdk['package_separator']}1.0-r1.{sdk['package_format']}"
            content = f"Opaque package fixture: {artifact.name}/{package}\n".encode()
            (artifact / filename).write_bytes(content)
            records.append(
                f"Package: {package}\n"
                f"Filename: {filename}\n"
                f"Size: {len(content)}\n"
                f"SHA256sum: {hashlib.sha256(content).hexdigest()}\n"
            )

        if sdk["package_format"] == "ipk":
            index = "\n".join(records).encode()
            (artifact / "Packages").write_bytes(index)
            (artifact / "Packages.gz").write_bytes(gzip.compress(index, mtime=0))
            (artifact / "Packages.sig").write_bytes(b"Opaque signature fixture\n")
        else:
            # Assembly copies this signed index; it does not interpret or verify it.
            (artifact / "packages.adb").write_bytes(
                f"Opaque APK signed index fixture: {artifact.name}\n".encode()
            )

    def _assemble(self, name: str = "site") -> tuple[subprocess.CompletedProcess, pathlib.Path]:
        site = self.repo / name
        result = subprocess.run(
            ["bash", str(self.repo / ".github/scripts/assemble-feed-site.sh"),
             str(self.artifacts), str(site)],
            cwd=self.repo,
            capture_output=True,
            text=True,
            timeout=30,
            check=False,
        )
        return result, site

    def _assert_site_matches_artifacts(self, site: pathlib.Path) -> None:
        expected_roots = set()
        for sdk in self.manifest["sdks"]:
            if not sdk["stable"]:
                self.assertFalse((site / "feeds" / sdk["version"]).exists())
                continue
            paths = [sdk["feed_path"], *sdk["feed_aliases"]]
            expected_roots.update(paths)
            for feed_path in paths:
                feed_root = site / "feeds" / feed_path
                self.assertEqual(
                    {path.name for path in feed_root.iterdir()},
                    set(self.manifest["release_architectures"]),
                )
                for arch in self.manifest["release_architectures"]:
                    artifact = self.artifacts / f"{arch}-{sdk['version']}"
                    destination = feed_root / arch / "packages_ci"
                    expected_files = {path.name for path in artifact.iterdir()}
                    self.assertEqual({path.name for path in destination.iterdir()}, expected_files)
                    for name in expected_files:
                        self.assertEqual(
                            (destination / name).read_bytes(),
                            (artifact / name).read_bytes(),
                            f"Published file differs from artifact: {destination / name}",
                        )

        self.assertEqual({path.name for path in (site / "feeds").iterdir()}, expected_roots)
        for path in site.rglob("*"):
            self.assertFalse(path.is_symlink(), f"Pages contains a symbolic link: {path}")
            if path.is_file():
                self.assertEqual(path.stat().st_nlink, 1, f"Pages contains a hard link: {path}")

    def test_series_feed_and_legacy_paths_publish_independent_copies(self) -> None:
        stable = {sdk["version"]: sdk for sdk in self.manifest["sdks"] if sdk["stable"]}
        self.assertEqual(stable["24.10.8"]["feed_path"], "24.10.8")
        self.assertEqual(stable["24.10.8"]["feed_aliases"], [])
        self.assertEqual(stable["25.12.5"]["feed_path"], "25.12")
        self.assertIn("25.12.5", stable["25.12.5"]["feed_aliases"])

        result, site = self._assemble()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self._assert_site_matches_artifacts(site)

    def test_sdk_upgrade_preserves_series_and_previous_alias(self) -> None:
        sdk = next(item for item in self.manifest["sdks"] if item["version"] == "25.12.5")
        sdk["version"] = "25.12.6"
        self.manifest_path.write_text(json.dumps(self.manifest), encoding="utf-8")
        for arch in self.manifest["release_architectures"]:
            (self.artifacts / f"{arch}-25.12.5").rename(self.artifacts / f"{arch}-25.12.6")

        result, site = self._assemble()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self._assert_site_matches_artifacts(site)
        self.assertTrue((site / "feeds/25.12.5").is_dir())
        self.assertFalse((site / "feeds/25.12.6").exists())

        matrix_output = self.repo / "matrix-output"
        result = subprocess.run(
            ["python3", str(self.repo / "scripts/build_targets.py"), "matrix",
             "--kind", "release", "--github-output", str(matrix_output)],
            cwd=self.repo,
            capture_output=True,
            text=True,
            timeout=30,
            check=False,
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        outputs = dict(line.split("=", 1) for line in matrix_output.read_text().splitlines())
        matrix = json.loads(outputs["build_matrix"])["include"]
        self.assertEqual(
            {(item["arch"], item["sdk"]) for item in matrix},
            {(arch, item["version"]) for arch in self.manifest["release_architectures"]
             for item in self.manifest["sdks"]},
        )
        self.assertTrue(all((self.artifacts / f"{item['arch']}-{item['sdk']}").is_dir()
                            for item in matrix))

    def test_missing_required_packages_and_indexes_are_rejected(self) -> None:
        arch = self.manifest["release_architectures"][0]
        case_number = 0
        for sdk in self.manifest["sdks"]:
            if not sdk["stable"]:
                continue
            artifact = self.artifacts / f"{arch}-{sdk['version']}"
            package = artifact / f"easytier{sdk['package_separator']}1.0-r1.{sdk['package_format']}"
            index_names = (
                ("Packages", "Packages.gz", "Packages.sig")
                if sdk["package_format"] == "ipk" else ("packages.adb",)
            )
            missing_files = [(package, "Missing easytier package")]
            missing_files.extend((artifact / name, f"Missing {name}") for name in index_names)
            for missing, message in missing_files:
                case_number += 1
                with self.subTest(sdk=sdk["version"], missing=missing.name):
                    content = missing.read_bytes()
                    missing.unlink()
                    try:
                        result, _ = self._assemble(f"missing-file-{case_number}")
                        self.assertNotEqual(result.returncode, 0)
                        self.assertIn(message, result.stderr)
                    finally:
                        missing.write_bytes(content)

    def test_opkg_index_package_integrity_is_still_checked(self) -> None:
        sdk = next(
            item for item in self.manifest["sdks"]
            if item["stable"] and item["package_format"] == "ipk"
        )
        arch = self.manifest["release_architectures"][0]
        artifact = self.artifacts / f"{arch}-{sdk['version']}"
        package = next(artifact.glob("*.ipk"))
        original = package.read_bytes()
        package.write_bytes(b"!" + original[1:])

        result, _ = self._assemble()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Package SHA256 mismatch", result.stderr)


if __name__ == "__main__":
    unittest.main()
