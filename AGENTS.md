# Repository guide for coding agents

This repository is an OpenWrt feed for the EasyTier core packages and LuCI app. Keep OpenWrt package, LuCI, UCI, rpcd ACL, procd, and firewall conventions intact. Do not change user-facing UCI keys, RPC operations, ACL permissions, package names, or release naming without an explicit requirement.

## Where to work

- `easytier/`, `easytier-noweb/`: core package definitions; shared download and install logic is in `easytier/common.mk`.
- `luci-app-easytier/htdocs/`: LuCI pages and shared JavaScript.
- `luci-app-easytier/root/`: installed defaults, init entry point, RPC/manage helpers, and firewall helpers.
- `luci-app-easytier/po/`: gettext template and translations.
- `tests/`, `scripts/`, `.github/scripts/`: host checks, shared validation, and CI/release helpers.
- `version.mk`, `config/build-targets.json`: package versions/checksums and supported build targets.

## Safety and validation

- Keep page input out of shell command strings. Validate helper arguments and preserve the RPC action allowlist and least-privilege ACL.
- Pass service arguments as separate values to procd; do not use `eval`, `sh -c`, or background-process management.
- Keep archive extraction path-safe and transactional. Never bypass package checksum verification.
- Follow [DEVELOPMENT.md](DEVELOPMENT.md) for cross-file change maps and OpenWrt-specific requirements.
- Run `npm ci && npm run check` after installing the development tools (`shellcheck` and GNU gettext). The network-dependent ARM ABI check is run separately by CI with `.github/scripts/check-arm-abi.sh`.
