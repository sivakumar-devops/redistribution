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

    install_package "nginx" "$force_reinstall"
    install_package "mysql-server" "$force_reinstall"
    install_package "php8.1-fpm php-mysql" "$force_reinstall"
    install_package "zip" "$force_reinstall"
    install_package "libgdiplus" "$force_reinstall"
    install_package "pv" "$force_reinstall"
    install_package "python3" "$force_reinstall"
}

# Function to install a single package
install_package() {
    local package_name=$1
    local force_reinstall=$2

    info "Checking if $package_name is already installed..."
    if dpkg -l | grep -q "$package_name"; then
        if [ "$force_reinstall" == "true" ]; then
            info "Reinstalling $package_name..."
            if ! sudo apt install -y --reinstall $package_name >> "$LOG_FILE" 2>&1; then
                error "Failed to reinstall $package_name."
                exit 1
            fi
        else
            warn "$package_name is already installed."
        fi
    else
        info "Installing $package_name..."
        if ! sudo apt install -y $package_name >> "$LOG_FILE" 2>&1; then
            error "Failed to install $package_name."
            exit 1
        fi
    fi
}

# Main function to execute the script
main() {
    local force_reinstall=false
    local install_new=""
    local user=""
    local host_url=""
    local notify=false

    # Parse command line arguments
    while getopts "i:u:h:n:f" opt; do
        case $opt in
            i) install_new=$OPTARG ;;
            u) user=$OPTARG ;;
            h) host_url=$OPTARG ;;
            n) notify=$OPTARG ;;
            f) force_reinstall=true ;;
            \?) error "Invalid option: -$OPTARG" >&2; exit 1 ;;
        esac
    done

    info "Starting system update..."
    update_system

    info "Starting package installation..."
    install_packages "$force_reinstall"

    info "Script completed successfully."

    info "Install new: $install_new"
    info "User: $user"
    info "Host URL: $host_url"
    info "Notify: $notify"
}

main "$@"
