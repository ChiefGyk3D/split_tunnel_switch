# Project Structure

Overview of all files and directories in the Split Tunnel Switch project (v3.0.0).

```
split_tunnel_switch/
├── split_tunnel.sh              # Main split tunnel script (dispatcher)
├── split_tunnel.conf            # Active config (created by setup.sh; gitignored)
├── split_tunnel.conf.example    # Documented config template
├── setup.sh                     # Interactive setup / management tool
├── README.md                    # Full documentation
├── QUICKSTART.md                # 5-minute getting-started guide
├── CHANGELOG.md                 # Version history
├── CONTRIBUTING.md              # Contributor guidelines
├── PROJECT_STRUCTURE.md         # This file
├── LICENSE                      # GPLv3 license
├── extras/                      # Optional infrastructure files
│   ├── logrotate.d/
│   │   └── split_tunnel         # Logrotate config for /var/log/split_tunnel.log
│   └── systemd/
│       ├── split-tunnel-persist.service   # Oneshot service to re-apply routes
│       └── split-tunnel-persist.timer     # Timer triggering every 5 minutes
└── tests/
    └── run_tests.sh             # Test suite (lint, unit, integration)
```

## File Descriptions

### Core Scripts

| File | Purpose |
|------|---------|
| `split_tunnel.sh` | Main script. Installed to `/etc/NetworkManager/dispatcher.d/99-split-tunnel`. Handles route management, kill switch, DNS leak prevention, auto-discovery, connectivity checks, and desktop notifications. ~750 lines. |
| `setup.sh` | Interactive installer and management tool. Handles install, uninstall, configuration, validation, and test execution. ~450 lines. |

### Configuration

| File | Purpose |
|------|---------|
| `split_tunnel.conf.example` | Comprehensive config template with per-setting documentation. Covers all options: tunnel mode, subnets (v4+v6), VPN interfaces, kill switch, DNS leak prevention, auto-discovery, connectivity, notifications, metrics, logging, and more. |
| `split_tunnel.conf` | User's active config (created by setup or manually). Not tracked in git. Installed to `/etc/split_tunnel/split_tunnel.conf`. |

### Documentation

| File | Purpose |
|------|---------|
| `README.md` | Full project documentation: features, installation, configuration, usage, architecture, troubleshooting, FAQ. |
| `QUICKSTART.md` | Minimal 5-minute setup guide with the essential steps and commands. |
| `CHANGELOG.md` | Version-by-version list of additions, changes, removals, and migration notes. |
| `CONTRIBUTING.md` | Guidelines for contributors: development setup, coding standards, testing requirements, PR process. |
| `PROJECT_STRUCTURE.md` | This file. Maps every file and directory with descriptions. |
| `LICENSE` | GNU General Public License v3.0. |

### Extras

| File | Purpose |
|------|---------|
| `extras/logrotate.d/split_tunnel` | Logrotate configuration: weekly rotation, 4 copies retained, gzip compression, `copytruncate` for seamless rotation. Installed to `/etc/logrotate.d/split_tunnel`. |
| `extras/systemd/split-tunnel-persist.service` | Systemd oneshot service that runs `99-split-tunnel add` to re-apply routes. Includes security hardening (`ProtectSystem`, `ProtectHome`, `PrivateTmp`). |
| `extras/systemd/split-tunnel-persist.timer` | Systemd timer that triggers the service: 60s after boot, then every 5 minutes with randomized 30s delay. Installed to `/etc/systemd/system/`. |

### Tests

| File | Purpose |
|------|---------|
| `tests/run_tests.sh` | Test suite with three categories: **lint** (shellcheck on all .sh files), **unit** (CIDR validation, config parsing, version/help output), **integration** (dry-run, validate, status, discover via the installed script — requires root). ~350 lines. |

## Installation Paths

When installed via `setup.sh`, files are placed at:

| Source | Destination |
|--------|-------------|
| `split_tunnel.sh` | `/etc/NetworkManager/dispatcher.d/99-split-tunnel` |
| `split_tunnel.conf` or `.example` | `/etc/split_tunnel/split_tunnel.conf` |
| `extras/logrotate.d/split_tunnel` | `/etc/logrotate.d/split_tunnel` |
| `extras/systemd/*.service` | `/etc/systemd/system/split-tunnel-persist.service` |
| `extras/systemd/*.timer` | `/etc/systemd/system/split-tunnel-persist.timer` |
| log output | `/var/log/split_tunnel.log` |
| lock file | `/var/run/split_tunnel.lock` |

## Architecture Overview

```
User / NetworkManager
        │
        ▼
99-split-tunnel (dispatcher script)
        │
        ├── load_config()          Safe line-by-line config parsing
        ├── validate_config()      Pre-flight checks
        ├── discover_subnets()     Auto-detect LAN (optional)
        ├── add_routes_v4/v6()     Route management
        ├── setup_dns_leak()       DNS /32 routes (optional)
        ├── enable_kill_switch()   iptables/nftables (optional)
        ├── verify_connectivity()  Post-route ping checks (optional)
        └── send_notification()    Desktop alerts (optional)
```
