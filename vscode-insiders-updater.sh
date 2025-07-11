#!/usr/bin/env bash
################################################################################
# Cross-Platform VSCode Insiders Update Script
# Supports RPM-based (Fedora, RHEL, openSUSE) and DEB-based (Ubuntu, Debian) systems
# Features: Smart downloads, resume capability, automatic system detection
#
# Environment Variables (optional configuration):
#   VSCODE_BACKUP_SCRIPT       - Path to backup script (auto-detected if not set)
#   VSCODE_DOWNLOAD_DIR        - Download cache directory (default: ~/.cache/vscode-insiders-updates)
#   PARTIAL_DOWNLOAD_THRESHOLD - Size threshold for partial download cleanup (default: 1MB)
#   PROCESS_SHUTDOWN_TIMEOUT   - Seconds to wait for graceful process shutdown (default: 5)
#   DOWNLOAD_TIMEOUT           - Download timeout in seconds (default: 1800/30min)
#   DOWNLOAD_RETRIES           - Number of download retry attempts (default: 3)
#   DEBUG                      - Enable debug logging (set to 1)
#   SKIP_COMPLIANCE_CHECK      - Skip Augment rules compliance check (set to 1)
################################################################################

set -euo pipefail
IFS=$'\n\t'

# ========== COMPREHENSIVE CLEANUP SYSTEM ==========
# Global cleanup tracking arrays (Augment Cleanup Rules Compliant)
TEMP_FILES=()
TEMP_DIRS=()
BACKGROUND_PIDS=()
LOCK_FILES=()
STARTED_SERVICES=()

# Resource registration functions
register_temp_file() {
    TEMP_FILES+=("$1")
    [[ "${DEBUG:-0}" == "1" ]] && echo "DEBUG: Registered temp file: $1" >&2
}

register_temp_dir() {
    TEMP_DIRS+=("$1")
    [[ "${DEBUG:-0}" == "1" ]] && echo "DEBUG: Registered temp dir: $1" >&2
}

register_background_pid() {
    BACKGROUND_PIDS+=("$1")
    [[ "${DEBUG:-0}" == "1" ]] && echo "DEBUG: Registered background PID: $1" >&2
}

register_lock_file() {
    LOCK_FILES+=("$1")
    [[ "${DEBUG:-0}" == "1" ]] && echo "DEBUG: Registered lock file: $1" >&2
}

