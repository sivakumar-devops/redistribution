#!/usr/bin/env bash
# Copyright (c) Syncfusion Inc. All rights reserved.
#

# Color codes for messages
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No color

info() {
    echo -e "${GREEN}Info: $1${NC}"
}

warn() {
    echo -e "${YELLOW}Warning: $1${NC}"
}

error() {
    echo -e "${RED}Error: $1${NC}"
}

update_system() {
    info "Updating package list..."
    if ! sudo apt update; then
        error "Failed to update package list."
        exit 1
    fi
}

install_packages() {
    info "Installing necessary packages..."
    
    info "Checking if nginx is already installed..."
    if ! dpkg -l | grep -q nginx; then
        info "Installing nginx..."
        if ! sudo apt install -y nginx; then
            error "Failed to install nginx."
            exit 1
        fi
    else
        warn "nginx is already installed."
    fi

    info "Checking if mysql-server is already installed..."
    if ! dpkg -l | grep -q mysql-server; then
        info "Installing mysql-server..."
        if ! sudo apt install -y mysql-server; then
            error "Failed to install mysql-server."
            exit 1
        fi
    else
        warn "mysql-server is already installed."
    fi

    info "Installing php packages..."
    if ! sudo apt install -y php8.1-fpm php-mysql; then
        error "Failed to install PHP packages."
        exit 1
    fi
}

main() {
    info "Starting system update..."
    update_system

    info "Starting package installation..."
    install_packages

    info "Script completed successfully."
}

main
