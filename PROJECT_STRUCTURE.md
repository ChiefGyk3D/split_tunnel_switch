# Project Structure

```
split_tunnel_switch/
├── split_tunnel.sh              # Main script with split tunneling logic
├── setup.sh                     # Interactive installation wizard
├── split_tunnel.conf.example    # Configuration file template
├── README.md                    # Comprehensive documentation
├── QUICKSTART.md               # Quick start guide
├── CONTRIBUTING.md             # Contribution guidelines
├── CHANGELOG.md                # Version history and changes
├── LICENSE                     # GPL v3 license
└── .gitignore                  # Git ignore rules

After Installation:
/etc/
├── NetworkManager/
│   └── dispatcher.d/
│       └── 99-split-tunnel     # Installed main script (auto-runs)
└── split_tunnel/
    └── split_tunnel.conf       # Active configuration file

/var/log/
└── split_tunnel.log            # Log file with all operations

/var/run/
└── split_tunnel.lock           # Lock file (temporary, when running)
```

## File Descriptions

### Core Scripts

**`split_tunnel.sh`** (Main Script)
- Core split tunneling functionality
- Route management (add/remove/status)
- NetworkManager dispatcher integration
- Configuration file support
- Logging system
- Lock file mechanism
- Dry-run testing mode

**`setup.sh`** (Installation Script)
- Interactive installation wizard
- Configuration helper
- Quick install mode
- Uninstallation
- Status checking
- Testing utilities

### Configuration

**`split_tunnel.conf.example`**
- Configuration template
- Documented settings
- Example subnets
- Common VPN interfaces
- Best practices

### Documentation

**`README.md`**
- Project overview
- Features and benefits
- Complete installation guide
- Configuration examples
- Usage instructions
- Troubleshooting guide
- FAQ section
- Architecture explanation

**`QUICKSTART.md`**
- Fast setup guide
- Common configurations
- Basic troubleshooting
- Daily usage examples

**`CONTRIBUTING.md`**
- Contribution guidelines
- Development setup
- Coding standards
- Testing procedures
- PR process
- Commit message format

**`CHANGELOG.md`**
- Version history
- Feature additions
- Bug fixes
- Breaking changes

### System Files (After Installation)

**`/etc/NetworkManager/dispatcher.d/99-split-tunnel`**
- Installed copy of split_tunnel.sh
- Automatically executed by NetworkManager on network events
- Can also be run manually

**`/etc/split_tunnel/split_tunnel.conf`**
- Active configuration
- User-customized settings
- Loaded by main script on each run

**`/var/log/split_tunnel.log`**
- Operation log
- Error messages
- Success confirmations
- Timestamped entries

**`/var/run/split_tunnel.lock`**
- Temporary lock file
- Prevents concurrent execution
- Contains PID of running instance
- Automatically removed when script exits

## Key Features by File

### split_tunnel.sh
- ✅ Add/remove/status commands
- ✅ Configuration file support
- ✅ Comprehensive error handling
- ✅ Colorized output
- ✅ Detailed logging
- ✅ Lock file protection
- ✅ Dry-run mode
- ✅ NetworkManager dispatcher support

### setup.sh
- ✅ Interactive subnet configuration
- ✅ VPN interface detection
- ✅ Automatic backup of existing config
- ✅ Prerequisites checking
- ✅ Configuration testing
- ✅ Clean uninstallation
- ✅ Status reporting
- ✅ Quick install mode

### Documentation Suite
- ✅ Beginner-friendly quick start
- ✅ Comprehensive README
- ✅ Development guidelines
- ✅ Version tracking
- ✅ FAQ and troubleshooting
- ✅ Architecture diagrams
- ✅ Code examples

## Workflow

```
User runs setup.sh
    ↓
Interactive Configuration
    ↓
Creates /etc/split_tunnel/split_tunnel.conf
    ↓
Installs split_tunnel.sh → /etc/NetworkManager/dispatcher.d/99-split-tunnel
    ↓
NetworkManager detects network changes
    ↓
Automatically runs 99-split-tunnel
    ↓
Script reads configuration
    ↓
Adds bypass routes
    ↓
Logs operations → /var/log/split_tunnel.log
```

## Maintenance

### Update Configuration
1. Edit `/etc/split_tunnel/split_tunnel.conf`
2. Run: `sudo /etc/NetworkManager/dispatcher.d/99-split-tunnel test`
3. Apply: `sudo /etc/NetworkManager/dispatcher.d/99-split-tunnel add`

### View Logs
```bash
tail -f /var/log/split_tunnel.log
```

### Check Status
```bash
sudo /etc/NetworkManager/dispatcher.d/99-split-tunnel status
```

### Reinstall/Update
```bash
sudo ./setup.sh install
```

### Uninstall
```bash
sudo ./setup.sh uninstall
```
