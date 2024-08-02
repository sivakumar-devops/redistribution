#!/usr/bin/env bash
# Copyright (c) Syncfusion Inc. All rights reserved.
#

# Set environment variable
export OPENSSL_CONF=/etc/ssl/

# Save the current directory
pushd . > /dev/null

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

    info "Creating MySQL database..."
    create_database

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

    info "Configuring WordPress..."
    setup_wp_config

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

# Function to install Bold BI
install_boldbi() {
    info "Downloading and unzipping Bold BI package..."

    # Define the package file name
    package_file="BoldBIEnterpriseEdition_Linux.zip"

    # Remove the package file if it already exists
    if [ -f "$package_file" ]; then
            rm "$package_file"
            if [ $? -ne 0 ]; then
                    info "Failed to remove existing Bold BI package."
                    exit 1
            fi
    fi

    # Download the package
    wget "$package_link" >> "$LOG_FILE" 2>&1

    # Check if the download was successful
    if [ $? -ne 0 ]; then
        info "Failed to download Bold BI package."
        exit 1
    fi

    # Unzip the downloaded package
    unzip BoldBIEnterpriseEdition_Linux.zip >> "$LOG_FILE" 2>&1
        Unzip the downloaded package, replacing existing files
        unzip -o "$package_file"

    # Check if the unzip was successful
    if [ $? -ne 0 ]; then
        info "Failed to unzip Bold BI package."
        exit 1
    fi

    cd BoldBIEnterpriseEdition-Linux || { info "Failed to change directory."; exit 1; }

    info "Executing installation command..."

echo "    bash install-boldbi.sh -i "$install_type" \
                           -u "$user" \
                           -h "$host_url/dashboard" \
                           -n "$nginx" \
                           -license "$license_key" \
                           -databasetype "$database_type" \
                           -databasehost "$database_host" \
                           -databaseport "$database_port" \
                           -maintaindb "$maintain_db" \
                           -databaseuser "$database_user" \
                           -databasepwd "$database_pwd" \
                           -databasename "$database_name" \
                           -email "$email" \
                           -emailpwd "$email_pwd" \
                           -mainlogo "$main_logo" \
                           -loginlogo "$login_logo" \
                           -emaillogo "$email_logo" \
                           -favicon "$favicon" \
                           -footerlogo "$footer_logo" \
                           -sitename "$site_name" \
                           -siteidentifier "$site_identifier" "

    info "Bold BI package installed successfully."
}