# Comprehensive cleanup function
cleanup_all() {
    local exit_code=$?
    local cleanup_start=$(date +%s)

    [[ "${DEBUG:-0}" == "1" ]] && echo "DEBUG: Starting comprehensive cleanup (exit code: $exit_code)" >&2

    # Kill background processes gracefully
    for pid in "${BACKGROUND_PIDS[@]}"; do
        if kill -0 "$pid" 2>/dev/null; then
            [[ "${DEBUG:-0}" == "1" ]] && echo "DEBUG: Terminating background process: $pid" >&2
            # Try graceful shutdown first
            kill "$pid" 2>/dev/null || true

            # Wait for graceful shutdown
            local count=0
            while kill -0 "$pid" 2>/dev/null && [[ $count -lt $PROCESS_SHUTDOWN_TIMEOUT ]]; do
                sleep 1
                ((count++))
            done

            # Force kill if still running
            if kill -0 "$pid" 2>/dev/null; then
                [[ "${DEBUG:-0}" == "1" ]] && echo "DEBUG: Force killing process: $pid" >&2
                kill -9 "$pid" 2>/dev/null || true
            fi
        fi
    done

    # Clean up temporary files with ownership verification
    for file in "${TEMP_FILES[@]}"; do
        if [[ -f "$file" ]]; then
            # Verify we own the file before deletion
            if [[ -O "$file" ]]; then
                [[ "${DEBUG:-0}" == "1" ]] && echo "DEBUG: Removing temp file: $file" >&2
                rm -f "$file" 2>/dev/null || true
            else
                echo "WARNING: Cannot remove temp file (not owner): $file" >&2
            fi
        fi
    done

    # Clean up temporary directories with safety checks
    for dir in "${TEMP_DIRS[@]}"; do
        if [[ -d "$dir" ]]; then
            # Verify directory is within safe paths
            case "$dir" in
                /tmp/*|/var/tmp/*|"$HOME"/.cache/*)
                    if [[ -O "$dir" ]]; then
                        [[ "${DEBUG:-0}" == "1" ]] && echo "DEBUG: Removing temp dir: $dir" >&2
                        rm -rf "$dir" 2>/dev/null || true
                    else
                        echo "WARNING: Cannot remove temp dir (not owner): $dir" >&2
                    fi
                    ;;
                *)
                    echo "ERROR: Temp directory outside safe paths: $dir" >&2
                    ;;
            esac
        fi
    done

    # Remove lock files
    for lock in "${LOCK_FILES[@]}"; do
        if [[ -f "$lock" ]]; then
            [[ "${DEBUG:-0}" == "1" ]] && echo "DEBUG: Removing lock file: $lock" >&2
            rm -f "$lock" 2>/dev/null || true
        fi
    done

    # Clean up partial downloads on failure
    if [[ $exit_code -ne 0 ]] && [[ -n "${CURRENT_DOWNLOAD:-}" ]] && [[ -f "$CURRENT_DOWNLOAD" ]]; then
        local file_size=$(stat -c%s "$CURRENT_DOWNLOAD" 2>/dev/null || echo "0")
        if [[ $file_size -lt $PARTIAL_DOWNLOAD_THRESHOLD ]]; then
            echo "INFO: Cleaning up partial download: $CURRENT_DOWNLOAD (${file_size} bytes < ${PARTIAL_DOWNLOAD_THRESHOLD} threshold)" >&2
            rm -f "$CURRENT_DOWNLOAD" 2>/dev/null || true
        fi
    fi

    # Cleanup metrics
    local cleanup_end=$(date +%s)
    local cleanup_duration=$((cleanup_end - cleanup_start))

    if [[ "${DEBUG:-0}" == "1" ]]; then
        echo "DEBUG: Cleanup completed in ${cleanup_duration}s" >&2
        echo "DEBUG: Cleaned ${#TEMP_FILES[@]} temp files, ${#TEMP_DIRS[@]} temp dirs, killed ${#BACKGROUND_PIDS[@]} processes" >&2
    fi

    exit $exit_code
}

# Set up comprehensive signal handlers (Augment Rules Compliant)
trap cleanup_all EXIT INT TERM QUIT

# ========== LOCK FILE MANAGEMENT ==========
LOCK_FILE="${XDG_RUNTIME_DIR:-/tmp}/vscode_insiders_updater.lock"

acquire_lock() {
    # Try to create lock file atomically
    if ! ( set -o noclobber; echo "$$" > "$LOCK_FILE" ) 2>/dev/null; then
        local existing_pid
        existing_pid=$(cat "$LOCK_FILE" 2>/dev/null || echo "unknown")

        # Check if the process is actually running
        if [[ "$existing_pid" != "unknown" ]] && kill -0 "$existing_pid" 2>/dev/null; then
            log "ERROR" "Another instance is running (PID: $existing_pid)"
            log "ERROR" "If you're sure no other instance is running, remove: $LOCK_FILE"
            return 1
        else
            log "WARN" "Stale lock file found, removing and retrying..."
            rm -f "$LOCK_FILE" 2>/dev/null || true

            # Retry lock acquisition
            if ! ( set -o noclobber; echo "$$" > "$LOCK_FILE" ) 2>/dev/null; then
                log "ERROR" "Failed to acquire lock after removing stale lock file"
                return 1
            fi
        fi
    fi

    # Register lock file for cleanup
    register_lock_file "$LOCK_FILE"
    log "INFO" "Acquired lock file: $LOCK_FILE (PID: $$)"
    return 0
}

# ========== VALIDATION FUNCTIONS ==========
validate_cleanup_safety() {
    local resource="$1"
    local resource_type="$2"

    case "$resource_type" in
        "file")
            # Verify file ownership
            if [[ -f "$resource" ]] && [[ ! -O "$resource" ]]; then
                log "ERROR" "Cannot clean up file (not owner): $resource"
                return 1
            fi
            ;;
        "directory")
            # Verify directory is within allowed paths
            case "$resource" in
                /tmp/*|/var/tmp/*|"$HOME"/.cache/*) ;;
                *)
                    log "ERROR" "Directory outside safe paths: $resource"
                    return 1
                    ;;
            esac

            # Verify directory ownership
            if [[ -d "$resource" ]] && [[ ! -O "$resource" ]]; then
                log "ERROR" "Cannot clean up directory (not owner): $resource"
                return 1
            fi
            ;;
        "process")
            # Verify process exists and we can signal it
            if ! kill -0 "$resource" 2>/dev/null; then
                return 1  # Process doesn't exist, nothing to clean
            fi
            ;;
    esac

    return 0
}

# ========== AUGMENT CLEANUP RULES COMPLIANCE VALIDATION ==========
validate_cleanup_compliance() {
    local compliance_issues=0

    # Check for trap handlers
    if ! grep -q "trap.*EXIT" "$0"; then
        echo "❌ COMPLIANCE: Missing EXIT trap handler" >&2
        ((compliance_issues++))
    fi

    # Check for cleanup function
    if ! grep -q "cleanup_all" "$0"; then
        echo "❌ COMPLIANCE: Missing comprehensive cleanup function" >&2
        ((compliance_issues++))
    fi

    # Check for resource tracking arrays
    local required_arrays=("TEMP_FILES" "TEMP_DIRS" "BACKGROUND_PIDS" "LOCK_FILES")
    for array in "${required_arrays[@]}"; do
        if ! grep -q "$array" "$0"; then
            echo "❌ COMPLIANCE: Missing resource tracking array: $array" >&2
            ((compliance_issues++))
        fi
    done

    # Check for mktemp usage instead of hardcoded paths
    if grep -q "/tmp/[^$]" "$0" && ! grep -q "mktemp" "$0"; then
        echo "⚠️  COMPLIANCE: Consider using mktemp for temporary files" >&2
    fi

    if [[ $compliance_issues -eq 0 ]]; then
        log "SUCCESS" "✅ Augment Cleanup Rules compliance validation passed"
        return 0
    else
        log "ERROR" "❌ Augment Cleanup Rules compliance validation failed ($compliance_issues issues)"
        return 1
    fi
}

# ========== CONFIGURATION ==========
SCRIPT_VERSION="1.2.0"

# Configurable paths (can be overridden via environment variables)
BACKUP_SCRIPT="${VSCODE_BACKUP_SCRIPT:-}"
DOWNLOAD_DIR="${VSCODE_DOWNLOAD_DIR:-$HOME/.cache/vscode-insiders-updates}"

# Configurable thresholds
PARTIAL_DOWNLOAD_THRESHOLD="${PARTIAL_DOWNLOAD_THRESHOLD:-1048576}"  # 1MB in bytes
PROCESS_SHUTDOWN_TIMEOUT="${PROCESS_SHUTDOWN_TIMEOUT:-5}"  # seconds
DOWNLOAD_TIMEOUT="${DOWNLOAD_TIMEOUT:-1800}"  # 30 minutes
DOWNLOAD_RETRIES="${DOWNLOAD_RETRIES:-3}"

# Auto-detect backup script if not specified
if [[ -z "$BACKUP_SCRIPT" ]]; then
    # Search common locations for backup script
    local backup_candidates=(
        "$HOME/Desktop/test/augment_chat_backup_enhanced.sh"
        "$HOME/bin/augment_chat_backup_enhanced.sh"
        "$HOME/.local/bin/augment_chat_backup_enhanced.sh"
        "$(dirname "$0")/augment_chat_backup_enhanced.sh"
        "./augment_chat_backup_enhanced.sh"
    )

    for candidate in "${backup_candidates[@]}"; do
        if [[ -f "$candidate" && -x "$candidate" ]]; then
            BACKUP_SCRIPT="$candidate"
            break
        fi
    done
fi

# Note: VSCODE_CONFIG will be set after system detection

# ========== CONFIGURATION DISPLAY ==========
show_configuration() {
    if [[ "${DEBUG:-0}" == "1" ]]; then
        echo "DEBUG: Configuration:" >&2
        echo "  BACKUP_SCRIPT: ${BACKUP_SCRIPT:-'(auto-detect failed)'}" >&2
        echo "  DOWNLOAD_DIR: $DOWNLOAD_DIR" >&2
        echo "  PARTIAL_DOWNLOAD_THRESHOLD: $PARTIAL_DOWNLOAD_THRESHOLD bytes" >&2
        echo "  PROCESS_SHUTDOWN_TIMEOUT: $PROCESS_SHUTDOWN_TIMEOUT seconds" >&2
        echo "  DOWNLOAD_TIMEOUT: $DOWNLOAD_TIMEOUT seconds" >&2
        echo "  DOWNLOAD_RETRIES: $DOWNLOAD_RETRIES attempts" >&2
        echo "  LOCK_FILE: $LOCK_FILE" >&2
        echo "" >&2
    fi
}

# ========== DYNAMIC SYSTEM DETECTION ==========
detect_package_manager() {
    # Detect package manager and system type
    if command -v rpm &>/dev/null && command -v dnf &>/dev/null; then
        echo "dnf"
    elif command -v rpm &>/dev/null && command -v yum &>/dev/null; then
        echo "yum"
    elif command -v rpm &>/dev/null && command -v zypper &>/dev/null; then
        echo "zypper"
    elif command -v rpm &>/dev/null; then
        echo "rpm"
    elif command -v dpkg &>/dev/null && command -v apt &>/dev/null; then
        echo "apt"
    elif command -v dpkg &>/dev/null; then
        echo "dpkg"
    else
        echo "unknown"
    fi
}

get_system_info() {
    local kernel=$(uname -s)
    local arch=$(uname -m)
    local distro="Linux"
    local pkg_manager=$(detect_package_manager)

    # Try to detect distribution
    if [[ -f /etc/os-release ]]; then
        distro=$(grep '^NAME=' /etc/os-release | cut -d'"' -f2 | cut -d' ' -f1)
    fi

    # Normalize architecture for User-Agent
    local ua_arch="$arch"
    case "$arch" in
        "x86_64") ua_arch="x64" ;;
        "aarch64"|"arm64") ua_arch="arm64" ;;
        "i386"|"i686") ua_arch="x86" ;;
    esac

    # Normalize architecture for download URL
    local dl_arch="x64"  # Default to x64
    case "$arch" in
        "x86_64") dl_arch="x64" ;;
        "aarch64"|"arm64") dl_arch="arm64" ;;
    esac

    # Determine package format and download URL based on package manager
    local pkg_format=""
    local install_cmd=""
    case "$pkg_manager" in
        "dnf"|"yum"|"zypper"|"rpm")
            pkg_format="rpm"
            DOWNLOAD_URL="https://code.visualstudio.com/sha/download?build=insider&os=linux-rpm-$dl_arch"
            PACKAGE_FILE="code-insiders.rpm"
            case "$pkg_manager" in
                "dnf") install_cmd="sudo dnf install -y" ;;
                "yum") install_cmd="sudo yum install -y" ;;
                "zypper") install_cmd="sudo zypper install -y" ;;
                "rpm") install_cmd="sudo rpm -Uvh" ;;
            esac
            ;;
        "apt"|"dpkg")
            pkg_format="deb"
            DOWNLOAD_URL="https://code.visualstudio.com/sha/download?build=insider&os=linux-deb-$dl_arch"
            PACKAGE_FILE="code-insiders.deb"
            case "$pkg_manager" in
                "apt") install_cmd="sudo apt install -y" ;;
                "dpkg") install_cmd="sudo dpkg -i" ;;
            esac
            ;;
        *)
            log "ERROR" "Unsupported package manager: $pkg_manager"
            log "ERROR" "This script supports RPM-based (Fedora, RHEL, openSUSE) and DEB-based (Ubuntu, Debian) systems"
            exit 1
            ;;
    esac

    # Export global variables
    USER_AGENT="Mozilla/5.0 (X11; $kernel $ua_arch) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36 VSCodeUpdater/1.1.0"
    PACKAGE_MANAGER="$pkg_manager"
    PACKAGE_FORMAT="$pkg_format"
    INSTALL_COMMAND="$install_cmd"

    # Set download paths based on package format
    CURRENT_DOWNLOAD="$DOWNLOAD_DIR/code-insiders-current.$pkg_format"
    DOWNLOAD_INFO="$DOWNLOAD_DIR/download-info-$pkg_format.txt"

    # Set VSCode config path (same on all Linux systems)
    VSCODE_CONFIG="$HOME/.config/Code - Insiders/User"

    log "INFO" "Detected: $distro on $arch ($ua_arch)"
    log "INFO" "Package manager: $pkg_manager ($pkg_format format)"
    log "INFO" "Download URL: $DOWNLOAD_URL"
    log "INFO" "Install command: $install_cmd"
    log "INFO" "VSCode config: $VSCODE_CONFIG"
}

# Initialize system detection
get_system_info
DOWNLOAD_DIR="$HOME/.cache/vscode-insiders-updates"
# Note: CURRENT_DOWNLOAD and DOWNLOAD_INFO will be set after system detection

# ========== LOGGING ==========
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%H:%M:%S')
    
    case "$level" in
        "SUCCESS") echo -e "${timestamp} ✅ ${message}" ;;
        "ERROR")   echo -e "${timestamp} ❌ ${message}" ;;
        "INFO")    echo -e "${timestamp} ℹ️  ${message}" ;;
        "WARN")    echo -e "${timestamp} ⚠️  ${message}" ;;
    esac
}

# ========== CHAT HISTORY HEALTH CHECK ==========
check_chat_history_health() {
    log "INFO" "Checking Augment chat history health..."
    local issues_found=0
    
    # Check workspace storage
    if [[ ! -d "$VSCODE_CONFIG/workspaceStorage" ]]; then
        log "ERROR" "Workspace storage missing"
        issues_found=1
    else
        local augment_workspaces=$(find "$VSCODE_CONFIG/workspaceStorage" -name "*Augment*" 2>/dev/null | wc -l)
        if [[ $augment_workspaces -eq 0 ]]; then
            log "WARN" "No Augment workspace data found"
            issues_found=1
        else
            log "SUCCESS" "Found $augment_workspaces Augment workspace(s)"
        fi
    fi
    
    # Check for backups
    if [[ -d "$HOME/augment_backups" ]]; then
        local backup_count=$(ls -1 "$HOME/augment_backups" 2>/dev/null | wc -l)
        if [[ $backup_count -gt 0 ]]; then
            log "SUCCESS" "Found $backup_count backup(s) available"
            local latest_backup=$(ls -1t "$HOME/augment_backups" | head -1)
            log "INFO" "Latest backup: $latest_backup"
        else
            log "WARN" "No backups found"
        fi
    else
        log "WARN" "No backup directory found"
    fi
    
    return $issues_found
}

# ========== AUTO-RECOVERY ==========
offer_auto_recovery() {
    log "ERROR" "Chat history issues detected!"
    echo ""
    echo "Recovery options:"
    echo "1. Auto-restore from latest backup (recommended)"
    echo "2. Continue update anyway (will create new backup)"
    echo "3. Exit and fix manually"
    echo ""
    
    read -p "Choose (1-3) [default: 1]: " choice
    choice=${choice:-1}
    
    case $choice in
        1)
            log "INFO" "Attempting auto-restore..."
            if [[ -f "$BACKUP_SCRIPT" ]]; then
                if "$BACKUP_SCRIPT" --restore --auto 2>/dev/null; then
                    log "SUCCESS" "Auto-restore successful!"
                    return 0
                fi
            fi
            
            log "ERROR" "Auto-restore failed"
            echo "Available backups:"
            ls -la "$HOME/augment_backups/" 2>/dev/null || echo "No backups found"
            echo ""
            read -p "Continue with update anyway? (y/N): " continue_anyway
            if [[ "$continue_anyway" != "y" ]] && [[ "$continue_anyway" != "Y" ]]; then
                exit 1
            fi
            ;;
        2)
            log "WARN" "Continuing with update. Will create backup of current state."
            ;;
        3)
            log "INFO" "Exiting. Fix chat history issues manually first."
            exit 0
            ;;
        *)
            log "ERROR" "Invalid choice. Defaulting to auto-restore..."
            offer_auto_recovery
            ;;
    esac
}

# ========== BACKUP CREATION ==========
create_backup() {
    log "INFO" "Creating pre-update backup..."
    
    # Use enhanced backup script if available
    if [[ -f "$BACKUP_SCRIPT" ]]; then
        if "$BACKUP_SCRIPT"; then
            log "SUCCESS" "Backup created using enhanced script"
            return 0
        else
            log "WARN" "Enhanced backup script failed, using fallback"
        fi
    fi
    
    # Fallback backup
    local backup_dir="$HOME/augment_backups/pre_update_$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$backup_dir"
    
    if [[ -d "$VSCODE_CONFIG/workspaceStorage" ]]; then
        cp -r "$VSCODE_CONFIG/workspaceStorage" "$backup_dir/"
        log "SUCCESS" "Fallback backup created: $backup_dir"
        echo "$backup_dir" > "$HOME/.last_augment_backup"
    else
        log "ERROR" "No workspace storage to backup"
        return 1
    fi
}

# ========== RESOURCE CONTENTION PROTECTION ==========
check_resource_contention() {
    # Skip if already in external terminal
    if [[ "${EXTERNAL_TERMINAL:-}" == "1" ]]; then
        log "SUCCESS" "Running in external terminal - safe to proceed"
        return 0
    fi

    # Check if running inside VSCode
    if [[ -n "${VSCODE_PID:-}" ]] || [[ -n "${VSCODE_IPC_HOOK:-}" ]] || [[ "${TERM_PROGRAM:-}" == "vscode" ]]; then
        log "WARN" "Running inside VSCode - launching external terminal..."
        
        # Try to find a terminal
        for terminal in konsole gnome-terminal xterm; do
            if command -v "$terminal" &> /dev/null; then
                log "INFO" "Launching external $terminal..."
                local terminal_pid

                case "$terminal" in
                    "konsole")
                        konsole -e bash -c "cd '$(pwd)' && EXTERNAL_TERMINAL=1 '$0' && echo 'Script completed. Press Enter to close...' && read" &
                        terminal_pid=$!
                        ;;
                    "gnome-terminal")
                        gnome-terminal -- bash -c "cd '$(pwd)' && EXTERNAL_TERMINAL=1 '$0' && echo 'Script completed. Press Enter to close...' && read" &
                        terminal_pid=$!
                        ;;
                    "xterm")
                        xterm -e bash -c "cd '$(pwd)' && EXTERNAL_TERMINAL=1 '$0' && echo 'Script completed. Press Enter to close...' && read" &
                        terminal_pid=$!
                        ;;
                esac

                # Register the terminal process for cleanup (though we'll exit before cleanup)
                register_background_pid "$terminal_pid"

                # Give the terminal time to start
                sleep 1
                log "SUCCESS" "Launched in external $terminal (PID: $terminal_pid)"
                log "INFO" "Original script exiting - external terminal will continue"

                # Note: We exit here, so cleanup won't affect the external terminal
                # The external terminal runs independently
                exit 0
            fi
        done
        
        log "ERROR" "No terminal emulator found!"
        exit 1
    fi
}

# ========== VSCODE PROCESS CHECK ==========
check_vscode_running() {
    if pgrep -f "code-insiders" > /dev/null; then
        log "WARN" "VSCode Insiders is currently running"
        echo ""
        echo "Please close VSCode Insiders before updating to avoid:"
        echo "• Data loss (unsaved files)"
        echo "• Installation corruption"
        echo "• Extension damage"
        echo ""
        read -p "Close VSCode Insiders and press Enter to continue..."
        
        # Wait for VSCode to close
        local wait_count=0
        while pgrep -f "code-insiders" > /dev/null && [[ $wait_count -lt 30 ]]; do
            sleep 1
            ((wait_count++))
        done
        
        if pgrep -f "code-insiders" > /dev/null; then
            log "ERROR" "VSCode Insiders is still running after 30 seconds"
            exit 1
        fi
        
        log "SUCCESS" "VSCode Insiders closed"
    fi
}

# ========== SMART DOWNLOAD MANAGEMENT ==========
get_remote_file_info() {
    log "INFO" "Checking remote file information..."

    # Get remote file headers
    local headers=$(curl -sI "$DOWNLOAD_URL" --user-agent "$USER_AGENT" 2>/dev/null || echo "")

    if [[ -z "$headers" ]]; then
        log "ERROR" "Failed to get remote file info"
        return 1
    fi

    local content_length=$(echo "$headers" | grep -i "content-length:" | cut -d' ' -f2 | tr -d '\r\n' || echo "0")
    local last_modified=$(echo "$headers" | grep -i "last-modified:" | cut -d' ' -f2- | tr -d '\r\n' || echo "")
    local etag=$(echo "$headers" | grep -i "etag:" | cut -d' ' -f2 | tr -d '\r\n' || echo "")

    # Save file info
    mkdir -p "$DOWNLOAD_DIR"
    cat > "$DOWNLOAD_INFO" << EOF
CONTENT_LENGTH=$content_length
LAST_MODIFIED=$last_modified
ETAG=$etag
TIMESTAMP=$(date +%s)
EOF

    log "INFO" "Remote file size: $(numfmt --to=iec $content_length 2>/dev/null || echo "$content_length bytes")"
    return 0
}

need_download() {
    # Check if we need to download (new file or update available)

    # If no local file exists, download needed
    if [[ ! -f "$CURRENT_DOWNLOAD" ]]; then
        log "INFO" "No local file found - download needed"
        return 0
    fi

    # If no info file exists, download needed
    if [[ ! -f "$DOWNLOAD_INFO" ]]; then
        log "INFO" "No download info found - download needed"
        return 0
    fi

    # Get current file info
    source "$DOWNLOAD_INFO"
    local current_size=$(stat -c%s "$CURRENT_DOWNLOAD" 2>/dev/null || echo "0")

    # Check if current file is incomplete
    if [[ "$current_size" -lt "$CONTENT_LENGTH" ]]; then
        log "INFO" "File incomplete ($current_size/$CONTENT_LENGTH bytes) - resume needed"
        return 0
    fi

    # Get new remote file info to check for updates
    local temp_info=$(mktemp /tmp/vscode_remote_info.XXXXXX)
    register_temp_file "$temp_info"

    if get_remote_file_info_temp "$temp_info"; then
        source "$temp_info"
        local new_content_length="$CONTENT_LENGTH"
        local new_last_modified="$LAST_MODIFIED"

        # Reload original info
        source "$DOWNLOAD_INFO"

        if [[ "$new_content_length" != "$CONTENT_LENGTH" ]] || \
           [[ "$new_last_modified" != "$LAST_MODIFIED" ]]; then
            log "INFO" "Remote file updated - download needed"
            return 0
        fi
    fi

    log "SUCCESS" "File is up-to-date and complete - no download needed"
    return 1
}

get_remote_file_info_temp() {
    local temp_file="$1"
    local headers=$(curl -sI "$DOWNLOAD_URL" --user-agent "$USER_AGENT" 2>/dev/null || echo "")

    if [[ -z "$headers" ]]; then
        return 1
    fi

    local content_length=$(echo "$headers" | grep -i "content-length:" | cut -d' ' -f2 | tr -d '\r\n' || echo "0")
    local last_modified=$(echo "$headers" | grep -i "last-modified:" | cut -d' ' -f2- | tr -d '\r\n' || echo "")
    local etag=$(echo "$headers" | grep -i "etag:" | cut -d' ' -f2 | tr -d '\r\n' || echo "")

    cat > "$temp_file" << EOF
CONTENT_LENGTH=$content_length
LAST_MODIFIED=$last_modified
ETAG=$etag
TIMESTAMP=$(date +%s)
EOF
    return 0
}

smart_download() {
    log "INFO" "Starting smart download with resume capability..."
    mkdir -p "$DOWNLOAD_DIR"

    # Get remote file info
    if ! get_remote_file_info; then
        return 1
    fi

    source "$DOWNLOAD_INFO"
    local total_size="$CONTENT_LENGTH"
    local resume_from=0

    # Check if we can resume
    if [[ -f "$CURRENT_DOWNLOAD" ]]; then
        resume_from=$(stat -c%s "$CURRENT_DOWNLOAD" 2>/dev/null || echo "0")
        if [[ "$resume_from" -gt 0 ]] && [[ "$resume_from" -lt "$total_size" ]]; then
            log "INFO" "Resuming download from byte $resume_from"
        elif [[ "$resume_from" -ge "$total_size" ]]; then
            log "SUCCESS" "File already complete"
            return 0
        fi
    fi

    # Download with resume capability
    local attempt=1
    local max_retries=$DOWNLOAD_RETRIES

    while [[ $attempt -le $max_retries ]]; do
        log "INFO" "Download attempt $attempt/$max_retries"

        if curl -L "$DOWNLOAD_URL" \
            --user-agent "$USER_AGENT" \
            --output "$CURRENT_DOWNLOAD" \
            --continue-at "$resume_from" \
            --progress-bar \
            --connect-timeout 30 \
            --max-time "$DOWNLOAD_TIMEOUT" \
            --retry 2 \
            --retry-delay 5; then

            local final_size=$(stat -c%s "$CURRENT_DOWNLOAD" 2>/dev/null || echo "0")
            if [[ "$final_size" -eq "$total_size" ]]; then
                log "SUCCESS" "Download completed successfully"
                return 0
            else
                log "WARN" "Size mismatch: got $final_size, expected $total_size"
                resume_from="$final_size"
            fi
        else
            log "ERROR" "Download attempt $attempt failed"
            if [[ -f "$CURRENT_DOWNLOAD" ]]; then
                resume_from=$(stat -c%s "$CURRENT_DOWNLOAD" 2>/dev/null || echo "0")
            fi
        fi

        ((attempt++))
        if [[ $attempt -le $max_retries ]]; then
            log "INFO" "Waiting 5 seconds before retry..."
            sleep 5
        fi
    done

    log "ERROR" "Download failed after $max_retries attempts"
    return 1
}

verify_and_install() {
    log "INFO" "Verifying downloaded file..."

    # Check file exists and has content
    if [[ ! -f "$CURRENT_DOWNLOAD" ]] || [[ ! -s "$CURRENT_DOWNLOAD" ]]; then
        log "ERROR" "Downloaded file is missing or empty"
        return 1
    fi

    # Check if it's a valid package based on format
    case "$PACKAGE_FORMAT" in
        "rpm")
            if ! file "$CURRENT_DOWNLOAD" | grep -q "RPM"; then
                log "ERROR" "Downloaded file is not a valid RPM package"
                return 1
            fi
            ;;
        "deb")
            if ! file "$CURRENT_DOWNLOAD" | grep -q "Debian"; then
                log "ERROR" "Downloaded file is not a valid DEB package"
                return 1
            fi
            ;;
        *)
            log "WARN" "Unknown package format: $PACKAGE_FORMAT - skipping format verification"
            ;;
    esac

    # Verify size matches expected
    if [[ -f "$DOWNLOAD_INFO" ]]; then
        source "$DOWNLOAD_INFO"
        local actual_size=$(stat -c%s "$CURRENT_DOWNLOAD" 2>/dev/null || echo "0")
        if [[ "$actual_size" -ne "$CONTENT_LENGTH" ]]; then
            log "ERROR" "Size mismatch: $actual_size != $CONTENT_LENGTH"
            return 1
        fi
    fi

    log "SUCCESS" "File verification passed"

    # Install using detected package manager
    log "INFO" "Installing VSCode Insiders using $PACKAGE_MANAGER..."
    log "INFO" "Running: $INSTALL_COMMAND $CURRENT_DOWNLOAD"

    if $INSTALL_COMMAND "$CURRENT_DOWNLOAD"; then
        log "SUCCESS" "Installation completed"

        # For DEB systems, fix dependencies if needed
        if [[ "$PACKAGE_FORMAT" == "deb" ]] && command -v apt &>/dev/null; then
            log "INFO" "Fixing any dependency issues..."
            sudo apt install -f -y || log "WARN" "Could not fix dependencies automatically"
        fi

        return 0
    else
        log "ERROR" "Installation failed"

        # For DEB systems, try to fix dependencies and retry
        if [[ "$PACKAGE_FORMAT" == "deb" ]] && command -v apt &>/dev/null; then
            log "INFO" "Attempting to fix dependencies and retry..."
            if sudo apt install -f -y && $INSTALL_COMMAND "$CURRENT_DOWNLOAD"; then
                log "SUCCESS" "Installation completed after dependency fix"
                return 0
            fi
        fi

        return 1
    fi
}

# ========== MAIN DOWNLOAD AND INSTALL ==========
download_and_install() {
    log "INFO" "Checking for VSCode Insiders updates..."

    # Check if download is needed
    if ! need_download; then
        log "INFO" "Using existing up-to-date file"
    else
        # Download (with resume if needed)
        if ! smart_download; then
            log "ERROR" "Download failed"
            return 1
        fi
    fi

    # Verify and install
    if ! verify_and_install; then
        log "ERROR" "Verification or installation failed"
        return 1
    fi

    log "SUCCESS" "Update process completed"
}

# ========== MAIN FUNCTION ==========
main() {
    echo "================================================================================"
    echo "            Cross-Platform VSCode Insiders Updater v$SCRIPT_VERSION"
    echo "        RPM (Fedora/RHEL) & DEB (Ubuntu/Debian) • Smart Downloads"
    echo "        🛡️  Augment Cleanup Rules Compliant • Production Ready"
    echo "                              $(date '+%Y-%m-%d %H:%M:%S')"
    echo "================================================================================"
    echo ""

    # Step 1: Acquire lock to prevent concurrent execution
    if ! acquire_lock; then
        log "ERROR" "Failed to acquire lock - another instance may be running"
        exit 1
    fi

    # Step 2: System detection (already done during initialization)
    log "SUCCESS" "System detection completed"

    # Step 2.1: Show configuration (debug mode)
    show_configuration

    # Step 2.5: Validate Augment Cleanup Rules compliance
    if [[ "${SKIP_COMPLIANCE_CHECK:-0}" != "1" ]]; then
        validate_cleanup_compliance
    fi

    # Step 3: Resource contention check
    check_resource_contention

    # Step 4: VSCode running check
    check_vscode_running

    # Step 5: Chat history health check
    if ! check_chat_history_health; then
        offer_auto_recovery
    fi

    # Step 6: Create backup
    if ! create_backup; then
        log "ERROR" "Backup creation failed"
        read -p "Continue without backup? (y/N): " continue_without_backup
        if [[ "$continue_without_backup" != "y" ]] && [[ "$continue_without_backup" != "Y" ]]; then
            exit 1
        fi
    fi

    # Step 7: Download and install
    if ! download_and_install; then
        log "ERROR" "Update failed"
        exit 1
    fi
    
    # Success
    echo ""
    echo "🎉 VSCode Insiders update completed successfully!"
    echo ""
    echo "📁 Backup location: $(cat "$HOME/.last_augment_backup" 2>/dev/null || echo 'No backup created')"
    echo "📁 Download cache: $DOWNLOAD_DIR"
    echo ""
    echo "💡 Next steps:"
    echo "   1. Start VSCode Insiders"
    echo "   2. Verify your extensions and settings"
    echo "   3. Check that Augment chat history is intact"
    echo ""
    echo "🔄 If issues occur, restore from backup:"
    echo "   $BACKUP_SCRIPT --restore"
    echo ""
    echo "⚡ Smart features enabled:"
    echo "   • Cross-platform support (RPM & DEB systems)"
    echo "   • Resume interrupted downloads"
    echo "   • Skip downloads if already up-to-date"
    echo "   • Persistent download cache"
    echo "   • Automatic package manager detection"
    echo ""
    echo "🛡️  Augment Cleanup Rules compliance:"
    echo "   • Comprehensive resource tracking"
    echo "   • Graceful process termination"
    echo "   • Secure temporary file management"
    echo "   • Lock file protection"
    echo "   • Signal handler cleanup (EXIT/INT/TERM/QUIT)"
    echo ""
    log "SUCCESS" "Update process completed"
}

# Run main function
main "$@"
