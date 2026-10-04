#!/usr/bin/env python3
import gzip
import hashlib
import json
import pathlib
import re
import sys

mode, directory = sys.argv[1:]
feed = pathlib.Path(directory).resolve()
required = {
    "easytier",
    "easytier-noweb",
    "luci-app-easytier",
    "luci-i18n-easytier-zh-cn",
}

if mode == "opkg":
    index = gzip.decompress((feed / "Packages.gz").read_bytes()).decode("utf-8")
    packages = []
    for record in index.strip().split("\n\n"):
        fields = dict(re.findall(r"^([^:]+):\s*(.*)$", record, re.MULTILINE))
        if "Package" in fields:
            packages.append({
                "name": fields["Package"],
                "filename": fields.get("Filename", "").removeprefix("./"),
                "size": int(fields.get("Size", "-1")),
                "sha256": fields.get("SHA256sum", ""),
            })
elif mode == "apk":
    data = json.load(sys.stdin)
    packages = [
        {
            "name": item.get("name", ""),
            "filename": f"{item.get('name', '')}-{item.get('version', '')}.apk",
            "size": int(item.get("file-size", -1)),
            # APK's `hashes` field is a package identity, not a SHA256 of the
            # complete .apk file. The signed index is verified separately.
            "sha256": None,
        }
        for item in data.get("packages", [])
    ]
else:
    raise SystemExit(f"Unknown package index format: {mode}")

found = set()
for item in packages:
    name = item["name"]
    filename = item["filename"]
    found.add(name)
    package = (feed / filename).resolve()
    if not filename or not package.is_relative_to(feed) or not package.is_file():
        raise SystemExit(f"Index references a missing or unsafe package: {filename}")
    if package.stat().st_size != item["size"]:
        raise SystemExit(f"Package size mismatch: {filename}")
    if item["sha256"] is not None:
        digest = hashlib.sha256(package.read_bytes()).hexdigest()
        if digest != item["sha256"]:
            raise SystemExit(f"Package SHA256 mismatch: {filename}")

missing = required - found
if missing:
    raise SystemExit(f"Feed index is missing package records: {', '.join(sorted(missing))}")
