#!/bin/bash

## Configuration ####################################################
#                                                                   #
# The Synful Version to provision this box with.                    #
SYNFUL_VERSION="v2.0.4"                                             #
#                                                                   #
# If set to true, Sql will be allowed access from external sources. #
SQL_OVER_NETWORK=false                                              #
#                                                                   #
# The password to set for the root mysql user.                      #
MYSQL_PASSWORD="mysqlpassword"                                      #
#                                                                   #
## End Configuration ################################################

# Valid versions of Synful that this script can install.
# DO NOT CHANGE THIS.
VALID_VERSIONS=(
    "dev-unstable"
    "v2.0.0"
    "v2.0.1"
    "v2.0.2"
    "v2.0.3"
    "v2.0.4"
)

LATEST_VERSION=`git ls-remote --tags http://git.synful.io 2>/dev/null | tail -n1 | awk -F/ '{ print $3 }'`

function main()
{
    log "----------------------------------"
    log "Synful Provisioning Utility v0.5.5"
    log "----------------------------------"
    log "----------------------------------"

    if [[ $EUID -ne 0 ]]; then
       log "Error: This script must be run as root" 
       exit 1
    fi
    
    log "Configuration ..."
    log "----------------------------------"
    log "Version:"    
    log "    Latest Version: $LATEST_VERSION"
    prompt "    Select Version (leave blank for $LATEST_VERSION) : "
    
    SYNFUL_VERSION=$PROMPT_VAL
    
    if [ "$SYNFUL_VERSION" == "" ]; then
        SYNFUL_VERSION=$LATEST_VERSION  
    fi
    
    if [ $(validate_version) == 0 ]; then
        log "    Error: Invalid version '$SYNFUL_VERSION'."
        log "    Valid Versions: ${VALID_VERSIONS[*]}"
        exit 2
    fi
    
    log "MySql Password:"
    sprompt "    Enter a new MySql root password (leave blank for 'password') : "
    if [ "$SPROMPT_VAL" == "" ]; then
        echo '' # Complete the new line after secure input
        MYSQL_PASSWORD=password
    else
       echo '' # Complete the new line after secure input
       P1=$SPROMPT_VAL
       sprompt "    Re-Type the new MySql root password : "
       if [ "$P1" != "$SPROMPT_VAL" ]; then
           echo '' # Complete the new line after secure input
           log "    Error: MySql passwords do not match."
           exit 3
       else
           echo '' # Complete the new line after secure input
           MYSQL_PASSWORD=$P1
       fi
    fi
    
    log "MySql Network:"
    prompt "    Allow MySql external access? (y/n) : "
    if [[ "$PROMPT_VAL" != "y" && "$PROMPT_VAL" != "n" ]]; then
        log "    Invalid entry. Please enter 'y' or 'n'."
        exit 4
    elif [ "$PROMPT_VAL" == "y" ]; then
            SQL_OVER_NETWORK=true
    fi
    
    log "----------------------------------"
    log "Installing Synful $SYNFUL_VERSION "
    log "----------------------------------"

    # Install Dependencies
    install_dependencies;

    # Instal MySql
    install_mysql
    if [ "$SQL_OVER_NETWORK" = true ]; then
        mysql_network_allow
    fi

    # Download and Configure Synful
    download

    # Configure Apache
    configure_apache

    # Install Synful
    install_synful

    log "----------------------------------"

    # Display Results
    display_results
}

function validate_version()
{
    FOUND=0
    for version in "${VALID_VERSIONS[@]}"; do
        [[ "$SYNFUL_VERSION" == "$version" ]] && FOUND=1
    done

    echo $FOUND
}

function install_dependencies()
{
    log "Updating packages..."
    apt-get -y update >/dev/null 2>&1

    log "Adding repo lists..."
    apt-get install python-software-properties -y >/dev/null 2>&1
    add-apt-repository ppa:ondrej/php -y >/dev/null 2>&1
    apt-get -y update >/dev/null 2>&1

    log "Installing Dependencies..."
    packagelist=(

        # For controlling Synful from the command line
        php7.2-cli

        # For installing dependencies
        composer

        # Composer Dependency
        php7.2-zip

        # Composer Dependency
        unzip

        # The web server
        apache2

        # PHP
        php7.2

        # For using PHP with Apache
        libapache2-mod-php7.2

        # For using MySql with PHP
        php7.2-mysql

        # For certain PHP dependencies
        php7.2-mbstring

        # For controlling MySql
        mysql-client
        
        # For benchmarking
        apache2-utils

    )

    apt-get install -y ${packagelist[@]} >/dev/null 2>&1
}

