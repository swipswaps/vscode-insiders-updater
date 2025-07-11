# Security Policy

## Supported Versions

We actively support the following versions of the VSCode Insiders Updater:

| Version | Supported          |
| ------- | ------------------ |
| 1.2.x   | :white_check_mark: |
| 1.1.x   | :white_check_mark: |
| < 1.1   | :x:                |

## Security Features

This project implements several security measures:

### 🛡️ Built-in Security Controls

- **File Ownership Verification**: Script validates ownership before file operations
- **Path Validation**: Temporary directories restricted to safe system paths
- **Process Isolation**: Prevents interference with running applications
- **Atomic Lock Files**: Prevents race conditions and concurrent execution
- **Signal Handling**: Proper cleanup on interruption (SIGINT, SIGTERM, SIGQUIT)
- **Resource Tracking**: Comprehensive cleanup of all temporary resources

### 🔒 Secure Defaults

- Uses `mktemp` for secure temporary file creation
- Validates package integrity before installation
- Requires explicit user confirmation for critical operations
- Implements graceful process termination with timeouts
- Logs security-relevant operations for audit trails

## Reporting a Vulnerability

We take security vulnerabilities seriously. If you discover a security issue, please follow these steps:

### 🚨 For Critical Security Issues

**DO NOT** create a public GitHub issue for security vulnerabilities.

Instead, please:

1. **Email**: Send details to the repository maintainer via GitHub's private vulnerability reporting
2. **Include**: 
   - Description of the vulnerability
   - Steps to reproduce
   - Potential impact assessment
   - Suggested fix (if available)

### 📧 Contact Information

- **Primary**: Use GitHub's [Private Vulnerability Reporting](https://github.com/swipswaps/vscode-insiders-updater/security/advisories/new)
- **Alternative**: Create a private issue and mention @swipswaps

### ⏱️ Response Timeline

- **Initial Response**: Within 48 hours
- **Vulnerability Assessment**: Within 1 week
- **Fix Development**: Within 2 weeks (depending on severity)
- **Public Disclosure**: After fix is released and users have time to update

## Security Best Practices for Users

### 🔍 Before Running

1. **Verify Source**: Only download from official GitHub repository
2. **Check Integrity**: Verify script hasn't been tampered with
3. **Review Code**: Examine the script before execution (it's open source!)
4. **Backup Data**: Always backup important data before system updates

### 🛡️ Safe Execution

```bash
# Download and verify
curl -fsSL https://raw.githubusercontent.com/swipswaps/vscode-insiders-updater/main/vscode-insiders-updater.sh -o vscode-insiders-updater.sh

# Check script integrity
bash -n vscode-insiders-updater.sh

# Review the script (recommended)
less vscode-insiders-updater.sh

# Run with debug mode first (optional)
DEBUG=1 ./vscode-insiders-updater.sh
```

### 🚫 What NOT to Do

- Don't run the script as root unless necessary
- Don't disable security features (ownership checks, path validation)
- Don't run on production systems without testing
- Don't ignore error messages or warnings

## Security Considerations

### 🔐 Permissions Required

The script requires:
- **User permissions**: For creating temporary files and directories
- **Sudo access**: Only for package installation (`dnf install`, `apt install`)
- **Network access**: For downloading VSCode Insiders packages

### 🌐 Network Security

- Downloads only from official Microsoft VSCode servers
- Uses HTTPS for all network communications
- Validates downloaded package integrity
- Implements download timeouts and retry limits

### 📁 File System Security

- Creates temporary files in user-accessible directories only
- Validates file ownership before deletion
- Restricts temporary directory creation to safe paths
- Implements secure cleanup on script exit

## Compliance

This project follows:

- **OWASP Secure Coding Practices**
- **Google Shell Style Guide**
- **GitHub Security Best Practices**
- **Linux Security Standards**

## Security Updates

Security updates will be:
- Released as soon as possible after discovery
- Clearly marked in release notes
- Communicated via GitHub Security Advisories
- Backward compatible when possible

## Audit Trail

The script provides audit capabilities:
- Debug logging for all security-relevant operations
- Clear error messages for security violations
- Comprehensive cleanup tracking
- Process and resource monitoring

---

**Remember**: This script modifies system packages. Always review the code and test in a safe environment before using in production.
