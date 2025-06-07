#!/bin/bash

# Configuration Backup Script
# Backs up all stack configurations from /datapool/config

set -e

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
BACKUP_DIR="/datapool/backups"
CONFIG_DIR="/datapool/config"
DATE=$(date +"%Y%m%d_%H%M%S")
BACKUP_NAME="config_backup_$DATE"
BACKUP_PATH="$BACKUP_DIR/$BACKUP_NAME"

# Function to print colored output
print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

# Function to create backup directory
create_backup_dir() {
    print_step "Creating backup directory..."
    
    mkdir -p "$BACKUP_DIR"
    
    if [ $? -eq 0 ]; then
        print_info "✓ Backup directory created: $BACKUP_DIR"
        return 0
    else
        print_error "Failed to create backup directory"
        return 1
    fi
}

# Function to backup configurations
backup_configs() {
    print_step "Backing up configurations from $CONFIG_DIR..."
    
    if [ ! -d "$CONFIG_DIR" ]; then
        print_error "Configuration directory not found: $CONFIG_DIR"
        return 1
    fi
    
    # Create compressed archive
    print_info "Creating compressed backup archive..."
    tar -czf "$BACKUP_PATH.tar.gz" -C "$(dirname $CONFIG_DIR)" "$(basename $CONFIG_DIR)"
    
    if [ $? -eq 0 ]; then
        print_info "✓ Configuration backup created: $BACKUP_PATH.tar.gz"
        
        # Show backup size
        local backup_size=$(du -h "$BACKUP_PATH.tar.gz" | cut -f1)
        print_info "Backup size: $backup_size"
        
        return 0
    else
        print_error "Failed to create configuration backup"
        return 1
    fi
}

# Function to list existing backups
list_backups() {
    print_step "Listing existing backups..."
    
    if [ -d "$BACKUP_DIR" ]; then
        local backup_count=$(ls -1 "$BACKUP_DIR"/config_backup_*.tar.gz 2>/dev/null | wc -l)
        
        if [ "$backup_count" -gt 0 ]; then
            print_info "Found $backup_count existing backups:"
            ls -lh "$BACKUP_DIR"/config_backup_*.tar.gz 2>/dev/null | awk '{print "  " $9 " (" $5 ", " $6 " " $7 " " $8 ")"}'
        else
            print_info "No existing backups found"
        fi
    else
        print_info "Backup directory does not exist yet"
    fi
}

# Function to cleanup old backups (keep last 7)
cleanup_old_backups() {
    local keep_count=${1:-7}
    
    print_step "Cleaning up old backups (keeping last $keep_count)..."
    
    if [ -d "$BACKUP_DIR" ]; then
        local backup_files=($(ls -t "$BACKUP_DIR"/config_backup_*.tar.gz 2>/dev/null))
        local total_backups=${#backup_files[@]}
        
        if [ "$total_backups" -gt "$keep_count" ]; then
            print_info "Found $total_backups backups, removing $(($total_backups - $keep_count)) old ones..."
            
            for ((i=$keep_count; i<$total_backups; i++)); do
                rm -f "${backup_files[$i]}"
                print_info "Removed: $(basename ${backup_files[$i]})"
            done
            
            print_info "✓ Old backups cleaned up"
        else
            print_info "No old backups to clean up"
        fi
    fi
}

# Function to restore backup
restore_backup() {
    local backup_file=$1
    
    print_step "Restoring backup: $backup_file"
    
    if [ ! -f "$backup_file" ]; then
        print_error "Backup file not found: $backup_file"
        return 1
    fi
    
    print_warning "⚠️  This will overwrite existing configurations!"
    read -p "Are you sure you want to continue? (y/N): " confirm
    
    if [[ "$confirm" =~ ^([yY][eE][sS]|[yY])$ ]]; then
        # Stop all containers first
        print_info "Stopping all Docker containers..."
        docker stop $(docker ps -q) 2>/dev/null || true
        
        # Create backup of current config
        local current_backup="$BACKUP_DIR/pre_restore_backup_$(date +%Y%m%d_%H%M%S).tar.gz"
        print_info "Creating backup of current configuration..."
        tar -czf "$current_backup" -C "$(dirname $CONFIG_DIR)" "$(basename $CONFIG_DIR)" 2>/dev/null || true
        
        # Restore backup
        print_info "Restoring configuration..."
        tar -xzf "$backup_file" -C "$(dirname $CONFIG_DIR)"
        
        if [ $? -eq 0 ]; then
            print_info "✓ Configuration restored successfully"
            print_info "Current config backed up to: $current_backup"
            print_warning "Remember to restart your Docker containers"
            return 0
        else
            print_error "Failed to restore configuration"
            return 1
        fi
    else
        print_info "Restore cancelled"
        return 0
    fi
}

# Function to show backup info
show_backup_info() {
    local backup_file=$1
    
    if [ ! -f "$backup_file" ]; then
        print_error "Backup file not found: $backup_file"
        return 1
    fi
    
    print_info "Backup file: $backup_file"
    print_info "Size: $(du -h $backup_file | cut -f1)"
    print_info "Created: $(stat -c %y $backup_file)"
    print_info "Contents:"
    tar -tzf "$backup_file" | head -20
    
    if [ "$(tar -tzf $backup_file | wc -l)" -gt 20 ]; then
        print_info "... and $(( $(tar -tzf $backup_file | wc -l) - 20 )) more items"
    fi
}

# Main function
main() {
    case "${1:-backup}" in
        "backup")
            print_info "🔄 Starting configuration backup..."
            create_backup_dir
            list_backups
            backup_configs
            cleanup_old_backups 7
            print_info "✅ Backup completed successfully!"
            ;;
        "list")
            list_backups
            ;;
        "restore")
            if [ -z "$2" ]; then
                print_error "Please specify backup file to restore"
                print_info "Usage: $0 restore <backup_file>"
                print_info "Available backups:"
                list_backups
                exit 1
            fi
            restore_backup "$2"
            ;;
        "info")
            if [ -z "$2" ]; then
                print_error "Please specify backup file"
                print_info "Usage: $0 info <backup_file>"
                exit 1
            fi
            show_backup_info "$2"
            ;;
        "cleanup")
            cleanup_old_backups "${2:-7}"
            ;;
        *)
            echo "Usage: $0 {backup|list|restore|info|cleanup} [options]"
            echo ""
            echo "Commands:"
            echo "  backup         Create a new configuration backup"
            echo "  list           List existing backups"
            echo "  restore <file> Restore configuration from backup"
            echo "  info <file>    Show backup information"
            echo "  cleanup [num]  Remove old backups (default: keep 7)"
            echo ""
            echo "Examples:"
            echo "  $0 backup"
            echo "  $0 list"
            echo "  $0 restore /datapool/backups/config_backup_20240101_120000.tar.gz"
            echo "  $0 cleanup 5"
            exit 1
            ;;
    esac
}

# Check if running as root
if [ "$(id -u)" -ne 0 ]; then
    print_error "This script must be run as root"
    exit 1
fi

# Execute main function
main "$@"