function install_mysql()
{
    # We install MySql separately from everything else
    # so that we can configure it using debconf-utils
    # before we begin installing it. This helps us
    # avoid any reliance on user input.
    log "Installing MySql Server..."
    apt-get install -y debconf-utils > /dev/null 2>&1
    debconf-set-selections <<< \
        "mysql-server mysql-server/root_password password $MYSQL_PASSWORD" \
    >/dev/null 2>&1
    debconf-set-selections <<< \
        "mysql-server mysql-server/root_password_again password $MYSQL_PASSWORD" \
    >/dev/null 2>&1
    apt-get -y install mysql-server > /dev/null 2>&1
    
    log "Creating default database..."
    mysql -u root -p$MYSQL_PASSWORD -e "CREATE DATABASE synful" >/dev/null 2>&1
}
function mysql_network_allow()
{
    # If you want your MySql server to be accessible to external 
    # requests, this section will update the mysqld.cnf file and
    # the permissions around the root user.
    # 
    # This is not recommended. 
    # Only your API should have access to your database.
    log "Making MySql accessible over network..."
    sed -i '43s!127.0.0.1!0.0.0.0!' /etc/mysql/mysql.conf.d/mysqld.cnf
    log "Restarting MySql Service..."
    service mysql restart >/dev/null 2>&1
    log "Updating SQL Permissions..."
    mysql -u root -p$MYSQL_PASSWORD -e \
        "USE mysql;" \
        "UPDATE user SET host='%' WHERE User='root';" \
        "GRANT ALL ON *.* TO 'root'@'%';" \
        "FLUSH PRIVILEGES;" \
    >/dev/null 2>&1
}
function download()
{
    # Download Synful from git and
    # checkout the tag associated
    # with the configured version.
    log "Downloading Synful..."
    rm -rf /var/www/html >/dev/null 2>&1
    mkdir /var/www/html >/dev/null 2>&1
    git clone \
    http://git.synful.io \
    /var/www/html >/dev/null 2>&1
    cd /var/www/html
    
    if [[ "$SYNFUL_VERSION" != "dev-unstable" ]]; then
        git checkout tags/$SYNFUL_VERSION >/dev/null 2>&1
        log "`git status | head -n1`"
    fi
    # Update the Synful configuration 
    # to match the configured Sql Password.
    log "Updating Synful configuration..."
    sed -i "20s!password',!$MYSQL_PASSWORD',!" /var/www/html/config/Databases.php
}
function configure_apache()
{
    # Update the Site Root to match that of our Synful installation
    log "Setting site root..."
    sed -i '12s!/var/www/html!/var/www/html/public!' /etc/apache2/sites-enabled/000-default.conf
    sed -i '164s!/var/www!/var/www/html/public!' /etc/apache2/apache2.conf
    # Enable ModRewrite so that endpoints work properly
    log "Enabling modrewrite..."
    a2enmod rewrite >/dev/null 2>&1
    sed -i '155s!None!All!' /etc/apache2/apache2.conf
    sed -i '166s!None!All!' /etc/apache2/apache2.conf
    # Restart apache
    service apache2 restart
}
function install_synful()
{
    cd /var/www/html
    log "Installing Synful..."
    # Run ./synful install to install Synful's dependencies
    # and create the default tables for storing API keys.
    ./synful install >/dev/null 2>&1
}
function display_results()
{
    log "Done!"
    log "----------------------------------"
    log "MySql Credentials: [ Username = root, Password = YES, Database = synful ]"
    log "----------------------------------"
    log "You can access your Synful API at one of the following addresses:";
    for ip in $( hostname -I ); do
        log "    http://"$ip"/";
    done;
    log "----------------------------------"
    log "Access Synful CLI in /var/www/html by running './synful'."
    log "----------------------------------"
    log "Exiting..."
}
function log()
{
    if [[ "$1" == "-n" ]]; then
        echo -e -n "\033[1;32m[\033[1;37mSYNFUL\033[1;32m]\033[0m $2"
    else
        echo -e "\033[1;32m[\033[1;37mSYNFUL\033[1;32m]\033[0m $1"
    fi
}
# Result stored in $PROMT_VAL
function prompt()
{
    log -n "$1"
    read PROMPT_VAL
}
# Result stored in $SPROMPT_VAL
function sprompt()
{
    log -n "$1"
    read -s SPROMPT_VAL
}
# Initialize the provisioning process
main