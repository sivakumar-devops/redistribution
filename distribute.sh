#!/usr/bin/env bash
# Copyright (c) Syncfusion Inc. All rights reserved.
#

# Set environment variable
export OPENSSL_CONF=/etc/ssl/

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

# Function to create MySQL database and user
create_database() {
    local mysql_user="root"
    local mysql_psw=""
    local db_name="wordpress"
    local db_user="wordpressuser"
    local db_pass="password"  # Replace with actual user password

    info "Creating MySQL database and user..."

    # Create or update the .my.cnf file
    cat > ~/.my.cnf <<EOF
[client]
user=$mysql_user
password="$mysql_psw"
EOF

    # Set file permissions
    chmod 600 ~/.my.cnf

    # Use `mysql` command with the .my.cnf file for authentication
    mysql <<EOF
    -- Check if the database exists
    CREATE DATABASE IF NOT EXISTS $db_name DEFAULT CHARACTER SET utf8 COLLATE utf8_unicode_ci;

    -- Create the user if it does not exist
    CREATE USER IF NOT EXISTS '$db_user'@'localhost' IDENTIFIED BY '$db_pass';

    -- Grant permissions
    GRANT ALL ON $db_name.* TO '$db_user'@'localhost';
    FLUSH PRIVILEGES;

    -- Verify the database and user creation
    SHOW DATABASES LIKE '$db_name';
    SELECT user, host FROM mysql.user WHERE user = '$db_user';
EOF

    info "MySQL database and user created successfully."
}

# Function to install WordPress
install_wordpress() {
    info "Starting WordPress installation..."

    cd /tmp || { error "Failed to change directory to /tmp"; exit 1; }

    if ! curl -LO https://wordpress.org/latest.tar.gz >> "$LOG_FILE" 2>&1; then
        error "Failed to download WordPress."
        exit 1
    fi

    if ! tar xzvf latest.tar.gz >> "$LOG_FILE" 2>&1; then
        error "Failed to extract WordPress."
        exit 1
    fi

    if ! cp /tmp/wordpress/wp-config-sample.php /tmp/wordpress/wp-config.php >> "$LOG_FILE" 2>&1; then
        error "Failed to copy wp-config.php."
        exit 1
    fi

    if ! sudo cp -a /tmp/wordpress/. /var/www/wordpress >> "$LOG_FILE" 2>&1; then
        error "Failed to copy WordPress files to /var/www/wordpress."
        exit 1
    fi

    if ! sudo chown -R www-data:www-data /var/www/wordpress >> "$LOG_FILE" 2>&1; then
        error "Failed to change ownership of WordPress files."
        exit 1
    fi

    info "WordPress installation completed successfully."
}

# Function to configure WordPress
setup_wp_config() {
    local wp_config_file="/var/www/wordpress/wp-config.php"
    local db_name="wordpress"
    local db_user="wordpressuser"
    local db_password="password"

    # Fetch secure keys from the WordPress secret key generator
    local secure_keys
    secure_keys=$(curl -s https://api.wordpress.org/secret-key/1.1/salt/)

    # Check if the curl command was successful
    if [ $? -ne 0 ]; then
        error "Failed to fetch secure keys from the WordPress API. Exiting..."
        exit 1
    fi

    # Handle backup file
    local backup_file="${wp_config_file}.bak"
    if [ -f "$backup_file" ]; then
        info "Backup file already exists. Removing it..."
        rm -f "$backup_file"
    fi

    info "Backing up the existing WordPress configuration file..."
    cp "$wp_config_file" "$backup_file"

    # Check if the backup command was successful
    if [ $? -ne 0 ]; then
        error "Failed to backup the WordPress configuration file. Exiting..."
        exit 1
    fi

    info "Updating the WordPress configuration file with secure keys and salts..."

    # Remove old key and salt lines and add new ones
    sed -i '/AUTH_KEY/d' "$wp_config_file"
    sed -i '/SECURE_AUTH_KEY/d' "$wp_config_file"
    sed -i '/LOGGED_IN_KEY/d' "$wp_config_file"
    sed -i '/NONCE_KEY/d' "$wp_config_file"
    sed -i '/AUTH_SALT/d' "$wp_config_file"
    sed -i '/SECURE_AUTH_SALT/d' "$wp_config_file"
    sed -i '/LOGGED_IN_SALT/d' "$wp_config_file"
    sed -i '/NONCE_SALT/d' "$wp_config_file"

    # Append new keys and salts
    echo "$secure_keys" >> "$wp_config_file"

    # Update database configuration
    sed -i "s/define( 'DB_NAME'.*/define( 'DB_NAME', '$db_name' );/" "$wp_config_file"
    sed -i "s/define( 'DB_USER'.*/define( 'DB_USER', '$db_user' );/" "$wp_config_file"
    sed -i "s/define( 'DB_PASSWORD'.*/define( 'DB_PASSWORD', '$db_password' );/" "$wp_config_file"

    # Add FS_METHOD configuration
    if ! grep -q "define( 'FS_METHOD', 'direct' );" "$wp_config_file"; then
        echo "define( 'FS_METHOD', 'direct' );" >> "$wp_config_file"
    fi

    info "WordPress configuration file updated successfully."
}

# Main function to execute the script
main() {
    local force_reinstall=false
    local install_new=""
    local user=""
    local host_url=""
    local notify=false
    local package_link=""

    # Parse command line arguments
    while getopts "i:u:h:n:p:f" opt; do
        case $opt in
            i) install_new=$OPTARG ;;
            u) user=$OPTARG ;;
            h) host_url=$OPTARG ;;
            n) notify=$OPTARG ;;
            p) package_link=$OPTARG ;;
            f) force_reinstall=true ;;
            \?) error "Invalid option: -$OPTARG" >&2; exit 1 ;;
        esac
    done

    info "Package link: $package_link"

    info "Starting system update..."
    update_system

    info "Starting package installation..."
    install_packages "$force_reinstall"

    info "Creating MySQL database..."
    create_database

    info "Starting WordPress installation..."
    install_wordpress

    info "Configuring WordPress..."
    setup_wp_config

    info "Script completed successfully."

    info "Install new: $install_new"
    info "User: $user"
    info "Host URL: $host_url"
    info "Notify: $notify"
}

main "$@"
