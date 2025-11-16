# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [2.0.0] - 2025-11-16

### Added
- Interactive setup script (`setup.sh`) with installation wizard
- Configuration file support (`/etc/split_tunnel/split_tunnel.conf`)
- Comprehensive logging system with timestamps
- Lock file mechanism to prevent concurrent execution
- Dry-run mode for testing without making changes
- Status command to check current split tunnel configuration
- Route removal functionality
- Color-coded terminal output for better readability
- Automatic backup of existing installations
- Support for NetworkManager dispatcher events
- Help command with usage information
- Better error handling and validation
- VPN interface detection
- Example configuration file template

### Changed
- Restructured main script with modular functions
- Improved error messages with actionable guidance
- Enhanced route verification logic
- Better default route detection
- Upgraded to Bash best practices (set -euo pipefail)
- Made script more portable across Linux distributions

### Fixed
- Race conditions when called by multiple dispatcher events
- Routes not persisting after VPN reconnection
- Improved handling of missing configuration
- Better validation of network interfaces

### Documentation
- Completely rewritten README with comprehensive documentation
- Added CONTRIBUTING.md with development guidelines
- Added FAQ section
- Added troubleshooting guide
- Added architecture diagram
- Added usage examples and common configurations

## [1.0.0] - Initial Release

### Added
- Basic split tunneling functionality
- Support for multiple bypass subnets
- NetworkManager dispatcher integration
- Simple route addition
- Basic README documentation
