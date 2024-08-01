#!/usr/bin/env bash
# Copyright (c) Syncfusion Inc. All rights reserved.
#

# Color codes for messages
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No color

LOG_FILE="install.log"

# Function to print info messages in green
info() {
    echo -e "${GREEN}Info: $1${NC}" | tee -a "$LOG_FILE"
}

# Function to print warning messages in yellow
warn() {
    echo -e "${YELLOW}Warning: $1${NC}" | tee -a "$LOG_FILE"
}

# Function to print error messages in red
error() {
    echo -e "${RED}Error: $1${NC}" | tee -a "$LOG_FILE"
}

# Function to update system package list
update_system() {
    info "Updating package list..."
    if ! sudo apt update >> "$LOG_FILE" 2>&1; then
        error "Failed to update package list."
        exit 1
    fi
}

# Function to install necessary packages
install_packages() {
    local force_reinstall=$1

    info "Checking if nginx is already installed..."
    if dpkg -l | grep -q nginx; then
        if [ "$force_reinstall" == "true" ]; then
            info "Reinstalling nginx..."
            if ! sudo apt install -y --reinstall nginx >> "$LOG_FILE" 2>&1; then
                error "Failed to reinstall nginx."
                exit 1
            fi
        else
            warn "nginx is already installed."
        fi
    else
        info "Installing nginx..."
        if ! sudo apt install -y nginx >> "$LOG_FILE" 2>&1; then
            error "Failed to install nginx."
            exit 1
        fi
    fi

    info "Checking if mysql-server is already installed..."
    if dpkg -l | grep -q mysql-server; then
        if [ "$force_reinstall" == "true" ]; then
            info "Reinstalling mysql-server..."
            if ! sudo apt install -y --reinstall mysql-server >> "$LOG_FILE" 2>&1; then
                error "Failed to reinstall mysql-server."
                exit 1
            fi
        else
            warn "mysql-server is already installed."
        fi
    else
        info "Installing mysql-server..."
        if ! sudo apt install -y mysql-server >> "$LOG_FILE" 2>&1; then
            error "Failed to install mysql-server."
            exit 1
        fi
    fi

    info "Installing php packages..."
    if ! sudo apt install -y php8.1-fpm php-mysql >> "$LOG_FILE" 2>&1; then
        error "Failed to install PHP packages."
        exit 1
    fi
}

# Main function to execute the script
main() {
    local force_reinstall=false

    # Parse command line arguments
    while getopts "f" opt; then
        case $opt in
            f) force_reinstall=true ;;
            \?) error "Invalid option: -$OPTARG" >&2; exit 1 ;;
        esac
    done

    info "Starting system update..."
    update_system

    info "Starting package installation..."
    install_packages "$force_reinstall"

    info "Script completed successfully."
}

main "$@"
