#!/usr/bin/env python3
"""Fail-closed guard for manually dispatched GitHub releases."""

from __future__ import annotations

import os
import re
import sys
from collections.abc import Callable
from urllib.error import HTTPError, URLError
from urllib.parse import quote
from urllib.request import Request, urlopen

TAG_PATTERN = re.compile(r"[A-Za-z0-9._+-]+\Z")
StatusRequest = Callable[[str, str], int]


class ReleaseValidationError(RuntimeError):
    """Raised when a release is unsafe or cannot be checked reliably."""


def request_status(url: str, token: str) -> int:
    request = Request(
        url,
        headers={
            "Accept": "application/vnd.github+json",
            "Authorization": f"Bearer {token}",
            "X-GitHub-Api-Version": "2022-11-28",
        },
    )
    try:
        with urlopen(request, timeout=20) as response:
            return response.status
    except HTTPError as error:
        return error.code
    except (URLError, TimeoutError, OSError) as error:
        raise ReleaseValidationError(f"GitHub API request failed: {error}") from error


def validate_release(
    *,
    tag: str,
    git_ref: str,
    default_branch: str,
    repository: str = "",
    api_url: str = "",
    token: str = "",
    status_request: StatusRequest = request_status,
) -> None:
    """Validate a release request; an empty tag means build-only mode."""
    if not tag:
        return

    if not TAG_PATTERN.fullmatch(tag):
        raise ReleaseValidationError("Tag contains unsupported characters.")
    if not default_branch:
        raise ReleaseValidationError("Repository default branch is missing.")
    expected_ref = f"refs/heads/{default_branch}"
    if git_ref != expected_ref:
        raise ReleaseValidationError(
            f"Release publishing must run from the default branch ({expected_ref})."
        )
    if not repository or "/" not in repository:
        raise ReleaseValidationError("GITHUB_REPOSITORY is missing or invalid.")
    if not api_url or not token:
        raise ReleaseValidationError("GitHub API URL or read token is missing.")

    repository_path = quote(repository, safe="/")
    tag_path = quote(tag, safe="")
    api_root = api_url.rstrip("/")
    checks = (
        (
            "Git tag",
            f"{api_root}/repos/{repository_path}/git/ref/tags/{tag_path}",
        ),
        (
            "GitHub Release",
            f"{api_root}/repos/{repository_path}/releases/tags/{tag_path}",
        ),
    )

    for label, url in checks:
        try:
            status = status_request(url, token)
        except ReleaseValidationError:
            raise
        except Exception as error:  # Fail closed for unexpected transport errors.
            raise ReleaseValidationError(f"Could not check {label}: {error}") from error

        if status == 404:
            continue
        if 200 <= status < 300:
            raise ReleaseValidationError(f"{label} '{tag}' already exists.")
        raise ReleaseValidationError(
            f"Could not check {label} '{tag}': GitHub API returned HTTP {status}."
        )


def main() -> int:
    try:
        validate_release(
            tag=os.environ.get("RELEASE_TAG", ""),
            git_ref=os.environ.get("GITHUB_REF", ""),
            default_branch=os.environ.get("DEFAULT_BRANCH", ""),
            repository=os.environ.get("GITHUB_REPOSITORY", ""),
            api_url=os.environ.get("GITHUB_API_URL", ""),
            token=os.environ.get("GITHUB_TOKEN", ""),
        )
    except ReleaseValidationError as error:
        print(f"::error::{error}", file=sys.stderr)
        return 1

    print("Release validation passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
