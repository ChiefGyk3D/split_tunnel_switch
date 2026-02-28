# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [3.0.1] - 2025-06-28

### Added
- **`reload` command**: Remove and re-apply all routes in one step, re-reading config
- **Operation timing**: Route operations log duration in milliseconds (e.g., `[28ms]`)
- **Dispatcher cooldown**: 5-second cooldown prevents duplicate rapid-fire NetworkManager events
- **Proper IPv6 address validation**: `validate_ipv6_cidr` now verifies hex:colon address format, not just prefix length

### Fixed
- **`remove_routes_v6` kernel route protection**: IPv6 removal now skips `proto kernel` routes (same fix as IPv4)
- **IPv6 auto-discover parsing**: Fixed interface detection — was getting `noprefixroute` flag instead of actual interface name; now uses `ip -o` format
- **Config `-c`/`--config` flag**: `CONFIG_FILE` was `readonly` before argument parsing, so `-c` was silently ignored; now properly overrides the config path
- **Auto-discover interface filtering**: Excludes `ipv6leakintrf0` (ProtonVPN leak protection), `virbr*`, `docker*`, `br-*`, `veth*` interfaces from subnet discovery
- **`ip route add` error handling**: Route creation errors are now captured and logged with actual error messages instead of being silenced with `2>/dev/null`
- **VPN-up dispatcher `local` keyword**: Removed `local` from cooldown variables in dispatcher entry point (not inside a function)
- **Test suite `((var++))` crash**: Fixed post-increment on zero under `set -e` in test counters (same bug from main script)
- **Shellcheck warnings**: Fixed SC2155 (declare/assign), SC2190 (associative array), SC2120 (unused args)

## [3.0.0] - 2025-06-22

### Added

#### Core Features
- **IPv6 dual-stack support**: Full IPv6 routing alongside IPv4 with `BYPASS_SUBNETS_V6` configuration
- **Include tunnel mode**: New `TUNNEL_MODE="include"` routes only specified subnets through VPN; everything else goes direct
- **Multiple VPN interfaces**: `VPN_INTERFACES` array supports simultaneous VPN connections (e.g., OpenVPN + WireGuard)
- **Route metrics**: `ROUTE_METRIC` setting controls routing priority for bypass routes
- **Auto-discover subnets**: `AUTO_DISCOVER_SUBNETS` detects LAN subnets from physical interfaces and adds them to bypass list

#### Security
- **Kill switch**: `KILL_SWITCH` blocks all non-VPN traffic if VPN drops; supports both `iptables` and `nftables` backends
- **DNS leak prevention**: `DNS_LEAK_PREVENTION` routes specified DNS servers through physical gateway
- **Safe config parsing**: Configuration is parsed line-by-line with `_assign_scalar`/`_assign_array` — `source` and `eval` are never used
- **Strict CIDR validation**: IPv4 octet range checks, IPv6 segment validation, prefix length verification

#### Reliability
- **Route persistence**: Systemd timer (`split-tunnel-persist.timer`) verifies routes every 5 minutes
- **Lock file protection**: Prevents concurrent dispatcher instances via `/var/run/split_tunnel.lock`
- **VPN-down cleanup**: `REMOVE_ROUTES_ON_VPN_DOWN` removes routes and kill switch on VPN disconnect

#### Operations
- **Config validation command**: `validate` checks all settings without modifying routes
- **Dry-run mode**: `test` shows planned actions without applying them
- **Subnet discovery command**: `discover` shows detected LAN subnets
- **Desktop notifications**: `DESKTOP_NOTIFICATIONS` sends notify-send alerts on route changes and failures
- **Verbose mode**: `-v`/`--verbose` flag for detailed diagnostic output
- **Custom config path**: `-c`/`--config` flag to specify alternate config file
- **Connectivity verification**: `VERIFY_CONNECTIVITY` pings specified hosts after route changes
- **Log rotation**: `extras/logrotate.d/split_tunnel` config for weekly rotation with compression
- **Test suite**: Comprehensive `tests/run_tests.sh` with lint, unit, and integration tests
- **Interactive setup wizard**: Completely rewritten `setup.sh` with mode selection, feature configuration, and validation

#### CLI Commands
- `add` — Apply all routes and features
- `remove` — Remove all routes, firewall rules, and DNS routes
- `status` — Show current configuration, routes, and feature states
- `test` — Dry-run mode
- `validate` — Config validation
- `discover` — Auto-discover local subnets
- `kill-switch-on` / `kill-switch-off` — Manual kill switch control
- `version` — Display version
- `help` — Usage information

### Changed
- Complete rewrite of `split_tunnel.sh` from ~300 lines to ~750 lines
- Complete rewrite of `setup.sh` from ~430 lines to ~450 lines with improved UX
- Configuration format updated: single `BYPASS_SUBNET` → array `BYPASS_SUBNETS`
- Configuration format updated: single `VPN_INTERFACE` → array `VPN_INTERFACES`
- Default log file moved to `/var/log/split_tunnel.log`
- Default config directory: `/etc/split_tunnel/`
- Script installed as `99-split-tunnel` (was previously user-defined)
- Config file permissions tightened to 640

### Removed
- Legacy single-value `BYPASS_SUBNET` and `VPN_INTERFACE` settings (use arrays now)
- `source`/`eval`-based config loading

### Migration from 2.x
1. Back up your existing config
2. Run `sudo ./setup.sh install` (preserves existing settings where possible)
3. Update config file:
   - `BYPASS_SUBNET="192.168.1.0/24"` → `BYPASS_SUBNETS=("192.168.1.0/24")`
   - `VPN_INTERFACE="tun0"` → `VPN_INTERFACES=("tun0")`
4. Review new options in `split_tunnel.conf.example`
5. Run `sudo /etc/NetworkManager/dispatcher.d/99-split-tunnel validate`

## [2.0.0] - 2024-12-18

### Added
- Interactive setup wizard with menu-driven interface
- Configuration validation during setup
- Automatic backup of existing configurations
- Support for custom VPN interface names
- Support for custom configuration file paths
- Uninstall functionality with cleanup
- Project structure documentation
- Quick start guide
- Contributing guidelines

### Changed
- Restructured project layout with clear separation of concerns
- Improved error handling and logging
- Enhanced documentation across all files

## [1.1.0]

### Added
- Improved error messages with suggested fixes
- Debug/verbose logging mode
- Support for multiple subnets
- Lock file mechanism to prevent race conditions

### Changed
- Better default gateway detection
- Improved VPN interface detection logic

## [1.0.0]

### Added
- Initial release
- Basic split tunneling via NetworkManager dispatcher
- Single subnet bypass support
- IPv4 routing only
- Basic logging
- Manual installation process