configure_nginx() {
    # Variables
    NGINX_SITES_AVAILABLE="/etc/nginx/sites-available"
    NGINX_SITES_ENABLED="/etc/nginx/sites-enabled"
    WORDPRESS_CONFIG="wordpress"
    NGINX_RELOAD_CMD="systemctl reload nginx"

    # Function to create configuration file
    create_nginx_config() {
        cat <<EOF > ${NGINX_SITES_AVAILABLE}/${WORDPRESS_CONFIG}
server {
    listen 80;
    server_name your_domain www.your_domain;
    root /var/www/wordpress;

    index index.php index.html index.htm;

    access_log /var/log/nginx/wordpress_access.log;
    error_log /var/log/nginx/wordpress_error.log;

    location / {
        try_files \$uri \$uri/ /index.php?\$args;
    }

    location ~ \.php\$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/var/run/php/php8.1-fpm.sock;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        include fastcgi_params;
    }

    location = /favicon.ico { log_not_found off; access_log off; }
    location = /robots.txt { log_not_found off; access_log off; allow all; }
    location ~* \.(css|gif|ico|jpeg|jpg|js|png)\$ {
        expires max;
        log_not_found off;
    }

    location ~ /\.ht {
        deny all;
    }

    # BoldBI Locations
    location /dashboard/ {
        root /var/www/bold-services/application/idp/web/wwwroot;
        proxy_pass http://localhost:6500/dashboard/;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection keep-alive;
        proxy_set_header Host \$http_host;
        proxy_cache_bypass \$http_upgrade;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        fastcgi_buffers 16 16k;
        fastcgi_buffer_size 32k;
    }

    location /dashboard/api {
        proxy_pass http://localhost:6501/dashboard/api;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection keep-alive;
        proxy_set_header Host \$http_host;
        proxy_cache_bypass \$http_upgrade;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    location /dashboard/ums {
        root /var/www/bold-services/application/idp/ums;
        proxy_pass http://localhost:6502/dashboard/ums;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection keep-alive;
        proxy_set_header Host \$http_host;
        proxy_cache_bypass \$http_upgrade;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    location /dashboard/bi {
        root /var/www/bold-services/application/bi/web/wwwroot;
        proxy_pass http://localhost:6504/dashboard/bi;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection keep-alive;
        proxy_set_header Host \$http_host;
        proxy_cache_bypass \$http_upgrade;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    location /dashboard/bi/api {
        proxy_pass http://localhost:6505/dashboard/bi/api;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection keep-alive;
        proxy_set_header Host \$http_host;
        proxy_cache_bypass \$http_upgrade;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    location /dashboard/bi/jobs {
        proxy_pass http://localhost:6506/dashboard/bi/jobs;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection keep-alive;
        proxy_set_header Host \$http_host;
        proxy_cache_bypass \$http_upgrade;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    location /dashboard/bi/designer {
        root /var/www/bold-services/application/bi/designer/wwwroot;
        proxy_pass http://localhost:6507/dashboard/bi/designer;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection keep-alive;
        proxy_set_header Host \$http_host;
        proxy_cache_bypass \$http_upgrade;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    location /dashboard/bi/designer/helper {
        proxy_pass http://localhost:6507/dashboard/bi/designer/helper;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$http_host;
        proxy_cache_bypass \$http_upgrade;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF
    }

    # Function to enable site
    enable_site() {
        if [ ! -L ${NGINX_SITES_ENABLED}/${WORDPRESS_CONFIG} ]; then
            ln -s ${NGINX_SITES_AVAILABLE}/${WORDPRESS_CONFIG} ${NGINX_SITES_ENABLED}/${WORDPRESS_CONFIG}
        fi
    }

    # Function to reload NGINX
    reload_nginx() {
        ${NGINX_RELOAD_CMD}
    }

    # Main function execution
    create_nginx_config
    enable_site
    reload_nginx

    echo "NGINX configuration for WordPress and BoldBI has been set up and reloaded."
}


# Main function to execute the script
main() {
    local force_reinstall=false
    local install_type=""
    local user=""
    local host_url=""
    local nginx=""
    local package_link=""
    local license_key=""
    local database_type=""
    local database_host=""
    local database_port=""
    local maintain_db=""
    local database_user=""
    local database_pwd=""
    local database_name=""
    local email=""
    local email_pwd=""
    local main_logo=""
    local login_logo=""
    local email_logo=""
    local favicon=""
    local footer_logo=""
    local site_name=""
    local site_identifier=""

    # Parse command line arguments
    options=$(getopt -o '' -l install-type:,user:,host-url:,nginx:,package-link:,force-reinstall,license-key:,database-type:,database-host:,database-port:,maintain-db:,database-user:,database-password:,database-name:,email:,email-password:,main-logo:,login-logo:,email-logo:,favicon:,footer-logo:,site-name:,site-identifier: -- "$@")
    eval set -- "$options"

    while true; do
        case "$1" in
            --install-type) install_type=$2; shift 2 ;;
            --user) user=$2; shift 2 ;;
            --host-url) host_url=$2; shift 2 ;;
            --nginx) nginx=$2; shift 2 ;;
            --package-link) package_link=$2; shift 2 ;;
            --force-reinstall) force_reinstall=true; shift ;;
            --license-key) license_key=$2; shift 2 ;;
            --database-type) database_type=$2; shift 2 ;;
            --database-host) database_host=$2; shift 2 ;;
            --database-port) database_port=$2; shift 2 ;;
            --maintain-db) maintain_db=$2; shift 2 ;;
            --database-user) database_user=$2; shift 2 ;;
            --database-password) database_pwd=$2; shift 2 ;;
            --database-name) database_name=$2; shift 2 ;;
            --email) email=$2; shift 2 ;;
            --email-password) email_pwd=$2; shift 2 ;;
            --main-logo) main_logo=$2; shift 2 ;;
            --login-logo) login_logo=$2; shift 2 ;;
            --email-logo) email_logo=$2; shift 2 ;;
            --favicon) favicon=$2; shift 2 ;;
            --footer-logo) footer_logo=$2; shift 2 ;;
            --site-name) site_name=$2; shift 2 ;;
            --site-identifier) site_identifier=$2; shift 2 ;;
            --) shift; break ;;
            *) echo "Invalid option: $1" >&2; exit 1 ;;
        esac
    done

    # Output parsed arguments for verification
    echo "Install Type: $install_type"
    echo "User: $user"
    echo "Host URL: $host_url"
    echo "Nginx: $nginx"
    echo "Package Link: $package_link"
    echo "Force Reinstall: $force_reinstall"
    echo "License Key: $license_key"
    echo "Database Type: $database_type"
    echo "Database Host: $database_host"
    echo "Database Port: $database_port"
    echo "Maintain DB: $maintain_db"
    echo "Database User: $database_user"
    echo "Database Password: $database_pwd"
    echo "Database Name: $database_name"
    echo "Email: $email"
    echo "Email Password: $email_pwd"
    echo "Main Logo: $main_logo"
    echo "Login Logo: $login_logo"
    echo "Email Logo: $email_logo"
    echo "Favicon: $favicon"
    echo "Footer Logo: $footer_logo"
    echo "Site Name: $site_name"
    echo "Site Identifier: $site_identifier"

    info "Starting system update..."
    update_system

    info "Starting package installation..."
    install_packages "$force_reinstall"

    info "Starting WordPress installation..."
    install_wordpress

    # Return to the original directory
    popd > /dev/null

    info "Bold Bi installation installation..."
    install_boldbi

    info "configure nginx..."
    configure_nginx

    info "Script completed successfully."


}

# Call the main function with all script arguments
main "$@"
