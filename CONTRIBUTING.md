# Contributing to Split Tunnel Switch

Thank you for your interest in contributing! This guide covers everything you need to get started.

## Table of Contents

- [Code of Conduct](#code-of-conduct)
- [Getting Started](#getting-started)
- [Development Setup](#development-setup)
- [Coding Standards](#coding-standards)
- [Testing](#testing)
- [Pull Request Process](#pull-request-process)
- [Reporting Issues](#reporting-issues)

## Code of Conduct

Be respectful and constructive. We follow the [Contributor Covenant](https://www.contributor-covenant.org/version/2/1/code_of_conduct/).

## Getting Started

1. Fork the repository
2. Clone your fork:
   ```bash
   git clone https://github.com/YOUR_USERNAME/split_tunnel_switch.git
   cd split_tunnel_switch
   ```
3. Create a feature branch:
   ```bash
   git checkout -b feature/your-feature
   ```
4. Make your changes
5. Run the test suite
6. Commit and push
7. Open a pull request

## Development Setup

### Prerequisites

- Linux with NetworkManager
- Bash 4.0+
- `shellcheck` (for lint tests)
- `ip`, `awk`, `grep` (standard utilities)
- Root/sudo access (for integration tests)

### Install shellcheck

```bash
# Debian/Ubuntu
sudo apt install shellcheck

# Fedora
sudo dnf install ShellCheck

# Arch
sudo pacman -S shellcheck
```

### Project Layout

See [PROJECT_STRUCTURE.md](PROJECT_STRUCTURE.md) for the full directory map.

Key files to know:

| File | What it does |
|------|-------------|
| `split_tunnel.sh` | Main dispatcher script (~750 lines) |
| `setup.sh` | Interactive installer (~450 lines) |
| `split_tunnel.conf.example` | Config template with docs |
| `tests/run_tests.sh` | Test suite (~350 lines) |

## Coding Standards

### Shell Script Style

- **Shebang**: `#!/usr/bin/env bash`
- **Strict mode**: `set -euo pipefail` at the top of every script
- **Indentation**: 4 spaces (no tabs)
- **Quoting**: Always quote variables: `"$var"`, not `$var`
- **Functions**: Use `function_name() { ... }` style
- **Local variables**: Declare with `local` inside functions
- **Naming**: `UPPER_CASE` for constants/config, `lower_case` for local variables and functions
- **Comments**: Use `#` with a space; explain *why*, not *what*

### Config Parsing Rules

The config parser is intentionally restrictive for security:

- **Never** use `source` or `eval` to load config
- All config values are parsed via `_assign_scalar` and `_assign_array` helpers
- Only explicitly allowlisted keys are accepted
- Adding a new config key requires updating:
  1. The parser's `case` statement in `load_config()`
  2. The defaults section at the top of `split_tunnel.sh`
  3. The `validate_config()` function
  4. The `split_tunnel.conf.example` template
  5. The README configuration section

### Error Handling

- Use `log_msg` for all output (supports ERROR, WARN, INFO, DEBUG levels)
- Critical failures should call `exit 1` with an error message
- Non-critical issues should `log_msg WARN` and continue
- Lock files must be cleaned up via trap on exit

## Testing

### Running Tests

```bash
# All tests
./tests/run_tests.sh

# Specific category
./tests/run_tests.sh lint          # shellcheck on all .sh files
./tests/run_tests.sh unit          # CIDR validation, config parsing, CLI output
./tests/run_tests.sh integration   # Requires root; tests against installed script
```

### Test Categories

#### Lint Tests
- Runs `shellcheck` on `split_tunnel.sh`, `setup.sh`, and `tests/run_tests.sh`
- All scripts must pass with zero warnings or errors

#### Unit Tests
- IPv4 CIDR validation (valid and invalid cases)
- IPv6 CIDR validation (valid and invalid cases)
- Config file syntax (valid bash array/string format)
- Config key completeness (all expected keys present)
- `version` command output format
- `help` command content
- Unknown command error handling

#### Integration Tests
- Dry-run (`test`) command execution
- Config validation (`validate`) command
- Status display (`status`) command
- Subnet discovery (`discover`) command

### Writing Tests

When adding a new feature, add tests covering:

1. **Happy path**: Feature works with valid input
2. **Error path**: Feature fails gracefully with bad input
3. **Edge cases**: Empty values, boundary values, special characters

Test functions follow the pattern:

```bash
test_your_feature() {
    local passed=0 failed=0

    # Test case 1
    if some_condition; then
        ((passed++))
    else
        echo "  FAIL: description of what failed"
        ((failed++))
    fi

    echo "  Results: $passed passed, $failed failed"
    TOTAL_PASS=$((TOTAL_PASS + passed))
    TOTAL_FAIL=$((TOTAL_FAIL + failed))
}
```

### Testing Checklist

Before submitting a PR, verify:

- [ ] `./tests/run_tests.sh lint` passes (zero shellcheck warnings)
- [ ] `./tests/run_tests.sh unit` passes (all unit tests green)
- [ ] `sudo ./tests/run_tests.sh integration` passes (if you changed dispatch logic)
- [ ] Manual test with VPN connected (if you changed routing)
- [ ] Manual test with VPN disconnected (if you changed vpn-down logic)
- [ ] Kill switch on/off cycle (if you touched firewall code)
- [ ] IPv4 and IPv6 both tested (if you changed route functions)
- [ ] Config validation still works (if you added/changed config keys)
- [ ] Dry-run mode shows correct planned actions

## Pull Request Process

### Branch Naming

- `feature/short-description` — new features
- `fix/short-description` — bug fixes
- `docs/short-description` — documentation only
- `test/short-description` — test improvements

### Commit Messages

Use [Conventional Commits](https://www.conventionalcommits.org/):

```
feat: add support for WireGuard key rotation
fix: kill switch not cleaning up on script exit
docs: update FAQ with nftables instructions
test: add IPv6 CIDR edge case tests
refactor: extract route validation into helper
```

### PR Requirements

1. **Description**: Explain what changed and why
2. **Tests**: All existing tests pass + new tests for new features
3. **Documentation**: Update README/QUICKSTART/config example if behavior changes
4. **Changelog**: Add entry to `CHANGELOG.md` under `[Unreleased]`
5. **No breaking changes** without discussion first
6. **One feature per PR** — keep changes focused

### Review Process

1. Open a PR against `main`
2. Automated checks run (lint, unit tests)
3. Maintainer reviews code and tests
4. Address feedback
5. Merge after approval

## Reporting Issues

### Bug Reports

Include:

- **OS and version** (e.g., Ubuntu 24.04)
- **Bash version** (`bash --version`)
- **VPN type** (OpenVPN, WireGuard, etc.)
- **Config file** (sanitize sensitive data)
- **Log output** (`tail -50 /var/log/split_tunnel.log`)
- **Steps to reproduce**
- **Expected vs. actual behavior**

### Feature Requests

Include:

- **Use case**: What problem does this solve?
- **Proposed solution**: How should it work?
- **Alternatives considered**: What else did you evaluate?

## Recognition

Contributors are recognized in release notes. Thank you for helping improve split tunneling for the Linux community!
