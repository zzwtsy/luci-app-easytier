#!/usr/bin/env python3
"""Validate and expand the repository's OpenWrt target manifest."""

from __future__ import annotations

import argparse
import json
import pathlib
import re
import sys
from typing import Any


ROOT = pathlib.Path(__file__).resolve().parents[1]
MANIFEST = ROOT / "config/build-targets.json"
RELEASE_WORKFLOW = ROOT / ".github/workflows/build.yml"


def load_manifest(path: pathlib.Path = MANIFEST) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def workflow_architecture_options(workflow: str) -> list[str]:
    lines = workflow.splitlines()
    input_line = next(
        (index for index, line in enumerate(lines) if line == "      architecture:"),
        None,
    )
    if input_line is None:
        raise ValueError("workflow_dispatch architecture input is missing")

    options_line = next(
        (index for index in range(input_line + 1, len(lines)) if lines[index] == "        options:"),
        None,
    )
    if options_line is None:
        raise ValueError("workflow_dispatch architecture options are missing")

    options: list[str] = []
    for line in lines[options_line + 1 :]:
        match = re.fullmatch(r"          - ([A-Za-z0-9_.-]+)", line)
        if not match:
            break
        options.append(match.group(1))
    return options


def validate_manifest(data: dict[str, Any], workflow: str | None = None) -> None:
    if data.get("schema_version") != 1:
        raise ValueError("unsupported build target manifest schema_version")

    sdks = data.get("sdks")
    if not isinstance(sdks, list) or not sdks:
        raise ValueError("sdks must be a non-empty array")
    sdk_versions = [sdk.get("version") for sdk in sdks]
    if len(sdk_versions) != len(set(sdk_versions)) or any(not version for version in sdk_versions):
        raise ValueError("SDK versions must be present and unique")
    for sdk in sdks:
        if sdk.get("package_format") not in {"ipk", "apk"}:
            raise ValueError(f"unsupported package format for SDK {sdk.get('version')}")
        expected_separator = "_" if sdk["package_format"] == "ipk" else "-"
        if sdk.get("package_separator") != expected_separator:
            raise ValueError(f"invalid package separator for SDK {sdk['version']}")
        if not isinstance(sdk.get("stable"), bool):
            raise ValueError(f"stable must be boolean for SDK {sdk['version']}")

    release_arches = data.get("release_architectures")
    smoke_arches = data.get("pr_smoke_architectures")
    priority_arches = data.get("pr_smoke_priority_architectures")
    for name, arches in (
        ("release_architectures", release_arches),
        ("pr_smoke_architectures", smoke_arches),
        ("pr_smoke_priority_architectures", priority_arches),
    ):
        if not isinstance(arches, list) or not arches:
            raise ValueError(f"{name} must be a non-empty array")
        if len(arches) != len(set(arches)) or any(not isinstance(arch, str) or not arch for arch in arches):
            raise ValueError(f"{name} must contain unique non-empty strings")
    if not set(smoke_arches).issubset(release_arches):
        raise ValueError("PR smoke architectures must be present in release_architectures")
    if not set(priority_arches).issubset(smoke_arches):
        raise ValueError("priority smoke architectures must be present in pr_smoke_architectures")

    if workflow is not None:
        actual = workflow_architecture_options(workflow)
        expected = ["all", *release_arches]
        if actual != expected:
            raise ValueError(
                "workflow_dispatch architecture options do not match the manifest: "
                f"expected {expected}, found {actual}"
            )


def build_matrix(data: dict[str, Any], kind: str, selected: str = "all") -> list[dict[str, str | bool]]:
    sdks = data["sdks"]
    if kind == "release":
        architectures = data["release_architectures"]
        if selected != "all":
            if selected not in architectures:
                raise ValueError(f"unsupported architecture: {selected}")
            architectures = [selected]
    elif kind == "pr-priority":
        architectures = data["pr_smoke_priority_architectures"]
    elif kind == "pr-remaining":
        priority = set(data["pr_smoke_priority_architectures"])
        architectures = [arch for arch in data["pr_smoke_architectures"] if arch not in priority]
    else:
        raise ValueError(f"unsupported matrix kind: {kind}")
    return [
        {
            "arch": arch,
            "sdk": sdk["version"],
            "package_format": sdk["package_format"],
            "stable": sdk["stable"],
        }
        for arch in architectures
        for sdk in sdks
    ]


def write_github_output(path: pathlib.Path, key: str, value: str) -> None:
    with path.open("a", encoding="utf-8") as output:
        output.write(f"{key}={value}\n")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)

    check_parser = subparsers.add_parser("check", help="validate the manifest and workflow options")
    check_parser.add_argument("--manifest", type=pathlib.Path, default=MANIFEST)
    check_parser.add_argument("--workflow", type=pathlib.Path, default=RELEASE_WORKFLOW)

    matrix_parser = subparsers.add_parser("matrix", help="write a GitHub Actions build matrix")
    matrix_parser.add_argument("--kind", choices=("release", "pr-priority", "pr-remaining"), required=True)
    matrix_parser.add_argument("--selected", default="all")
    matrix_parser.add_argument("--github-output", type=pathlib.Path, required=True)

    sdk_parser = subparsers.add_parser("sdk-field", help="print one SDK metadata field")
    sdk_parser.add_argument("version")
    sdk_parser.add_argument("field", choices=("package_format", "package_separator", "stable"))

    subparsers.add_parser("sdk-list", help="print SDK metadata as tab-separated rows")
    subparsers.add_parser("summary", help="print release architecture, SDK, and stable SDK counts")

    args = parser.parse_args()
    try:
        data = load_manifest(getattr(args, "manifest", MANIFEST))
        if args.command == "check":
            validate_manifest(data, args.workflow.read_text(encoding="utf-8"))
            print(
                f"Build manifest valid: {len(data['release_architectures'])} architectures, "
                f"{len(data['sdks'])} SDKs, "
                f"{len(data['release_architectures']) * len(data['sdks'])} release targets."
            )
        elif args.command == "matrix":
            validate_manifest(data, RELEASE_WORKFLOW.read_text(encoding="utf-8"))
            matrix = build_matrix(data, args.kind, args.selected)
            matrix_output = {"include": matrix}
            write_github_output(
                args.github_output,
                "build_matrix",
                json.dumps(matrix_output, separators=(",", ":")),
            )
            write_github_output(args.github_output, "expected_artifact_count", str(len(matrix)))
        elif args.command == "sdk-list":
            validate_manifest(data)
            for sdk in data["sdks"]:
                print(
                    "\t".join(
                        (
                            sdk["version"],
                            sdk["package_format"],
                            sdk["package_separator"],
                            str(sdk["stable"]).lower(),
                        )
                    )
                )
        elif args.command == "summary":
            validate_manifest(data)
            stable_sdks = sum(1 for sdk in data["sdks"] if sdk["stable"])
            print(f"{len(data['release_architectures'])}\t{len(data['sdks'])}\t{stable_sdks}")
        else:
            sdk = next((item for item in data["sdks"] if item["version"] == args.version), None)
            if sdk is None:
                raise ValueError(f"unsupported SDK version: {args.version}")
            value = sdk[args.field]
            print(str(value).lower() if isinstance(value, bool) else value)
    except (OSError, json.JSONDecodeError, KeyError, TypeError, ValueError) as error:
        print(f"build target check failed: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
