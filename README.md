# VSCode Insiders Updater

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Shell Script](https://img.shields.io/badge/Shell-Bash-green.svg)](https://www.gnu.org/software/bash/)
[![Platform](https://img.shields.io/badge/Platform-Linux-blue.svg)](https://www.linux.org/)

A robust, cross-platform shell script for automating VSCode Insiders updates on Linux systems. Supports both RPM-based (Fedora, RHEL, openSUSE) and DEB-based (Ubuntu, Debian) distributions with smart download management and comprehensive cleanup.

## ✨ Features

- **🌍 Cross-Platform**: Supports RPM and DEB-based Linux distributions
- **⚡ Smart Downloads**: Resume interrupted downloads, skip unnecessary updates
- **🛡️ Resource Management**: Comprehensive cleanup with lock file protection
- **🔒 Security**: Ownership verification, safe path validation
- **📊 Configurable**: Environment variable configuration for all settings
- **🔍 Debug Support**: Detailed logging and troubleshooting capabilities
- **🎯 Production Ready**: Follows industry best practices and cleanup standards

## 🚀 Quick Start

```bash
# Download and run
curl -fsSL https://raw.githubusercontent.com/swipswaps/vscode-insiders-updater/main/vscode-insiders-updater.sh | bash

# Or clone and run locally
git clone https://github.com/swipswaps/vscode-insiders-updater.git
cd vscode-insiders-updater
./vscode-insiders-updater.sh
```

## 📋 Requirements

### System Requirements
- Linux (RPM or DEB-based distribution)
- Bash 4.0+
- Internet connection

### Required Commands
- `curl` or `wget` - For downloading
- `rpm`/`dpkg` - Package management
- `dnf`/`yum`/`apt`/`zypper` - Package managers
- `sudo` - For package installation

### Supported Distributions

| Distribution | Package Manager | Status |
|--------------|----------------|--------|
| **Fedora** | `dnf` | ✅ Fully Supported |
| **RHEL/CentOS** | `yum` | ✅ Fully Supported |
| **openSUSE** | `zypper` | ✅ Fully Supported |
| **Ubuntu** | `apt` | ✅ Fully Supported |
| **Debian** | `apt` | ✅ Fully Supported |
| **Linux Mint** | `apt` | ✅ Fully Supported |

## ⚙️ Configuration

All settings can be customized via environment variables:

| Variable | Default | Description |
|----------|---------|-------------|
| `VSCODE_BACKUP_SCRIPT` | *(auto-detect)* | Path to backup script |
| `VSCODE_DOWNLOAD_DIR` | `~/.cache/vscode-insiders-updates` | Download cache directory |
| `PARTIAL_DOWNLOAD_THRESHOLD` | `1048576` (1MB) | Size threshold for partial download cleanup |
| `PROCESS_SHUTDOWN_TIMEOUT` | `5` | Seconds to wait for graceful process shutdown |
| `DOWNLOAD_TIMEOUT` | `1800` (30min) | Download timeout in seconds |
| `DOWNLOAD_RETRIES` | `3` | Number of download retry attempts |
| `DEBUG` | `0` | Enable debug logging (set to `1`) |
| `SKIP_COMPLIANCE_CHECK` | `0` | Skip cleanup compliance validation |

### Configuration Examples

```bash
# Use custom backup script
VSCODE_BACKUP_SCRIPT="/path/to/backup.sh" ./vscode-insiders-updater.sh

# Use different download directory
VSCODE_DOWNLOAD_DIR="/tmp/vscode-downloads" ./vscode-insiders-updater.sh

# Debug mode with faster timeouts
DEBUG=1 DOWNLOAD_TIMEOUT=300 ./vscode-insiders-updater.sh

# Production settings with extended timeouts
DOWNLOAD_RETRIES=5 PROCESS_SHUTDOWN_TIMEOUT=10 ./vscode-insiders-updater.sh
```

## 🔧 How It Works

1. **System Detection**: Automatically detects your Linux distribution and package manager
2. **Lock Management**: Prevents concurrent executions with atomic lock files
3. **Resource Protection**: Launches external terminal if run from within VSCode
4. **Process Verification**: Ensures VSCode Insiders is closed before updating
5. **Smart Downloads**: Checks for existing downloads and resumes if interrupted
6. **Package Installation**: Uses appropriate package manager for your system
7. **Comprehensive Cleanup**: Removes all temporary resources on exit

## 🛡️ Security Features

- **Ownership Verification**: Validates file ownership before deletion
- **Path Validation**: Ensures temporary directories are in safe locations
- **Process Isolation**: Prevents interference with running VSCode instances
- **Atomic Operations**: Lock files prevent race conditions
- **Signal Handling**: Proper cleanup on script interruption (SIGINT, SIGTERM)

## 📊 Smart Download Management

- **Resume Capability**: Interrupted downloads resume from last byte
- **Version Detection**: Skips downloads if file is already current
- **Integrity Verification**: Validates downloaded packages before installation
- **Cache Management**: Persistent download cache between runs
- **Bandwidth Optimization**: Avoids re-downloading identical files

## 🔍 Troubleshooting

### Enable Debug Mode
```bash
DEBUG=1 ./vscode-insiders-updater.sh
```

### Common Issues

**Permission Denied**
```bash
chmod +x vscode-insiders-updater.sh
```

**Lock File Issues**
```bash
# Remove stale lock file
rm -f "${XDG_RUNTIME_DIR:-/tmp}/vscode_insiders_updater.lock"
```

**Download Issues**
```bash
# Clear download cache
rm -rf ~/.cache/vscode-insiders-updates/
```

**Package Manager Issues**
```bash
# Update package manager cache
sudo dnf makecache  # Fedora
sudo apt update     # Ubuntu/Debian
```

## 🧪 Testing

The script includes built-in compliance validation:

```bash
# Run with compliance checking (default)
./vscode-insiders-updater.sh

# Skip compliance validation
SKIP_COMPLIANCE_CHECK=1 ./vscode-insiders-updater.sh

# Test syntax only
bash -n vscode-insiders-updater.sh
```

## 📝 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🤝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request. For major changes, please open an issue first to discuss what you would like to change.

### Development Guidelines

1. Follow existing code style and patterns
2. Ensure all temporary resources are properly tracked and cleaned
3. Add appropriate error handling and logging
4. Test on multiple Linux distributions
5. Update documentation for new features

## 📞 Support

- **Issues**: [GitHub Issues](https://github.com/swipswaps/vscode-insiders-updater/issues)
- **Discussions**: [GitHub Discussions](https://github.com/swipswaps/vscode-insiders-updater/discussions)

## 🏆 Acknowledgments

- Built following [Augment Script Cleanup Rules](https://github.com/swipswaps/vscode-insiders-updater/blob/main/docs/cleanup-rules.md)
- Inspired by production DevOps best practices
- Follows Google Shell Style Guide recommendations

---

**⚠️ Disclaimer**: This script modifies system packages. Always backup your data before running system updates. Use at your own risk.
