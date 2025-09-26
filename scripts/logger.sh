#!/bin/bash

# =================================================================
#                     Logging Utilities Module  
# =================================================================
# Centralized logging system with fail-fast patterns
# Extracted from helper-functions.sh for dedicated logging management
set -euo pipefail

# Color codes for output formatting
readonly COLOR_INFO="\033[36m"     # Cyan
readonly COLOR_SUCCESS="\033[32m"  # Green  
readonly COLOR_WARNING="\033[33m"  # Yellow
readonly COLOR_ERROR="\033[31m"    # Red
readonly COLOR_RESET="\033[0m"     # Reset

# Log levels
readonly LOG_LEVEL_INFO=1
readonly LOG_LEVEL_SUCCESS=2
readonly LOG_LEVEL_WARNING=3
readonly LOG_LEVEL_ERROR=4

# Current log level (can be overridden via LOG_LEVEL env var)
LOG_LEVEL=${LOG_LEVEL:-$LOG_LEVEL_INFO}

# Logging functions with consistent formatting
log_info() { 
    [[ $LOG_LEVEL -le $LOG_LEVEL_INFO ]] && echo -e "${COLOR_INFO}[INFO]${COLOR_RESET} $1" 
}

log_success() { 
    [[ $LOG_LEVEL -le $LOG_LEVEL_SUCCESS ]] && echo -e "${COLOR_SUCCESS}[SUCCESS]${COLOR_RESET} $1" 
}

log_warning() { 
    [[ $LOG_LEVEL -le $LOG_LEVEL_WARNING ]] && echo -e "${COLOR_WARNING}[WARNING]${COLOR_RESET} $1" 
}

log_error() { 
    echo -e "${COLOR_ERROR}[ERROR]${COLOR_RESET} $1" >&2
}

# Compatibility aliases for existing codebase
print_info() { log_info "$1"; }
print_success() { log_success "$1"; }  
print_warning() { log_warning "$1"; }
print_error() { log_error "$1"; }

# Enhanced logging with timestamps
log_with_timestamp() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case "$level" in
        "INFO")    echo -e "$timestamp ${COLOR_INFO}[INFO]${COLOR_RESET} $message" ;;
        "SUCCESS") echo -e "$timestamp ${COLOR_SUCCESS}[SUCCESS]${COLOR_RESET} $message" ;;
        "WARNING") echo -e "$timestamp ${COLOR_WARNING}[WARNING]${COLOR_RESET} $message" ;;
        "ERROR")   echo -e "$timestamp ${COLOR_ERROR}[ERROR]${COLOR_RESET} $message" >&2 ;;
        *)         echo -e "$timestamp [UNKNOWN] $message" ;;
    esac
}

# Fail-fast error handling pattern
fail_fast() {
    local error_message="$1"
    local exit_code="${2:-1}"
    
    log_error "$error_message"
    exit "$exit_code"
}

# Component-specific error handler (follows constitutional pattern)
component_error() {
    local component="$1"
    local specific_failure="$2" 
    local additional_context="${3:-}"
    
    local error_msg="$component: $specific_failure"
    [[ -n "$additional_context" ]] && error_msg="$error_msg: $additional_context"
    
    fail_fast "$error_msg" 3  # Infrastructure error code
}

# Log command execution with fail-fast
log_command() {
    local description="$1"
    shift
    local command=("$@")
    
    log_info "$description"
    
    if ! "${command[@]}"; then
        component_error "Command" "Failed to execute: ${command[*]}" "$description"
    fi
}

# Silent command execution (suppress output, log errors only)
silent_command() {
    local description="$1"
    shift
    local command=("$@")
    
    if ! "${command[@]}" >/dev/null 2>&1; then
        component_error "Silent Command" "Failed to execute: ${command[*]}" "$description"
    fi
}

# Progress indicator for long-running operations
show_progress() {
    local message="$1"
    local duration="${2:-3}"
    
    log_info "$message"
    
    for i in $(seq 1 "$duration"); do
        echo -n "."
        sleep 1
    done
    echo ""
}

# Log file operations
log_to_file() {
    local log_file="$1"
    local level="$2" 
    local message="$3"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    echo "$timestamp [$level] $message" >> "$log_file"
}

# Setup logging to file (optional)
setup_file_logging() {
    local log_file="${1:-/tmp/homelab-automation.log}"
    
    # Create log directory if needed
    mkdir -p "$(dirname "$log_file")"
    
    # Redirect all output to tee for dual logging
    exec 1> >(tee -a "$log_file")
    exec 2> >(tee -a "$log_file" >&2)
    
    log_info "Logging to file: $log_file"
}

# Cleanup function for temporary files and processes
cleanup_on_exit() {
    local temp_files=("$@")
    
    # Remove temporary files
    for file in "${temp_files[@]}"; do
        [[ -f "$file" ]] && rm -f "$file" && log_info "Cleaned up: $file"
    done
}

# Set up trap for automatic cleanup
setup_cleanup_trap() {
    local temp_files=("$@")
    
    trap "cleanup_on_exit ${temp_files[*]}" EXIT
    trap "fail_fast 'Script interrupted' 130" INT
    trap "fail_fast 'Script terminated' 15" TERM
}

# Main entry point for testing logging functions
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    case "${1:-}" in
        "test")
            log_info "This is an info message"
            log_success "This is a success message" 
            log_warning "This is a warning message"
            log_error "This is an error message"
            ;;
        "timestamp")
            log_with_timestamp "INFO" "Testing timestamp logging"
            log_with_timestamp "SUCCESS" "Operation completed"
            log_with_timestamp "WARNING" "Potential issue detected"
            log_with_timestamp "ERROR" "Critical error occurred"
            ;;
        "progress")
            show_progress "Simulating long operation" 5
            log_success "Operation completed"
            ;;
        *)
            echo "Usage: $0 {test|timestamp|progress}"
            echo "Examples:"
            echo "  $0 test       # Test all log levels"  
            echo "  $0 timestamp  # Test timestamp logging"
            echo "  $0 progress   # Test progress indicator"
            exit 1
            ;;
    esac
fi