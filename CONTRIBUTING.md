# Contributing to NetworkManager Split Tunneling Script

First off, thank you for considering contributing to this project! It's people like you that make this tool better for everyone.

## 📋 Table of Contents

- [Code of Conduct](#code-of-conduct)
- [How Can I Contribute?](#how-can-i-contribute)
- [Development Setup](#development-setup)
- [Coding Standards](#coding-standards)
- [Testing Guidelines](#testing-guidelines)
- [Submitting Changes](#submitting-changes)
- [Reporting Bugs](#reporting-bugs)
- [Suggesting Enhancements](#suggesting-enhancements)

## 📜 Code of Conduct

This project and everyone participating in it is governed by a code of mutual respect. By participating, you are expected to uphold this code. Please:

- Use welcoming and inclusive language
- Be respectful of differing viewpoints and experiences
- Gracefully accept constructive criticism
- Focus on what is best for the community
- Show empathy towards other community members

## 🤝 How Can I Contribute?

### Reporting Bugs

Before creating bug reports, please check the [existing issues](https://github.com/ChiefGyk3D/split_tunnel_switch/issues) to avoid duplicates.

When creating a bug report, please include:

- **Clear title and description**
- **Steps to reproduce** the behavior
- **Expected behavior** vs actual behavior
- **System information**:
  - Linux distribution and version
  - NetworkManager version: `NetworkManager --version`
  - Bash version: `bash --version`
  - VPN client and version
- **Relevant logs**: `/var/log/split_tunnel.log`
- **Configuration**: Sanitized copy of your config file
- **Network setup**: Output of `ip route show` and `ip addr show`

**Example Bug Report:**

```markdown
### Bug: Routes not persisting after VPN reconnection

**Description:**
Split tunnel routes are added successfully but disappear when VPN reconnects.

**Steps to Reproduce:**
1. Connect to VPN
2. Verify routes with `ip route show`
3. Disconnect and reconnect VPN
4. Routes are missing

**Expected:** Routes should be re-added automatically

**System Info:**
- Ubuntu 22.04 LTS
- NetworkManager 1.36.6
- OpenVPN 2.5.5

**Logs:**
[Attach relevant log entries]
```

### Suggesting Enhancements

Enhancement suggestions are tracked as GitHub issues. When creating an enhancement suggestion, please include:

- **Clear title and description** of the feature
- **Use case**: Explain why this would be useful
- **Current behavior** vs proposed behavior
- **Possible implementation** (if you have ideas)
- **Alternative solutions** you've considered

### Pull Requests

We actively welcome your pull requests:

1. Fork the repo and create your branch from `main`
2. Make your changes
3. Test your changes thoroughly
4. Update documentation if needed
5. Ensure your code follows our style guidelines
6. Submit a pull request

## 🔧 Development Setup

### Prerequisites

```bash
# Install required tools
sudo apt-get install shellcheck shfmt  # Ubuntu/Debian
# or
sudo dnf install ShellCheck shfmt      # Fedora
# or
sudo pacman -S shellcheck shfmt        # Arch
```

### Setting Up Development Environment

```bash
# Clone your fork
git clone https://github.com/YOUR_USERNAME/split_tunnel_switch.git
cd split_tunnel_switch

# Create a development branch
git checkout -b feature/your-feature-name

# Make the scripts executable
chmod +x split_tunnel.sh setup.sh
```

### Testing Your Changes

```bash
# Run shellcheck for syntax and best practices
shellcheck split_tunnel.sh setup.sh

# Format code consistently
shfmt -w -i 4 -bn -ci -sr split_tunnel.sh setup.sh

# Test in dry-run mode
sudo ./split_tunnel.sh test

# Test installation (in a VM or test system)
sudo ./setup.sh quick-install

# Verify functionality
sudo /etc/NetworkManager/dispatcher.d/99-split-tunnel status
```

## 📝 Coding Standards

### Shell Script Style Guide

We follow the [Google Shell Style Guide](https://google.github.io/styleguide/shellguide.html) with some modifications:

#### General Rules

- Use 4 spaces for indentation (not tabs)
- Maximum line length: 100 characters
- Use `#!/bin/bash` shebang (not `#!/bin/sh`)
- Always use `set -euo pipefail` for safety
- Quote all variables: `"$variable"` not `$variable`
- Use `[[` instead of `[` for conditionals
- Prefer functions over inline code

#### Naming Conventions

```bash
# Constants: UPPER_CASE
readonly CONFIG_FILE="/etc/split_tunnel/split_tunnel.conf"

# Global variables: UPPER_CASE
BYPASS_SUBNETS=()

# Local variables: lower_case
local subnet_count=0

# Functions: lower_case_with_underscores
function add_route() {
    local subnet="$1"
    # implementation
}

# Private/internal functions: _prefixed
function _validate_subnet() {
    # implementation
}
```

#### Error Handling

```bash
# Always check command success
if ! ip route add "$subnet" via "$gateway"; then
    log_message "ERROR" "Failed to add route"
    return 1
fi

# Use meaningful error messages
if [[ ! -f "$CONFIG_FILE" ]]; then
    log_message "ERROR" "Configuration file not found: $CONFIG_FILE"
    exit 1
fi

# Provide actionable guidance
print_error "VPN interface $VPN_INTERFACE not found"
print_info "Run 'ip link show' to list available interfaces"
```

#### Comments

```bash
# Good: Explain WHY, not WHAT
# Acquire lock to prevent race conditions when called by multiple dispatcher events
acquire_lock

# Avoid: Obvious comments
# Loop through subnets
for subnet in "${BYPASS_SUBNETS[@]}"; do
```

#### Functions

```bash
# Good: Single responsibility, clear purpose
add_route() {
    local subnet="$1"
    local gateway="$2"
    local interface="$3"
    
    if ip route add "$subnet" via "$gateway" dev "$interface" 2>/dev/null; then
        log_message "SUCCESS" "Added route for $subnet"
        return 0
    else
        log_message "ERROR" "Failed to add route for $subnet"
        return 1
    fi
}

# Document complex functions
# Validates CIDR notation subnet format
# Arguments:
#   $1 - Subnet in CIDR notation (e.g., 192.168.1.0/24)
# Returns:
#   0 if valid, 1 if invalid
validate_subnet() {
    local subnet="$1"
    # implementation
}
```

### Configuration File Standards

- Use descriptive variable names
- Include comments explaining each option
- Provide examples in comments
- Use sensible defaults

## 🧪 Testing Guidelines

### Manual Testing Checklist

Before submitting a PR, test the following scenarios:

- [ ] Fresh installation on clean system
- [ ] Installation with existing config (upgrade scenario)
- [ ] Adding routes manually
- [ ] Removing routes manually
- [ ] Status command shows correct information
- [ ] Dry-run mode doesn't modify routes
- [ ] Automatic operation via NetworkManager dispatcher
- [ ] VPN connection/disconnection handling
- [ ] Network interface switching (Wi-Fi to Ethernet)
- [ ] Multiple subnet configurations
- [ ] Invalid configuration handling
- [ ] Permission errors (non-root execution)
- [ ] Concurrent execution prevention (lock file)
- [ ] Log file creation and writing
- [ ] Uninstallation completely removes all files

### Test Environments

Please test on at least one of:

- Ubuntu LTS (20.04 or newer)
- Debian Stable
- Fedora (latest)
- Arch Linux

### Automated Testing

We're working on automated tests. Check the `tests/` directory for available test scripts.

```bash
# Run all tests
./tests/run_tests.sh

# Run specific test
./tests/test_route_addition.sh
```

## 📤 Submitting Changes

### Commit Messages

Use clear, descriptive commit messages following this format:

```
<type>: <subject>

<body>

<footer>
```

**Types:**
- `feat`: New feature
- `fix`: Bug fix
- `docs`: Documentation changes
- `style`: Code style changes (formatting, etc.)
- `refactor`: Code refactoring
- `test`: Adding or updating tests
- `chore`: Maintenance tasks

**Examples:**

```
feat: Add support for WireGuard interface detection

- Automatically detect wg* interfaces
- Update configuration examples for WireGuard
- Add WireGuard to FAQ section

Closes #42
```

```
fix: Prevent race condition in route addition

The script could be called multiple times simultaneously by
NetworkManager dispatcher events, causing conflicts. Added lock
file mechanism to prevent concurrent execution.

Fixes #38
```

### Pull Request Process

1. **Update documentation** for any changed functionality
2. **Add tests** if applicable
3. **Update CHANGELOG.md** with your changes
4. **Follow the coding standards** outlined above
5. **Test thoroughly** on your system
6. **Write a clear PR description**:
   - What does this PR do?
   - Why is this change needed?
   - What testing was performed?
   - Any breaking changes?

**PR Template:**

```markdown
## Description
Brief description of the changes

## Motivation
Why is this change needed? What problem does it solve?

## Changes Made
- Change 1
- Change 2
- Change 3

## Testing Performed
- [ ] Manual testing on Ubuntu 22.04
- [ ] Tested VPN connection/disconnection
- [ ] Verified routes persist
- [ ] Checked logs for errors

## Breaking Changes
None / List any breaking changes

## Related Issues
Closes #123
Related to #456
```

### Review Process

1. Maintainer will review your PR
2. May request changes or ask questions
3. Once approved, will be merged into `main`
4. Your contribution will be credited in the CHANGELOG

## 🏆 Recognition

Contributors will be recognized in:
- CHANGELOG.md for each release
- README.md contributors section
- Git commit history

## 📞 Getting Help

- **Questions?** Open a [GitHub Discussion](https://github.com/ChiefGyk3D/split_tunnel_switch/discussions)
- **Issues?** Create a [GitHub Issue](https://github.com/ChiefGyk3D/split_tunnel_switch/issues)
- **Chat?** (Add your preferred communication channel)

## 📚 Additional Resources

- [Bash Best Practices](https://bertvv.github.io/cheat-sheets/Bash.html)
- [ShellCheck](https://www.shellcheck.net/) - Shell script linter
- [Google Shell Style Guide](https://google.github.io/styleguide/shellguide.html)
- [Linux Networking Guide](https://www.kernel.org/doc/html/latest/networking/index.html)

---

Thank you for contributing! 🎉
