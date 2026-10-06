#!/usr/bin/env python3
"""Keep LuCI diagnostic queries, RPC allowlists, and ACL methods aligned."""

from __future__ import annotations

import json
import os
import pathlib
import re
import subprocess
import sys
import tempfile


ROOT = pathlib.Path(__file__).resolve().parents[1]
DIAGNOSTICS = ROOT / "luci-app-easytier/htdocs/luci-static/resources/view/easytier/diagnostics.js"
RPC = ROOT / "luci-app-easytier/root/usr/libexec/easytier/rpc"
ACL = ROOT / "luci-app-easytier/root/usr/share/rpcd/acl.d/luci-app-easytier.json"


def fail(message: str) -> None:
    raise ValueError(message)


def check_unknown_operations_are_denied() -> None:
    with tempfile.TemporaryDirectory(prefix="easytier-rpc-contract-") as temporary:
        temp = pathlib.Path(temporary)
        stub_lib = temp / "jshn.sh"
        stub_lib.write_text(
            "json_init() { :; }\n"
            "json_add_boolean() { :; }\n"
            "json_add_string() { :; }\n"
            "json_dump() { :; }\n",
            encoding="utf-8",
        )
        upload_lib = temp / "manage-upload.sh"
        upload_lib.write_text("", encoding="utf-8")
        bin_dir = temp / "bin"
        bin_dir.mkdir()
        uci = bin_dir / "uci"
        uci.write_text("#!/bin/sh\nexit 1\n", encoding="utf-8")
        uci.chmod(0o755)

        rpc_copy = temp / "rpc"
        rpc_source = RPC.read_text(encoding="utf-8").replace(
            ". /usr/share/libubox/jshn.sh", f'. "{stub_lib}"'
        )
        rpc_copy.write_text(rpc_source, encoding="utf-8")
        manage_path = ROOT / "luci-app-easytier/root/usr/libexec/easytier/manage"
        manage_copy = temp / "manage"
        manage_source = manage_path.read_text(encoding="utf-8")
        manage_source = manage_source.replace(". /usr/share/libubox/jshn.sh", f'. "{stub_lib}"')
        manage_source = manage_source.replace(". /usr/share/easytier/manage-upload.sh", f'. "{upload_lib}"')
        manage_copy.write_text(manage_source, encoding="utf-8")

        environment = os.environ.copy()
        environment["PATH"] = str(bin_dir) + os.pathsep + environment.get("PATH", "")
        for script, arguments, expected in (
            (rpc_copy, ["unknown-operation"], 2),
            (rpc_copy, ["conninfo", "unknown-query"], 2),
            (manage_copy, ["unknown-operation"], 1),
        ):
            result = subprocess.run(["sh", str(script), *arguments], env=environment, check=False)
            if result.returncode != expected:
                fail(f"{script.name} {arguments[0]} returned {result.returncode}, expected {expected}")


def main() -> int:
    try:
        diagnostics = DIAGNOSTICS.read_text(encoding="utf-8")
        rpc = RPC.read_text(encoding="utf-8")
        acl = json.loads(ACL.read_text(encoding="utf-8"))["luci-app-easytier"]

        source_block = re.search(r"var sources = \[(.*?)\n\];", diagnostics, re.DOTALL)
        if not source_block:
            fail("diagnostics source list was not found")
        frontend_sources = set(re.findall(r"^\s*\['([^']+)'", source_block.group(1), re.MULTILINE))
        if not frontend_sources:
            fail("diagnostics source list is empty")

        conninfo_block = re.search(r'case "\$key" in(.*?)\n\s*\*\) exit 2 ;;\n\s*esac', rpc, re.DOTALL)
        if not conninfo_block:
            fail("RPC conninfo allowlist or its deny-by-default branch is missing")
        rpc_sources = set(re.findall(r"^\s*([a-z][a-z0-9-]*)\) first=", conninfo_block.group(1), re.MULTILINE))
        if frontend_sources - {"log"} != rpc_sources:
            fail(
                "diagnostics and RPC conninfo sources differ: "
                f"frontend={sorted(frontend_sources - {'log'})}, rpc={sorted(rpc_sources)}"
            )

        if not re.search(r'case "\$1" in.*?\n\s*\*\) exit 2 ;;\n\s*esac\s*$', rpc, re.DOTALL):
            fail("RPC top-level operations must reject unknown operations")

        read_files = acl.get("read", {}).get("file", {})
        if "/usr/libexec/easytier/rpc conninfo *" not in read_files:
            fail("RPC conninfo is missing from the read ACL")
        expected_read_rpc = {
            "/usr/libexec/easytier/rpc status",
            "/usr/libexec/easytier/rpc conninfo *",
            "/usr/libexec/easytier/rpc netinfo",
            "/usr/libexec/easytier/rpc netinfo *",
            "/usr/libexec/easytier/rpc logs *",
        }
        actual_read_rpc = {path for path in read_files if path.startswith("/usr/libexec/easytier/rpc ")}
        if actual_read_rpc != expected_read_rpc:
            fail(f"RPC read ACL operations changed: expected {sorted(expected_read_rpc)}, found {sorted(actual_read_rpc)}")

        expected_manage = {
            "/usr/libexec/easytier/manage clear-logs",
            "/usr/libexec/easytier/manage reset-database",
            "/usr/libexec/easytier/manage install-upload *",
        }
        write_files = acl.get("write", {}).get("file", {})
        actual_manage = {path for path in write_files if path.startswith("/usr/libexec/easytier/manage ")}
        if actual_manage != expected_manage:
            fail(f"manage ACL operations changed: expected {sorted(expected_manage)}, found {sorted(actual_manage)}")

        manage = (ROOT / "luci-app-easytier/root/usr/libexec/easytier/manage").read_text(encoding="utf-8")
        if not re.search(r'case "\$1" in.*?\n\s*\*\) error "Unknown operation" ;;\n\s*esac\s*$', manage, re.DOTALL):
            fail("manage must reject unknown operations")
        check_unknown_operations_are_denied()

        print(f"RPC contract valid: {len(rpc_sources)} diagnostic queries and fixed ACL operations; unknown calls denied.")
    except (OSError, json.JSONDecodeError, KeyError, ValueError) as error:
        print(f"RPC contract check failed: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
