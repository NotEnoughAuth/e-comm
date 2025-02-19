#!/bin/bash
# Check if the script is being run as root
if [[ $EUID -ne 0 ]]
then
  printf 'Must be run as root, exiting!\n'
  exit 1
fi

CCDC_DIR="/ccdc"
CCDC_ETC="$CCDC_DIR/etc"
SCRIPT_DIR="/ccdc/scripts"
LOGFILE="$CCDC_DIR/logs/monolith-log.txt"

# Color Variables
RED='\033[0;31m'
NC='\033[0m'
BLUE='\033[0;34m'
GREEN='\033[0;32m'


sendLog(){
    if [ ! -f $LOGFILE ]; then
        mkdir -p $CCDC_DIR/logs
        touch $LOGFILE
    fi
    if [ -z "$1" ]; then
        echo "No message provided to log"
        return 1
    fi
    echo "$(date +"%x %X") - $1" >> $LOGFILE
}

sendError(){
    if [ ! -f $LOGFILE ]; then
        touch $LOGFILE
    fi
    if [ -z "$1" ]; then
        echo "No message provided to log"
        return 1
    fi
    echo "$RED$(date +"%x %X") - ERROR: $1$NC" >> $LOGFILE
}


# get the OS ID
OS_ID=$(cat /etc/os-release | grep ^ID= | cut -d'=' -f2)

# get the OS VERSION_ID
OS_VERSION_ID=$(cat /etc/os-release | grep ^VERSION_ID= | cut -d'=' -f2)

# Echo the OS_ID and OS_VERSION_ID
echo "OS_ID=$OS_ID"
echo "OS_VERSION_ID=$OS_VERSION_ID"

# This is where we run some prerequisits that are needed for the rest of the scripts to run
prescripts(){

    #////////////////////////////////////////
    # Check if the system is running Prestashop
    #////////////////////////////////////////
    # Check if the system is running prestashop and get the MySQL root password
    if [ -d /var/www/html/prestashop ]; then
        if [ $(which mysql) ]; then
            PRESTASHOP="true"
            ATTEMPTS=0
            CORRECT_PASS="random_text"
            while ([ ! -z "$CORRECT_PASS" ]) && [ $ATTEMPTS -le 2 ]; do
                # Get the MySQL root password
                read -p "Enter the MySQL root password: " -s MYSQL_ROOT_PASSWORD

                # Check if the password is correct, it also may be blank
                if [ -z "$MYSQL_ROOT_PASSWORD" ]; then
                    CORRECT_PASS=$(mysql -u root -e "exit" 2>/dev/stdout)
                else
                    CORRECT_PASS=$(mysql -u root -p$MYSQL_ROOT_PASSWORD -e "exit" 2>/dev/stdout)
                fi
                ATTEMPTS=$((ATTEMPTS+1))
                echo
            done

            if [ ! -z "$CORRECT_PASS" ]; then
                echo "Could not connect to MySQL please run the scripts for mysql manually"
                MYSQL="false"
            else
                MYSQL="true"
                sendLog "Prestashop is installed on the system, and MySQL has been configured"
            fi
        else
            MYSQL="false"
            sendError "Could not connect to MySQL, please check the password and try again"
        fi

    else
        PRESTASHOP="false"
    fi

    # Check if the system is running apache
    if [ -d /etc/httpd ]; then
        APACHE="true"
    elif [ -d /etc/apache2 ]; then
        APACHE="true"
    else
        APACHE="false"
    fi

    #////////////////////////////////////////
    # CCDC Directory Creation
    #////////////////////////////////////////
    # Create the ccdc directory
    if [ ! -d $CCDC_DIR ]; then
        mkdir $CCDC_DIR
        sendLog "CCDC directory created"
    fi
    # Check if the linux directory exists within the script directory, if it does not, create it
    if [ ! -d "$SCRIPT_DIR/linux" ]; then
        mkdir -p $SCRIPT_DIR/linux
        sendLog "Linux directory created"
    fi

    # Check if the logs directory exists within the ccdc directory, if it does not, create it
    if [ ! -d "$CCDC_DIR/logs" ]; then
        mkdir -p $CCDC_DIR/logs
        sendLog "Logs directory created"
    fi

    #////////////////////////////////////////
    # CentOS 7 Fixes
    #////////////////////////////////////////
    if [ "$OS_ID" == "centos" ] && [ "$OS_VERSION_ID" == "7" ]; then
        # if the system is running CentOS 7, we need to add the new repositories
        cat <<'EOF' > /etc/yum.repos.d/CentOS-Base.repo
        # CentOS-Base.repo
#
# The mirror system uses the connecting IP address of the client and the
# update status of each mirror to pick mirrors that are updated to and
# geographically close to the client.  You should use this for CentOS updates
# unless you are manually picking other mirrors.
#
# If the mirrorlist= does not work for you, as a fall back you can try the
# remarked out baseurl= line instead.
#
#

[base]
name=CentOS-$releasever - Base
#mirrorlist=http://mirrorlist.centos.org/?release=$releasever&arch=$basearch&repo=os&infra=$infra
baseurl=http://vault.centos.org/centos/$releasever/os/$basearch/
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-CentOS-7

#released updates
[updates]
name=CentOS-$releasever - Updates
#mirrorlist=http://mirrorlist.centos.org/?release=$releasever&arch=$basearch&repo=updates&infra=$infra
baseurl=http://vault.centos.org/centos/$releasever/updates/$basearch/
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-CentOS-7

#additional packages that may be useful
[extras]
name=CentOS-$releasever - Extras
#mirrorlist=http://mirrorlist.centos.org/?release=$releasever&arch=$basearch&repo=extras&infra=$infra
baseurl=http://vault.centos.org/centos/$releasever/extras/$basearch/
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-CentOS-7

#additional packages that extend functionality of existing packages
[centosplus]
name=CentOS-$releasever - Plus
#mirrorlist=http://mirrorlist.centos.org/?release=$releasever&arch=$basearch&repo=centosplus&infra=$infra
baseurl=http://vault.centos.org/centos/$releasever/centosplus/$basearch/
gpgcheck=1
enabled=0
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-CentOS-7
EOF
        # Clean the yum cache
        yum -v clean expire-cache

        # update the certificates on the system
        yum update -y ca-certificates
        yum install -y epel-release wget

        sendLog "CentOS 7 Fixes applied"
    fi


}

configure_networking(){
    #////////////////////////////////////////
    # Configure Networking
    #////////////////////////////////////////
    # Check if the system is running CentOS 7
    if [ "$OS_ID" == "centos" ] && [ "$OS_VERSION_ID" == "7" ]; then
        echo "Setting up DNS..."
        INTERFACE=$(ip route | grep default | awk '{print $5}')
        sed -i 's/DNS1='.*'/DNS1=1.1.1.1/g' /etc/sysconfig/network-scripts/ifcfg-$INTERFACE
        sed -i 's/DNS2='.*'/DNS2=9.9.9.9/g' /etc/sysconfig/network-scripts/ifcfg-$INTERFACE
        systemctl restart network
        sendLog "New DNS servers set"
    fi
    # Check if the system is running Ubuntu
    if [ "$OS_ID" == "ubuntu" ]; then
        echo "Setting up DNS..."
        echo "nameserver 1.1.1.1" > /etc/resolv.conf
        echo "nameserver 1.0.0.1" >> /etc/resolv.conf
        sendLog "New DNS servers set"
        #TODO: Add DNS configuration for Ubuntu via netplan
    fi
}

lock_users(){
    #////////////////////////////////////////
    # Lock Users
    #////////////////////////////////////////
    # lock all users except root
    cat <<'EOF' > $SCRIPT_DIR/linux/lock_users.sh
#!/bin/bash
if [[ $EUID -ne 0 ]]
then
  printf 'Must be run as root, exiting!\n'
  exit 1
fi

# Get the current user, even if running with sudo
if [[ -n "$SUDO_USER" ]]; then
    CURRENT_USER="$SUDO_USER"
else
    CURRENT_USER="$USER"
fi

# Get a list of users from /etc/passwd, and allow the user to select what users to keep with a simple yes/no prompt
while read -r line; do
    # Get the username
    username=$(echo $line | cut -d: -f1)
    # Check if the user is root
    if [ "$username" == "root" ] || [ "$username" == "$CURRENT_USER" ]; then
        # Skip the root user and the current user
        continue
    fi
    # Lock the user account if the user is not already locked
    if [ $(echo $line | cut -d: -f7) != "/sbin/nologin" ]; then
        usermod -s /sbin/nologin $username
        passwd -l $username
        echo -n "$username "
    fi
done < /etc/passwd
echo
EOF
    chmod +x $SCRIPT_DIR/linux/lock_users.sh
    LOCKED_USERS=$(bash $SCRIPT_DIR/linux/lock_users.sh)
    sendLog "Users locked: $LOCKED_USERS"
}

iptables(){
    #////////////////////////////////////////
    # Configure iptables
    #////////////////////////////////////////
    # Check for the package manager 
    if [ -x "$(command -v apt-get)" ]; then
        apt-get install iptables -y
    elif [ -x "$(command -v yum)" ]; then
        yum install iptables -y
    fi

    #////////////////////////////////////////
    # Configure iptables
    #////////////////////////////////////////
    IPTABLES_SCRIPT="$SCRIPT_DIR/linux/iptables.sh"
    cat <<EOF > $IPTABLES_SCRIPT
#!/bin/bash
if [[ \$EUID -ne 0 ]]
then
  printf 'Must be run as root, exiting!\n'
  exit 1
fi

# Empty all rules
iptables -t filter -F
iptables -t filter -X

# Block everything by default
iptables -t filter -P INPUT DROP
iptables -t filter -P FORWARD DROP
iptables -t filter -P OUTPUT DROP

# Authorize already established connections
iptables -A INPUT -m state --state RELATED,ESTABLISHED -j ACCEPT
iptables -A OUTPUT -m state --state RELATED,ESTABLISHED -j ACCEPT
iptables -t filter -A INPUT -i lo -j ACCEPT
iptables -t filter -A OUTPUT -o lo -j ACCEPT

# ICMP (Ping)
iptables -t filter -A INPUT -p icmp -j ACCEPT
iptables -t filter -A OUTPUT -p icmp -j ACCEPT

# Deny outbound traffic to RFC 1918 addresses (do not need to communicate with private IP addresses)
iptables -t filter -A OUTPUT -d 10.0.0.0/8 -j REJECT
iptables -t filter -A OUTPUT -d 172.16.0.0/12 -j REJECT
iptables -t filter -A OUTPUT -d 192.168.0.0/16 -j REJECT

# DNS (Needed for curl, and updates)
iptables -t filter -A OUTPUT -p tcp --dport 53 -j ACCEPT
iptables -t filter -A OUTPUT -p udp --dport 53 -j ACCEPT

# HTTP/HTTPS
iptables -t filter -A OUTPUT -p tcp --dport 80 -j ACCEPT
iptables -t filter -A OUTPUT -p tcp --dport 443 -j ACCEPT

# NTP (server time)
iptables -t filter -A OUTPUT -p udp --dport 123 -j ACCEPT

# # Splunk
# iptables -t filter -A OUTPUT -p tcp --dport 8000 -j ACCEPT
# iptables -t filter -A OUTPUT -p tcp --dport 8089 -j ACCEPT
# iptables -t filter -A OUTPUT -p tcp --dport 9997 -j ACCEPT

######## OUTBOUND SERVICES ###############
EOF
    if [ "$APACHE" == "true" ]; then
        cat <<EOF >> $IPTABLES_SCRIPT
# HTTP/HTTPS (apache)
iptables -t filter -A INPUT -p tcp --dport 80 -j ACCEPT
iptables -t filter -A INPUT -p tcp --dport 443 -j ACCEPT
EOF
    fi

    # Make the script executable
    chmod +x $IPTABLES_SCRIPT

    bash $IPTABLES_SCRIPT
    sendLog "Iptables rules configured"

    # Create systemd unit for the firewall
    mkdir -p /etc/systemd/system/
    cat <<-EOF > /etc/systemd/system/ccdc_firewall.service
[Unit]
Description=ZDSFirewall
After=syslog.target network.target

[Service]
Type=oneshot
ExecStart=$IPTABLES_SCRIPT 
ExecStop=/sbin/iptables -F
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable ccdc_firewall
    systemctl start ccdc_firewall

    systemctl disable --now firewalld
    systemctl disable --now ufw

    sendLog "Firewall service created and is $(systemctl is-active ccdc_firewall)"
}

prestashop_config(){
    #////////////////////////////////////////
    # Prestashop Configuration
    #////////////////////////////////////////
    # Configure prestashop hardening
    # Zip up the /var/www/html directory and move it to /bkp
    # Check if the /bkp directory exists, if it does not, create it
    if [ ! -d "/bkp/original" ]; then
        mkdir -p /bkp/original
    fi
    if [ -f "/bkp/original/html.tar.gz" ]; then
        echo "Prestashop backup already exists, skipping backup"
        sendLog "Prestashop directory already backed up"
    else
        echo "Zipping up /var/www/html..."
        tar -czf /bkp/original/html.tar.gz /var/www/html
        sendLog "Prestashop directory backed up"
    fi

    # zip up the apache config directory and move it to /bkp
    if [ -d "/etc/httpd" ]; then
        if [ -f "/bkp/original/httpd.tar.gz" ]; then
            echo "Apache backup already exists, skipping backup"
            sendLog "Apache directory already backed up"
        else
            echo "Zipping up /etc/httpd..."
            tar -czf /bkp/original/httpd.tar.gz /etc/httpd
            sendLog "Apache directory backed up"
        fi
    elif [ -d "/etc/apache2" ]; then
        if [ -f "/bkp/original/apache2.tar.gz" ]; then
            echo "Apache backup already exists, skipping backup"
            sendLog "Apache directory already backed up"
        else
            echo "Zipping up /etc/apache2..."
            tar -czf /bkp/original/apache2.tar.gz /etc/apache2
            sendLog "Apache directory backed up"
        fi
    fi  
    

    if [ "$MYSQL" == "true" ]; then
        # backup the mysql database
        if [ -f "/bkp/original/ecomm.sql" ]; then
            echo "MySQL backup already exists, skipping backup"
            sendLog "MySQL database already backed up"
        else
            echo "Backing up MySQL database..."
            if [ -z "$MYSQL_ROOT_PASSWORD" ]; then
                mysqldump -u root --all-databases > /bkp/original/ecomm.sql
                sendLog "MySQL database backed up"
            else
                mysqldump -u root -p$MYSQL_ROOT_PASSWORD --all-databases > /bkp/original/ecomm.sql
                sendLog "MySQL database backed up"
            fi
        fi
    else
        echo "MySQL is not installed on this system or the password is incorrect, skipping database backup"
    fi

    # Add a backup script for the database in the /ccdc/scripts/linux directory
    cat <<'EOF' > $SCRIPT_DIR/linux/mysql_backup.sh
#!/bin/bash
if [[ $EUID -ne 0 ]]
then
  printf 'Must be run as root, exiting!\n'
  exit 1
fi

# Check if the system is running prestashop and get the MySQL root password
if [ ! -d /var/www/html/prestashop ]; then
    echo "Prestashop is not installed on this system"
    exit 1
fi
CORRECT_PASS="random_text"
while ([ ! -z "$CORRECT_PASS" ]) && [ $ATTEMPTS -le 2 ]; do
    # Get the MySQL root password
    read -p "Enter the MySQL root password: " -s MYSQL_ROOT_PASSWORD

    # Check if the password is correct, it also may be blank
    if [ -z "$MYSQL_ROOT_PASSWORD" ]; then
        CORRECT_PASS=$(mysql -u root -e "exit" 2>/dev/stdout)
    else
        CORRECT_PASS=$(mysql -u root -p$MYSQL_ROOT_PASSWORD -e "exit" 2>/dev/stdout)
    fi
    ATTEMPTS=$((ATTEMPTS+1))
done

if [ ! -z "$CORRECT_PASS" ]; then
    echo "Could not connect to MySQL please run the scripts for mysql manually"
    exit 1
fi

# backup the mysql database save it in /bkp/new/ and give it a timestamp in the name
if [ -z "$MYSQL_ROOT_PASSWORD" ]; then
    mysqldump -u root --all-databases > /bkp/new/ecomm-$(date +%s).sql
else
    mysqldump -u root -p$MYSQL_ROOT_PASSWORD --all-databases > /bkp/new/ecomm-$(date +%s).sql
fi
EOF
    chmod +x $SCRIPT_DIR/linux/mysql_backup.sh

    # Add a script to restore the database
    cat <<'EOF' > $SCRIPT_DIR/linux/mysql_restore.sh
#!/bin/bash
if [[ $EUID -ne 0 ]]
then
  printf 'Must be run as root, exiting!\n'
  exit 1
fi

# Check if the system is running prestashop and get the MySQL root password
if [ ! -d /var/www/html/prestashop ]; then
    echo "Prestashop is not installed on this system"
    exit 1
fi
CORRECT_PASS="random_text"
while ([ ! -z "$CORRECT_PASS" ]) && [ $ATTEMPTS -le 2 ]; do
    # Get the MySQL root password
    read -p "Enter the MySQL root password: " -s MYSQL_ROOT_PASSWORD

    # Check if the password is correct, it also may be blank
    if [ -z "$MYSQL_ROOT_PASSWORD" ]; then
        CORRECT_PASS=$(mysql -u root -e "exit" 2>/dev/stdout)
    else
        CORRECT_PASS=$(mysql -u root -p$MYSQL_ROOT_PASSWORD -e "exit" 2>/dev/stdout)
    fi
    ATTEMPTS=$((ATTEMPTS+1))
done

if [ ! -z "$CORRECT_PASS" ]; then
    echo "Could not connect to MySQL please run the scripts for mysql manually"
    exit 1
fi

# restore the mysql database
if [ -z "$MYSQL_ROOT_PASSWORD" ]; then
    mysql -u root < /bkp/original/ecomm.sql
else
    mysql -u root -p$MYSQL_ROOT_PASSWORD < /bkp/original/ecomm.sql
fi
EOF
    chmod +x $SCRIPT_DIR/linux/mysql_restore.sh


    if [ $PRESTASHOP == "true" ]; then
        # Remove prestashop admin directory
        ls /var/www/html/prestashop | grep admin > ~/adminPanel.txt
        rm -rf /var/www/html/prestashop/admin*

        # Remove the unneeded directories from prestashop
        rm -rf /var/www/html/prestashop/install*
        rm -rf /var/www/html/prestashop/docs
        rm -f /var/www/html/prestashop/README.md

        rm -f /var/www/html/prestashop/CONTRIBUTING.md
        rm -f /var/www/html/prestashop/CONTRIBUTORS.md
        rm -f /var/www/html/prestashop/init.php

        rm -f /var/www/html/prestashop/INSTALL.txt
        rm -f /var/www/html/prestashop/Install_PrestaShop.html
        rm -f /var/www/html/prestashop/LICENSES
        rm -f /var/www/html/prestashop/XMLFeed.cache

        # remove index.php from /upload and /download directories
        rm -f /var/www/html/prestashop/upload/index.php
        rm -f /var/www/html/prestashop/download/index.php

        # remove more unneeded files, such as the composer.lock files
        rm -f /var/www/html/prestashop/composer.lock
        rm -f /var/www/html/prestashop/Makefile
        rm -f /var/www/html/prestashop/phpstan.neon.dist

        sendLog "Prestashop unneeded files removed"
    fi

    # Get the apache config file
    if [ -d "/etc/httpd" ]; then
        APACHE_CONFIG="/etc/httpd/conf/httpd.conf"
    elif [ -d "/etc/apache2" ]; then
        APACHE_CONFIG="/etc/apache2/apache2.conf"
    fi

    # check if the /var/www/html/prestashop/config directory exists, if it does then add a section to disable it if it does not already exist in the apache config
    if [ -d "/var/www/html/prestashop/config" ]; then
        if [ "$(grep -iq 'RedirectMatch 404 ^/prestashop/config' $APACHE_CONFIG)" ]; then
            echo "Adding configuration to disable access to the config directory..."
            echo "RedirectMatch 404 ^/prestashop/config" >> $APACHE_CONFIG
            sendLog "Prestashop config directory disabled"
        fi
    fi

    # check if the /var/www/html/prestashop/app directory exists, if it does then add a section to disable it if it does not already exist in the apache config
    if [ -d "/var/www/html/prestashop/app" ]; then
        if [ "$(grep -iq 'RedirectMatch 404 ^/prestashop/app' $APACHE_CONFIG)" ]; then
            echo "Adding configuration to disable access to the app directory..."
            echo "RedirectMatch 404 ^/prestashop/app" >> $APACHE_CONFIG
            sendLog "Prestashop app directory disabled"
        fi
    fi

    # check if the /var/www/html/prestashop/var directory exists, if it does then add a section to disable it if it does not already exist in the apache config
    if [ -d "/var/www/html/prestashop/var" ]; then
        if [ "$(grep -iq 'RedirectMatch 404 ^/prestashop/var' $APACHE_CONFIG)" ]; then
            echo "Adding configuration to disable access to the var directory..."
            echo "RedirectMatch 404 ^/prestashop/var" >> $APACHE_CONFIG
            sendLog "Prestashop var directory disabled"
        fi
    fi

    # check if the /var/www/html/prestashop/translations directory exists, if it does then add a section to disable it if it does not already exist in the apache config
    if [ -d "/var/www/html/prestashop/translations" ]; then
        if [ "$(grep -iq 'RedirectMatch 404 ^/prestashop/translations' $APACHE_CONFIG)" ]; then
            echo "Adding configuration to disable access to the translations directory..."
            echo "RedirectMatch 404 ^/prestashop/translations" >> $APACHE_CONFIG
            sendLog "Prestashop translations directory disabled"
        fi
    fi

    # check if the /var/www/html/prestashop/cache directory exists, if it does then add a section to disable it if it does not already exist in the apache config
    if [ -d "/var/www/html/prestashop/cache" ]; then
        if [ "$(grep -iq 'RedirectMatch 404 ^/prestashop/cache' $APACHE_CONFIG)" ]; then
            echo "Adding configuration to disable access to the cache directory..."
            echo "RedirectMatch 404 ^/prestashop/cache" >> $APACHE_CONFIG
            sendLog "Prestashop cache directory disabled"
        fi
    fi

    # check if the /var/www/html/prestashop/src directory exists, if it does then add a section to disable it if it does not already exist in the apache config
    if [ -d "/var/www/html/prestashop/src" ]; then
        if [ "$(grep -iq 'RedirectMatch 404 ^/prestashop/src' $APACHE_CONFIG)" ]; then
            echo "Adding configuration to disable access to the src directory..."
            echo "RedirectMatch 404 ^/prestashop/src" >> $APACHE_CONFIG
            sendLog "Prestashop src directory disabled"
        fi
    fi

    # check if the /var/www/html/prestashop/vendor directory exists, if it does then add a section to disable it if it does not already exist in the apache config
    if [ -d "/var/www/html/prestashop/vendor" ]; then
        if [ "$(grep -iq 'RedirectMatch 404 ^/prestashop/vendor' $APACHE_CONFIG)" ]; then
            echo "Adding configuration to disable access to the vendor directory..."
            echo "RedirectMatch 404 ^/prestashop/vendor" >> $APACHE_CONFIG
            sendLog "Prestashop vendor directory disabled"
        fi
    fi

    # check if the /var/www/html/prestashop/install directory exists, if it does then add a section to disable it if it does not already exist in the apache config
    if [ -d "/var/www/html/prestashop/install" ]; then
        if [ "$(grep -iq 'RedirectMatch 404 ^/prestashop/install' $APACHE_CONFIG)" ]; then
            echo "Adding configuration to disable access to the install directory..."
            echo "RedirectMatch 404 ^/prestashop/install" >> $APACHE_CONFIG
            sendLog "Prestashop install directory disabled"
        fi
    fi

    # check if the /var/www/html/prestashop/mails directory exists, if it does then add a section to disable it if it does not already exist in the apache config
    if [ -d "/var/www/html/prestashop/mails" ]; then
        if [ "$(grep -iq 'RedirectMatch 404 ^/prestashop/mails' $APACHE_CONFIG)" ]; then
            echo "Adding configuration to disable access to the mails directory..."
            echo "RedirectMatch 404 ^/prestashop/mails" >> $APACHE_CONFIG
            sendLog "Prestashop mails directory disabled"
        fi
    fi

    # check if the /var/www/html/prestashop/pdf directory exists, if it does then add a section to disable it if it does not already exist in the apache config
    if [ -d "/var/www/html/prestashop/pdf" ]; then
        if [ "$(grep -iq 'RedirectMatch 404 ^/prestashop/pdf' $APACHE_CONFIG)" ]; then
            echo "Adding configuration to disable access to the pdf directory..."
            echo "RedirectMatch 404 ^/prestashop/pdf" >> $APACHE_CONFIG
            sendLog "Prestashop pdf directory disabled"
        fi
    fi

    # check if the /var/www/html/prestashop/log directory exists, if it does then add a section to disable it if it does not already exist in the apache config
    if [ -d "/var/www/html/prestashop/log" ]; then
        if [ "$(grep -iq 'RedirectMatch 404 ^/prestashop/log' $APACHE_CONFIG)" ]; then
            echo "Adding configuration to disable access to the log directory..."
            echo "RedirectMatch 404 ^/prestashop/log" >> $APACHE_CONFIG
            sendLog "Prestashop log directory disabled"
        fi
    fi

    # check if the /var/www/html/prestashop/controllers directory exists, if it does then add a section to disable it if it does not already exist in the apache config
    if [ -d "/var/www/html/prestashop/controllers" ]; then
        if [ "$(grep -iq 'RedirectMatch 404 ^/prestashop/controllers' $APACHE_CONFIG)" ]; then
            echo "Adding configuration to disable access to the controllers directory..."
            echo "RedirectMatch 404 ^/prestashop/controllers" >> $APACHE_CONFIG
            sendLog "Prestashop controllers directory disabled"
        fi
    fi

    # check if the /var/www/html/prestashop/classes directory exists, if it does then add a section to disable it if it does not already exist in the apache config
    if [ -d "/var/www/html/prestashop/classes" ]; then
        if [ "$(grep -iq 'RedirectMatch 404 ^/prestashop/classes' $APACHE_CONFIG)" ]; then
            echo "Adding configuration to disable access to the classes directory..."
            echo "RedirectMatch 404 ^/prestashop/classes" >> $APACHE_CONFIG
            sendLog "Prestashop classes directory disabled"
        fi
    fi

    # check if the /var/www/html/prestashop/override directory exists, if it does then add a section to disable it if it does not already exist in the apache config
    if [ -d "/var/www/html/prestashop/override" ]; then
        if [ "$(grep -iq 'RedirectMatch 404 ^/prestashop/override' $APACHE_CONFIG)" ]; then
            echo "Adding configuration to disable access to the override directory..."
            echo "RedirectMatch 404 ^/prestashop/override" >> $APACHE_CONFIG
            sendLog "Prestashop override directory disabled"
        fi
    fi

    # check if the /var/www/html/prestashop/img directory exists, if it does then add a section to disable 
    if [ -d "/var/www/html/prestashop/img" ]; then
        if [ "$(grep -iq '<Directory /var/www/html/prestashop/img>' $APACHE_CONFIG)" ]; then
            echo "Adding configuration to disable access to the img directory..."
            cat <<EOF >> $APACHE_CONFIG
<Directory /var/www/html/prestashop/img>
    <FilesMatch "\.(jpg|jpeg|png|gif|svg|webp|ico)$">
        Order allow,deny
        Allow from all
    </FilesMatch>
    <FilesMatch "\.php$">
        Deny from all
    </FilesMatch>
    php_admin_flag engine off
</Directory>
EOF
            sendLog "Only images can be accessed in the img directory"
        fi

    fi

    # Prevent access to sensitive files
    if [ "$(grep -iq '<FilesMatch "\.(env|ini|log|bak|swp|sql|git)">' $APACHE_CONFIG)" ]; then
        echo "Adding configuration to disable access to sensitive files..."
        cat <<EOF >> $APACHE_CONFIG
<FilesMatch "\.(env|ini|log|bak|swp|sql|git)">
    Order Allow,Deny
    Deny from all
</FilesMatch>
<FilesMatch "^(settings.inc.php|config.inc.php|parameters.php|parameters.yml)$">
    Order deny,allow
    Deny from all
</FilesMatch>
<FilesMatch "\.(sql|tpl|twig|md|yml|yaml|log|ini|sh|bak|inc)$">
    Order deny,allow
    Deny from all
</FilesMatch>
EOF
        sendLog "Access to sensitive files disabled"
    fi


    # disable the php engine in the /var/www/html/prestashop/upload directory and download directory
    if [ -d "/var/www/html/prestashop/upload" ]; then
        if [ "$(grep -iq '<Directory /var/www/html/prestashop/upload>' $APACHE_CONFIG)" ]; then
            echo "Adding configuration to disable the php engine in the upload directory..."
            cat <<EOF >> $APACHE_CONFIG
<Directory /var/www/html/prestashop/upload>
    php_admin_flag engine off
</Directory>
EOF
            sendLog "PHP engine disabled in the upload directory"
        fi
    fi

    if [ -d "/var/www/html/prestashop/download" ]; then
        if [ "$(grep -iq '<Directory /var/www/html/prestashop/download>' $APACHE_CONFIG)" ]; then
            echo "Adding configuration to disable the php engine in the download directory..."
            cat <<EOF >> $APACHE_CONFIG
<Directory /var/www/html/prestashop/download>
    php_admin_flag engine off
</Directory>
EOF
            sendLog "PHP engine disabled in the download directory"
        fi
    fi


    # Disable directory listing check if it might say Options Indexes FollowSymLinks in the apache config and change it to Options -Indexes
    if [ -z "$(grep -i '^[^#]*Options -Indexes +FollowSymLinks' $APACHE_CONFIG)" ]; then
        echo "Adding configuration to disable directory listing..."
        sed -i 's/^\([[:space:]]*Options\)[[:space:]]Indexes[[:space:]]FollowSymLinks/\1 -Indexes +FollowSymLinks/g' $APACHE_CONFIG
        sendLog "Directory listing disabled"
    fi

    # Disable TRACK and TRACE methods
    if [ "$(grep -iq 'TraceEnable off' $APACHE_CONFIG)" ]; then
        echo "Adding configuration to disable TRACK and TRACE methods..."
        echo "TraceEnable off" >> $APACHE_CONFIG
        sendLog "TRACK and TRACE methods disabled"
    fi


    # dont allow access to any file with .class.php or .inc.php
    if [ "$(grep -iq 'RedirectMatch 404 ^/prestashop/(.*\.class\.php|.*\.inc\.php)$' $APACHE_CONFIG)" ]; then
        echo "Adding configuration to disable access to .class.php and .inc.php files..."
        echo "RedirectMatch 404 ^/prestashop/(.*\.class\.php|.*\.inc\.php)$" >> $APACHE_CONFIG
        sendLog "Access to .class.php and .inc.php files disabled"
    fi

    # dont allow access to any file in the /phpmyadmin directory
    if [ "$(grep -iq 'RedirectMatch 404 ^/prestashop/phpmyadmin' $APACHE_CONFIG)" ]; then
        echo "Adding configuration to disable access to the phpmyadmin directory..."
        echo "RedirectMatch 404 ^/prestashop/phpmyadmin" >> $APACHE_CONFIG
        sendLog "Access to phpmyadmin directory disabled"
    fi


    # find the configuration file
    PHP_CONF=$(php -i | grep 'Loaded Configuration File' | cut -d' ' -f5)
    sendLog "PHP configuration file found at $PHP_CONF"

    # check if expose_php is set to off in the php.ini file
    if [ -z "$(grep -i 'expose_php = Off' $PHP_CONF)" ]; then
        echo "Adding configuration to disable expose_php..."
        sed -i 's/^\([[:space:]]*expose_php\)[[:space:]]*=.*/\1 = Off/g' $PHP_CONF
        sendLog "expose_php disabled"
    fi

    # disable allow_url_fopen in the php.ini file
    if [ -z "$(grep -i 'allow_url_fopen = Off' $PHP_CONF)" ]; then
        echo "Adding configuration to disable allow_url_fopen..."
        sed -i 's/^\([[:space:]]*allow_url_fopen\)[[:space:]]*=.*/\1 = Off/g' $PHP_CONF
        sendLog "allow_url_fopen disabled"
    fi

    # Add a script to change the user prestashop uses to connect to the database
    cat <<'EOF' > $SCRIPT_DIR/linux/change_db_user.sh
#!/bin/bash

# Variables
MYSQL_ROOT_USER="root"         # MySQL root username
PRESTASHOP_DIR="/var/www/html/prestashop"  # Path to your PrestaShop installation

# Check if MYSQL_ROOT_PASS is passed as an argument or if we need to ask for it
if [ -z "$1" ]; then
    # If no password argument is provided, try to use passwordless login
    MYSQL_COMMAND="mysql -u $MYSQL_ROOT_USER"

    # Test if passwordless login is available by running a simple query
    if ! $MYSQL_COMMAND -e "exit" > /dev/null 2>&1; then
        # If passwordless login fails, prompt for MySQL root password
        read -sp "Enter MySQL root password: " MYSQL_ROOT_PASS
        echo
        MYSQL_COMMAND="mysql -u $MYSQL_ROOT_USER -p$MYSQL_ROOT_PASS"
    fi
else
    # If an argument is passed, use it as the MySQL root password
    MYSQL_ROOT_PASS="$1"
    MYSQL_COMMAND="mysql -u $MYSQL_ROOT_USER -p$MYSQL_ROOT_PASS"
fi

# Read the current PrestaShop database name from the configuration file, there are two possible locations, and they have different formats
# The database name can be found in the configuration file located in /var/www/html/prestashop/config/settings.inc.php, or in /var/www/html/prestashop/app/config/parameters.php
# The database name will look like this define('_DB_NAME_', 'prestashop'); or 'database_name' => 'prestashop',
# Extract the database name from the define statement
if [ -f "$PRESTASHOP_DIR/config/settings.inc.php" ]; then
    PHP_FILE="$PRESTASHOP_DIR/config/settings.inc.php"
    CURRENT_DB_NAME=$(grep -oP "define\('_DB_NAME_', '\K[^']+" "$PHP_FILE")
elif [ -f "$PRESTASHOP_DIR/app/config/parameters.php" ]; then
    PHP_FILE="$PRESTASHOP_DIR/app/config/parameters.php"
    CURRENT_DB_NAME=$(grep -oP "'database_name' => '\K[^']+" "$PHP_FILE")
else
    echo "PrestaShop configuration file not found."
    exit 1
fi

# If no database name is found in the configuration file, ask the user for the database name
if [ -z "$CURRENT_DB_NAME" ]; then
    echo "No database name found in the configuration file."
    read -p "Please enter the PrestaShop database name: " CURRENT_DB_NAME
fi

# Generate random password for the new MySQL user
NEW_USER="ps_user_$(openssl rand -hex 4)"
NEW_PASS=$(openssl rand -base64 64)

# Fileter out special characters from the password
NEW_PASS=$(echo "$NEW_PASS" | tr -cd '[:alnum:]')

# Create new MySQL user with random password and grant necessary permissions
echo "Creating MySQL user and granting permissions..."
$MYSQL_COMMAND -e "
CREATE USER '$NEW_USER'@'localhost' IDENTIFIED BY '$NEW_PASS';
GRANT SELECT, INSERT, UPDATE, DELETE, CREATE, DROP, ALTER ON $CURRENT_DB_NAME.* TO '$NEW_USER'@'localhost';
FLUSH PRIVILEGES;
"

# Test the new user
echo "Testing new MySQL user..."
$MYSQL_COMMAND -e "exit" -u $NEW_USER -p$NEW_PASS
if [ $? -ne 0 ]; then
    echo "Failed to create or test new MySQL user."
    exit 1
fi

# Update the PrestaShop configuration file with the new database user and password
echo "Updating PrestaShop configuration file with the new database user and password..."
if [ -f "$PRESTASHOP_DIR/config/settings.inc.php" ]; then
    sed -i "s/define('_DB_USER_', '.*');/define('_DB_USER_', '$NEW_USER');/" "$PHP_FILE"
    sed -i "s/define('_DB_PASSWD_', '.*');/define('_DB_PASSWD_', '$NEW_PASS');/" "$PHP_FILE"
elif [ -f "$PRESTASHOP_DIR/app/config/parameters.php" ]; then
    sed -i "s/'database_user' => '.*',/'database_user' => '$NEW_USER',/" "$PHP_FILE"
    sed -i "s/'database_password' => '.*',/'database_password' => '$NEW_PASS',/" "$PHP_FILE"
fi

echo "PrestaShop database user updated successfully."
EOF
        chmod +x $SCRIPT_DIR/linux/change_db_user.sh

    if [ $MYSQL == "true" ]; then
        # Create a new database user for prestashop
        bash $SCRIPT_DIR/linux/change_db_user.sh $MYSQL_ROOT_PASSWORD
        sendLog "Prestashop database user created, and configuration updated"

        # disable smarty cache in the prestashop configuration table
        # first get the db prefix from the two possible locations
        if [ -f "/var/www/html/prestashop/config/settings.inc.php" ]; then
            DB_PREFIX=$(grep -oP "define\('_DB_PREFIX_', '\K[^']+" /var/www/html/prestashop/config/settings.inc.php)
        elif [ -f "/var/www/html/prestashop/app/config/parameters.php" ]; then
            DB_PREFIX=$(grep -oP "'database_prefix' => '\K[^']+" /var/www/html/prestashop/app/config/parameters.php)
        fi

        # Ensure DB_PREFIX is set, default to 'ps_' if missing
        DB_PREFIX=${DB_PREFIX:-ps_}

        # check if the db prefix is set
        if [ -z "$DB_PREFIX" ]; then
            echo "Could not find the database prefix in the configuration file"
        else
            # update the smarty cache in the database
            if [ -z "$MYSQL_ROOT_PASSWORD" ]; then
                mysql -u root -e "UPDATE ${DB_PREFIX}configuration SET value='0' WHERE name='PS_SMARTY_CACHE';"
            else
                mysql -u root -p$MYSQL_ROOT_PASSWORD -e "UPDATE ${DB_PREFIX}configuration SET value='0' WHERE name='PS_SMARTY_CACHE';"
            fi
            echo "Smarty cache disabled in the database"
            sendLog "Smarty cache disabled in the database"
        fi
    fi

    # fix permissions on the /var/www/html/prestashop directory
    TARGET_DIR="/var/www/html/prestashop"
    # Set directories to 755
    find "$TARGET_DIR" -type d -exec chmod 755 {} \;
    # Set files to 644
    find "$TARGET_DIR" -type f -exec chmod 644 {} \;
    echo "Permissions set: Directories (755), Files (644) in $TARGET_DIR"
    sendLog "Permissions set: Directories (755), Files (644) in $TARGET_DIR"


    # restart apache
    systemctl restart apache2
    systemctl restart httpd
    sendLog "Apache restarted"

    #TODO: Ensure that the backup does not already exist
    # Create backups of the new changes
    if [ ! -d "/bkp/new" ]; then
        mkdir -p /bkp/new
    fi

    # Zip up the /var/www/html directory and move it to /bkp
    echo "Zipping up /var/www/html..."
    tar -czf /bkp/new/html.tar.gz /var/www/html
    sendLog "Prestashop directory backed up"

    # zip up the apache config directory and move it to /bkp
    if [ -d "/etc/httpd" ]; then
        echo "Zipping up /etc/httpd..."
        tar -czf /bkp/new/httpd.tar.gz /etc/httpd
        sendLog "Apache config backed up"
    elif [ -d "/etc/apache2" ]; then
        echo "Zipping up /etc/apache2..."
        tar -czf /bkp/new/apache2.tar.gz /etc/apache2
        sendLog "Apache config backed up"
    fi

    if [ "$MYSQL" == "true" ]; then
        # backup the mysql database
        if [ -z "$MYSQL_ROOT_PASSWORD" ]; then
            mysqldump -u root --all-databases > /bkp/new/ecomm.sql
        else
            mysqldump -u root -p$MYSQL_ROOT_PASSWORD --all-databases > /bkp/new/ecomm.sql
        fi
        sendLog "MySQL database backed up"
    fi

    # copy the backup folder to random location
    BKP_DIR="/etc/$(openssl rand -hex 4)"
    mkdir -p /etc/$BKP_DIR
    cp -r /bkp /etc/$BKP_DIR
    sendLog "Backup copied to $BKP_DIR"
}

cronjail() {
    #////////////////////////////////////////
    # cronjail
    #////////////////////////////////////////
    # We will move all cron jobs to a jail directory so they can be reviewed before being re-enabled
    # Check if the cron jail directory exists, if it does not, create it
    if [ ! -d "$CCDC_ETC/cron.jail" ]; then
        mkdir -p $CCDC_ETC/cron.jail
    fi

    # Move all cron jobs to the jail directory in a folder indicating where they came from
    if [ -f "/etc/cron.deny" ]; then
        mv /etc/cron.deny $CCDC_ETC/cron.jail
        cat /dev/null > /etc/cron.deny
        sendLog "cron.deny moved to $CCDC_ETC/cron.jail"
    fi

    # if there is a cron.deny.rpmsave file, copy it to the jail directory, and rename it to cron.deny
    if [ -f "/etc/cron.deny.rpmsave" ]; then
        cp /etc/cron.deny.rpmsave $CCDC_ETC/cron.jail
        cat /dev/null > /etc/cron.deny.rpmsave
        mv /etc/cron.deny.rpmsave /etc/cron.deny
        sendLog "cron.deny.rpmsave moved to $CCDC_ETC/cron.jail"
    fi

    if [ -f "/etc/cron.allow" ]; then
        mv /etc/cron.allow $CCDC_ETC/cron.jail
        cat /dev/null > /etc/cron.allow
        sendLog "cron.allow moved to $CCDC_ETC/cron.jail"
    fi

    if [ -f "/etc/crontab" ]; then
        mv /etc/crontab $CCDC_ETC/cron.jail
        cat /dev/null > /etc/crontab
        sendLog "crontab moved to $CCDC_ETC/cron.jail"
    fi

    if [ -d "/etc/cron.d" ] && [ "$(ls -A /etc/cron.d)" ]; then
        mkdir -p $CCDC_ETC/cron.jail/cron.d
        mv /etc/cron.d/* $CCDC_ETC/cron.jail/cron.d
        sendLog "cron.d moved to $CCDC_ETC/cron.jail"
    fi

    if [ -d "/etc/cron.daily" ] && [ "$(ls -A /etc/cron.daily)" ]; then
        mkdir -p $CCDC_ETC/cron.jail/daily
        mv /etc/cron.daily/* $CCDC_ETC/cron.jail/daily
        sendLog "cron.daily moved to $CCDC_ETC/cron.jail"
    fi

    if [ -d "/etc/cron.hourly" ] && [ "$(ls -A /etc/cron.hourly)" ]; then
        mkdir -p $CCDC_ETC/cron.jail/hourly
        mv /etc/cron.hourly/* $CCDC_ETC/cron.jail/hourly
        sendLog "cron.hourly moved to $CCDC_ETC/cron.jail"
    fi

    if [ -d "/etc/cron.monthly" ] && [ "$(ls -A /etc/cron.monthly)" ]; then
        mkdir -p $CCDC_ETC/cron.jail/monthly
        mv /etc/cron.monthly/* $CCDC_ETC/cron.jail/monthly
        sendLog "cron.monthly moved to $CCDC_ETC/cron.jail"
    fi

    if [ -d "/etc/cron.weekly" ] && [ "$(ls -A /etc/cron.weekly)" ]; then
        mkdir -p $CCDC_ETC/cron.jail/weekly
        mv /etc/cron.weekly/* $CCDC_ETC/cron.jail/weekly
        sendLog "cron.weekly moved to $CCDC_ETC/cron.jail"
    fi

    if [ -d "/var/spool/cron" ] && [ "$(ls -A /var/spool/cron)" ]; then
        mkdir -p $CCDC_ETC/cron.jail/spool
        mv /var/spool/cron/* $CCDC_ETC/cron.jail/spool
        sendLog "cron spool moved to $CCDC_ETC/cron.jail"
    fi

    if [ -d "/var/spool/at" ] && [ "$(ls -A /var/spool/at)" ]; then
        mkdir -p $CCDC_ETC/cron.jail/at
        mv /var/spool/at/* $CCDC_ETC/cron.jail/at
        sendLog "at spool moved to $CCDC_ETC/cron.jail"
    fi

    if [ -d "/var/spool/atjobs" ] && [ "$(ls -A /var/spool/atjobs)" ]; then
        mkdir -p $CCDC_ETC/cron.jail/atjobs
        mv /var/spool/atjobs/* $CCDC_ETC/cron.jail/atjobs
        sendLog "atjobs spool moved to $CCDC_ETC/cron.jail"
    fi

    # Restart the cron service
    systemctl restart crond
    systemctl restart cron
    # Restart the atd service
    systemctl restart atd
    sendLog "Cron and atd services restarted"
}

modsecurity() {
    #////////////////////////////////////////
    # ModSecurity
    #////////////////////////////////////////
    # Check if apache is installed
    if [ ! -z "$(which apache2)" ] && [ ! -z "$(which httpd)" ]; then
        echo "Apache is not installed on this system, skipping modsecurity installation"
        return
    fi

    # Install modsecurity
    if [ ! -z "$(which yum)" ]; then
        yum install mod_security mod_evasive -y
        a2enmod headers
        sendLog "ModSecurity installed"
    elif [ ! -z "$(which apt-get)" ]; then
        apt-get install libapache2-mod-security2 libapache2-mod-evasive -y
        a2enmod headers
        sendLog "ModSecurity installed"
    elif [ ! -z "$(which dnf)" ]; then
        dnf install mod_security mod_evasive -y
        a2enmod headers
        sendLog "ModSecurity installed"
    fi

    # Configure modsecurity
    if [ ! -f "/etc/modsecurity/modsecurity.conf" ]; then
        cp /etc/modsecurity/modsecurity.conf{-recommended,}
        sendLog "ModSecurity configuration file created"
    fi
    
    sed -i "s/SecRuleEngine DetectionOnly/SecRuleEngine On/g" /etc/modsecurity/modsecurity.conf
    sed -i "s/SecRequestBodyAccess On/SecRequestBodyAccess Off/g" /etc/modsecurity/modsecurity.conf

    if [ -f "/etc/apache2/apache2.conf" ]; then
        sed -i "s/IncludeOptional modsecurity.d\/\*.conf/IncludeOptional modsecurity.d\/\*.conf/g" /etc/apache2/apache2.conf
    elif [ -f "/etc/httpd/conf/httpd.conf" ]; then
        sed -i "s/IncludeOptional modsecurity.d\/\*.conf/IncludeOptional modsecurity.d\/\*.conf/g" /etc/httpd/conf/httpd.conf
    fi

    # mkdir /var/log/apache2/mod_evasive && chmod 777 /var/log/apache2/mod_evasive

    # Restart apache
    systemctl restart apache2
    systemctl restart httpd
    sendLog "Apache restarted"
}

legalese() {
    #////////////////////////////////////////
    # legalese
    #////////////////////////////////////////
    # add a legalese to the /etc/motd file\
    cat <<EOF > /etc/motd
UNAUTHORIZED ACCESS TO THIS DEVICE IS PROHIBITED

You must have explicit, authorized permission to access or configure this device.
Unauthorized attempts and actions to access or use this system may result in civil
and/or criminal penalties.

All activities performed on this device are logged and monitored.
EOF
    sendLog "Legalese added to /etc/motd"

    # add a legalese to the /etc/issue file
    cat <<EOF > /etc/issue
UNAUTHORIZED ACCESS TO THIS DEVICE IS PROHIBITED

You must have explicit, authorized permission to access or configure this device.
Unauthorized attempts and actions to access or use this system may result in civil
and/or criminal penalties.

All activities performed on this device are logged and monitored.
EOF
    sendLog "Legalese added to /etc/issue"

    # add a legalese to the /etc/issue.net file
    cat <<EOF > /etc/issue.net
UNAUTHORIZED ACCESS TO THIS DEVICE IS PROHIBITED

You must have explicit, authorized permission to access or configure this device.
Unauthorized attempts and actions to access or use this system may result in civil
and/or criminal penalties.

All activities performed on this device are logged and monitored.
EOF
    sendLog "Legalese added to /etc/issue.net"
}

harden() {
    # Disable prelinking altogether for aide
    #
    if grep -q ^PRELINKING /etc/sysconfig/prelink
    then
        sed -i 's/PRELINKING.*/PRELINKING=no/g' /etc/sysconfig/prelink
        sendLog "Prelinking disabled"
    else
        echo -e "\n# Set PRELINKING=no per security requirements" >> /etc/sysconfig/prelink
        echo "PRELINKING=no" >> /etc/sysconfig/prelink
        sendLog "Prelinking disabled"
    fi

    # Set Last Login/Access Notification
    if grep -q pam_lastlog.so /etc/pam.d/system-auth
    then
        echo "pam_lastlog.so already in system-auth"
    else
        echo "Adding pam_lastlog.so to system-auth..."
        sed -i '/pam_limits.so/a session required pam_lastlog.so showfailed' /etc/pam.d/system-auth
        sendLog "Last login/access notification added"
    fi

    # Disable Ctrl-Alt-Del Reboot Activation
    if grep -q "exec /usr/bin/logger -p security.info" /etc/init/control-alt-delete.conf
    then
        echo "Control-Alt-Delete already disabled"
    else
        echo "Disabling Control-Alt-Delete..."
        sed -i 's/exec \/sbin\/shutdown -r now "Control-Alt-Delete pressed"/exec \/usr\/bin\/logger -p security.info "Control-Alt-Delete pressed"/g' /etc/init/control-alt-delete.conf
        sendLog "Control-Alt-Delete disabled"
    fi

    # secure grub by ensuring the permissions are set to 600
    if [ -f /boot/grub2/grub.cfg ]; then
        chmod 600 /boot/grub2/grub.cfg
        sendLog "Grub permissions set to 600"
    elif [ -f /boot/grub/grub.cfg ]; then
        chmod 600 /boot/grub/grub.cfg
        sendLog "Grub permissions set to 600"
    fi

    # ensure SELinux is enabled, and in enforcing mode
    if grep -q SELINUX=enforcing /etc/selinux/config
    then
        echo "SELINUX already set to enforcing"
    else
        echo "Setting SELINUX to enforcing..."
        sed -i 's/SELINUX=disabled/SELINUX=enforcing/g' /etc/selinux/config
        if [ $APACHE == "true" ]; then
            chcon -R -t httpd_sys_rw_content_t /var/www/html/prestashop
            sendLog "httpd_sys_rw_content_t set on /var/www/html/prestashop"
        fi
        sendLog "SELinux set to enforcing"
    fi

    # Disable support for RPC IPv6
    if grep -q "udp6" /etc/netconfig
    then
        echo "Support for RPC IPv6 already disabled"
    else
        echo "Disabling Support for RPC IPv6..."
        sed -i 's/udp6       tpi_clts      v     inet6    udp     -       -/#udp6       tpi_clts      v     inet6    udp     -       -/g' /etc/netconfig
        sed -i 's/tcp6       tpi_cots_ord  v     inet6    tcp     -       -/#tcp6       tpi_cots_ord  v     inet6    tcp     -       -/g' /etc/netconfig
        sendLog "Support for RPC IPv6 disabled"
    fi

    # Only allow root to login from console
    if grep -q "tty1" /etc/securetty
    then
        echo "Root already allowed to login from console"
    else
        echo "Allowing root to login from console..."
        echo "tty1" >> /etc/securetty
        sendLog "Root allowed to only login from console"
    fi

    # Set permissions on the /root directory
    chmod 700 /root
    sendLog "Permissions set on /root"

    # Enable UMASK 077
    if grep -q "UMASK 077" /etc/login.defs
    then
        echo "UMASK already set to 077"
    else
        echo "Setting UMASK to 077..."
        sed -i 's/UMASK.*022/UMASK 077/g' /etc/login.defs
        sendLog "UMASK set to 077"
    fi

    # Check if cron is installed
    if command -v cron >/dev/null 2>&1 || command -v crond >/dev/null 2>&1; then
        echo "Locking down Cron allow"
        touch /etc/cron.allow
        chmod 600 /etc/cron.allow
        echo "Locking down Cron deny"
        touch /etc/cron.deny
        chmod 600 /etc/cron.deny
        awk -F: '{print $1}' /etc/passwd | grep -v root > /etc/cron.deny
        chmod 600 /etc/crontab
        sendLog "Cron locked down"
    else
        echo "Cron is not installed."
    fi

    # Check if at is installed
    if command -v at >/dev/null 2>&1; then
        echo "Locking down AT allow"
        touch /etc/at.allow
        chmod 600 /etc/at.allow
        echo "Locking down AT deny"
        touch /etc/at.deny
        chmod 600 /etc/at.deny
        awk -F: '{print $1}' /etc/passwd | grep -v root > /etc/at.deny
        sendLog "AT locked down"
    else
        echo "AT is not installed."
    fi
    
    # Enable kernel hardening
    cat <<-EOF > /etc/sysctl.conf
net.ipv4.ip_forward = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
net.ipv4.tcp_max_syn_backlog = 1280
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.all.secure_redirects = 0
net.ipv4.conf.all.log_martians = 1
net.ipv4.conf.default.accept_source_route = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.default.secure_redirects = 0
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.icmp_ignore_bogus_error_responses = 1
net.ipv4.tcp_syncookies = 1
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
net.ipv4.tcp_timestamps = 0
net.ipv6.conf.default.accept_redirects = 0
net.ipv6.conf.all.accept_redirects = 0
net.ipv4.conf.default.log_martians = 1
net.core.bpf_jit_harden = 2
kernel.sysrq = 0
kernel.perf_event_paranoid = 3
kernel.kptr_restrict = 2
kernel.dmesg_restrict = 1
kernel.yama.ptrace_scope = 3
kernel.exec_shield = 1
kernel.randomize_va_space = 2
fs.suid_dumpable = 0
EOF
    sendLog "Kernel configurations made to /etc/sysctl.conf"

    # Deny all TCP Wrappers if enabled
    if [ -f /etc/hosts.deny ]; then
        echo "Deny all TCP Wrappers"
        echo "ALL: ALL" > /etc/hosts.deny
        sendLog "TCP Wrappers denied"
    else
        echo "TCP Wrappers not supported on this system"
    fi

    # Disable Uncommon Protocols
    echo "install dccp /bin/false" > /etc/modprobe.d/dccp.conf
    echo "install sctp /bin/false" > /etc/modprobe.d/sctp.conf
    echo "install rds /bin/false" > /etc/modprobe.d/rds.conf
    echo "install tipc /bin/false" > /etc/modprobe.d/tipc.conf
    sendLog "Uncommon Protocols disabled"
}

remove_unneeded_services() {
    # Remove unneeded services
    if [ "$OS_ID" == "centos" ]; then
        yum remove xinetd telnet-server rsh-server telnet rsh ypbind ypserv tftp-server cronie-anacron bind vsftpd dovecot squid net-snmpd postfix vim -y
        if [ "$APACHE" == "true" ]; then
            yum remove httpd-manual phpmyadmin -y
            sendLog "Apache docs and phpmyadmin removed"
        fi
    elif [ "$OS_ID" == "ubuntu" ]; then
        apt-get remove xinetd telnetd rsh-server telnet rsh ypbind ypserv tftpd-hpa cronie-anacron bind9 vsftpd dovecot-core squid net-snmpd postfix vim -y
        if [ "$APACHE" == "true" ]; then
            apt-get remove apache2-doc phpmyadmin -y
            sendLog "Apache docs and phpmyadmin removed"
        fi
    fi

    # Disable unneeded services and enable needed services
    systemctl disable --now xinetd
    systemctl disable --now rexec
    systemctl disable --now rsh
    systemctl disable --now rlogin
    systemctl disable --now ypbind
    systemctl disable --now tftp
    systemctl disable --now certmonger
    systemctl disable --now cgconfig
    systemctl disable --now cgred
    systemctl disable --now cpuspeed
    systemctl disable --now kdump
    systemctl disable --now mdmonitor
    systemctl disable --now messagebus
    systemctl disable --now netconsole
    systemctl disable --now ntpdate
    systemctl disable --now oddjobd
    systemctl disable --now portreserve
    systemctl disable --now qpidd
    systemctl disable --now quota_nld
    systemctl disable --now rdisc
    systemctl disable --now rhnsd
    systemctl disable --now rhsmcertd
    systemctl disable --now saslauthd
    systemctl disable --now smartd
    systemctl disable --now sysstat
    systemctl disable --now atd
    systemctl disable --now nfslock
    systemctl disable --now named
    systemctl disable --now dovecot
    systemctl disable --now squid
    systemctl disable --now snmpd
    systemctl disable --now postfix
    systemctl disable --now rpcgssd
    systemctl disable --now rpcsvcgssd
    systemctl disable --now rpcidmapd
    systemctl disable --now netfs
    systemctl disable --now nfs


    # Ensure some services are enabled
    systemctl enable irqbalance
    systemctl enable psacct
    systemctl enable crond
}

update_packages() {
    # Update all packages
    if [ "$OS_ID" == "centos" ]; then
        sendLog "Updating packages..."
        yum update -y
        sendLog "Packages updated"
    elif [ "$OS_ID" == "ubuntu" ]; then
        sendLog "Updating packages..."
        apt-get update -y
        apt-get upgrade -y
        sendLog "Packages updated"
    fi
}

ipv6_config() {
    if [ "$OS_ID" == "centos" ] && [ "$OS_VERSION_ID" == "7" ]; then
        # Get main interface name
        INTERFACE=$(ip route | grep default | awk '{print $5}')

        # Check if changes were already made to the network config file
        if grep -q "IPV6INIT=yes" /etc/sysconfig/network-scripts/ifcfg-$INTERFACE;
        then
            echo "Network config file already has IPv6 settings"
        else
            echo "Setting up IPv6..."
            echo "IPV6INIT=yes" >> /etc/sysconfig/network-scripts/ifcfg-$INTERFACE
            echo "IPV6ADDR=fd00:3::70/64" >> /etc/sysconfig/network-scripts/ifcfg-$INTERFACE
            echo "IPV6_DEFAULTGW=fd00:3::1" >> /etc/sysconfig/network-scripts/ifcfg-$INTERFACE
            systemctl restart network
            sendLog "IPv6 configured"
        fi
    elif [ "$OS_ID" == "ubuntu" ]; then
        echo "IPv6 is not supported on Ubuntu with this script"
        sendLog "IPv6 is not supported on Ubuntu with this script"
    else
        echo "IPv6 is not supported on this system with this script"
        sendLog "IPv6 is not supported on this system with this script"
    fi
}

install_packages() {
    # Install required packages

    if [ $(which yum ) ]; then
        yum install screen netcat aide clamav tmux lynis auditd epel-release dialog -y
        sendLog "Extra packages installed"
    elif [ $(which apt-get) ]; then
        apt-get install screen netcat aide clamav tmux lynis auditd dialog -y
        sendLog "Extra packages installed"
    elif [ $(which dnf) ]; then
        dnf install screen netcat aide clamav tmux lynis auditd dialog -y
        sendLog "Extra packages installed"
    fi
}

configure_and_init_aide() {
    # Set up AIDE
    echo "Initializing AIDE..."
    # add /var/www/html to the aide.conf file
    # Check if the changes have already been made
    if [ "$APACHE" == "true" ]; then
        if grep -q "/var/www/html" /etc/aide.conf
        then
            echo "/var/www/html already in aide.conf"
        else
            echo "/var/www/html CONTENT_EX" >> /etc/aide.conf
        fi
    fi

    # check if /ccdc is in the aide.conf file
    if grep -q "/ccdc" /etc/aide.conf
    then
        echo "/ccdc already in aide.conf"
    else
        echo "/ccdc CONTENT_EX" >> /etc/aide.conf
    fi

    # Initialize AIDE
    aide --init
    mv /var/lib/aide/aide.db.new.gz /var/lib/aide/aide.db.gz

    # Create a cron job to run AIDE hourly
    echo "0 * * * * /usr/sbin/aide --check" > /etc/cron.d/aide
}

initialize_clamav() {
    # Initialize ClamAV
    echo "Initializing ClamAV..."
    freshclam
}

initialize_auditd(){
    # Install and Configure Auditd
    systemctl enable auditd
    systemctl start auditd
    wget raw.githubusercontent.com/Neo23x0/auditd/refs/heads/master/audit.rules
    rm /etc/audit/rules.d/audit.rules
    mv audit.rules audit.rules /etc/audit/rules.d/
    # CHANGE VALUE TO RefuseManualStop=no
    if grep -q "RefuseManualStop=no" /usr/lib/systemd/system/auditd.service
    then
        echo "RefuseManualStop already set to no"
    else
        echo "Setting RefuseManualStop to no..."
        sed -i 's/RefuseManualStop=yes/RefuseManualStop=no/g' /usr/lib/systemd/system/auditd.service
    fi

    auditctl -R /etc/audit/rules.d/audit.rules
    systemctl restart auditd
    service auditd restart
    systemctl daemon-reload
}

install_additional_scripts() {
    # Install monitor script
    wget $BASEURL/linux/E-Comm/monitor.sh -O /ccdc/scripts/monitor.sh
    chmod +x /ccdc/scripts/linux/monitor.sh

    # Install apache_update script
    wget $BASEURL/linux/E-Comm/update_apache.sh -O /ccdc/scripts/update_apache.sh
    chmod +x /ccdc/scripts/linux/update_apache.sh
}

netconfig_script() {
    # Create a script to configure networking

    # Get main interface name
    INTERFACE=$(ip route | grep default | awk '{print $5}')

    # ensure iproute is installed
    yum install -y iproute

    cat <<EOF > /ccdc/scripts/linux/netconfig.sh
#!/bin/bash
# Check if the network is already configured, we can check this with an ifconfig and see the status of the interface
if [ -z "\$(ifconfig $INTERFACE | grep 'inet ')" ]; then
    # enable the interface
    ip link set $INTERFACE up
    # Set the IP address, subnet mask, and gateway
    ip addr add $(ip -f inet addr show $INTERFACE | grep "inet " | awk '{print $2}' ) dev $INTERFACE
    ip route add default via $(ip route | grep default | awk '{print $3}') dev $INTERFACE

    # set the DNS server in the resolv.conf file
    echo "nameserver 1.1.1.1" > /etc/resolv.conf
    echo "nameserver 1.0.0.1" >> /etc/resolv.conf

    echo "Networking configured successfully"
else
    echo "Networking is already configured"
fi
EOF

    chmod +x /ccdc/scripts/linux/netconfig.sh

    # Create a service to run the script at boot after the network is up
    cat <<EOF > /etc/systemd/system/ccdc_netconfig.service
[Unit]
Description=Configure Networking for CCDC, run netconfig.sh
After=network-online.target

[Service]
ExecStart=/ccdc/scripts/linux/netconfig.sh
Type=oneshot
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

    systemctl enable netconfig
}

create_deny_access_script() {
    cat <<'EOF' > /ccdc/scripts/linux/apache_access.sh
#!/bin/bash

# create a script that will list out all directories 2 layers deep in /var/www/html, so this would be /var/www/html/directory1/directory2
# Then allow the user to select the directories they want to remove access from, it will also automatically get revoked directories from the apache configuration file
# The script will then remove access from the directories and restart the apache service

if [ $(id -u) -ne 0 ]; then
    echo "You must be root to run this script"
    exit 1
fi

# Check if dialog is installed
if [ ! $(which dialog) ]; then
    echo "The dialog package is not installed"
    if [ $(which apt) ]; then
        apt install -y dialog
    elif [ $(which yum) ]; then
        yum install -y dialog
    else
        echo "Could not install dialog package"
        exit 4
    fi
fi

if [ ! -d /var/www/html ]; then
    echo "The /var/www/html directory does not exist"
    exit 2
fi

if [ -f /etc/apache2/apache2.conf ]; then
    APACHE_CONF="/etc/apache2/apache2.conf"
elif [ -f /etc/httpd/conf/httpd.conf ]; then
    APACHE_CONF="/etc/httpd/conf/httpd.conf"
else
    echo "The apache configuration file could not be found"
    exit 3
fi

# Get the directories 2 layers deep in /var/www/html
DIRECTORIES=$(find /var/www/html -mindepth 2 -maxdepth 2 -type d)

# Create an array of the directories
declare -a DIR_ARRAY
i=0
for DIR in $DIRECTORIES
do
    DIR_ARRAY[$i]=$DIR
    i=$(($i+1))
done

# Get the currently denied directories from the apache configuration file
DENIED_DIRECTORIES=$(grep "RedirectMatch 404" "$APACHE_CONF" | awk '{print $3}' | sed 's/^\^//g')



# Truncate the array to remove the /var/www/html prefix
for ((i=0; i<${#DIR_ARRAY[@]}; i++))
do
    DIR_ARRAY[$i]=${DIR_ARRAY[$i]#/var/www/html/}
done

choices=(
    $(for ((i=0; i<${#DIR_ARRAY[@]}; i++)); do
        if echo "$DENIED_DIRECTORIES" | grep -q "^/${DIR_ARRAY[$i]}$"; then
            echo $i "${DIR_ARRAY[$i]}" on
        else
            echo $i "${DIR_ARRAY[$i]}" off
        fi
    done)
)

# Use dialog to show the checklist
output=$(dialog --checklist "Select items:" 15 40 5 "${choices[@]}" 2>&1 >/dev/tty)
exit_status=$?
clear

# Check if the exit status is 1 (cancel)
if [ $exit_status -eq 1 ] || [ $exit_status -eq 255  ]; then
    echo "User cancelled, changes not saved"
    exit 0
fi

# Set the apache configuration file for each item selected to be denied via RedirectMatch 404 ^/directory
for i in $output
do
    # Only add the RedirectMatch if it's not already present
    if ! grep -q "RedirectMatch 404 ^/${DIR_ARRAY[$i]}" $APACHE_CONF; then
        echo "RedirectMatch 404 ^/${DIR_ARRAY[$i]}" >> $APACHE_CONF
    fi
done


# for the other items that are not in the selected list, remove the RedirectMatch 404 ^/prestashop/classes
for ((i=0; i<${#DIR_ARRAY[@]}; i++))
do
    if ! echo $output | grep -q $i; then
        sed -i "\|RedirectMatch 404 ^/${DIR_ARRAY[$i]}|d" "$APACHE_CONF"
    fi
done

echo "Restarting apache service"
# The service might be called apache2 or httpd
if systemctl is-active --quiet httpd; then
    echo "httpd is running, restarting..."
    systemctl restart httpd
# Check if apache2 is running (alternative name for some systems like Ubuntu)
elif systemctl is-active --quiet apache2; then
    echo "apache2 is running, restarting..."
    systemctl restart apache2
else
    echo "Neither httpd nor apache2 is running."
fi
EOF

    chmod +x /ccdc/scripts/linux/apache_access.sh
}


check_for_malicious_bash() {
    # we need to check all of the bash configuration files to see if they ever set a trap, or set PROMPT_COMMAND
    # if they do, we need to check the contents of the trap or PROMPT_COMMAND and print them to a file, and remove them

    # Check if logs directory exists
    if [ ! -d /ccdc ]; then
        mkdir -p /ccdc/logs
    fi

    for FILE in /etc/bashrc /etc/profile /etc/profile.d/* /root/.bashrc /root/.bash_profile /root/.bash_logout /home/*/.bashrc /home/*/.bash_profile /home/*/.bash_logout /etc/bash.bashrc /etc/bash.bash_logout /etc/bash.bash_profile /root/.bash_login /home/*/.bash_login /root/.profile /home/*/.profile /etc/environment
    do
        if [ -f "$FILE" ]; then
            # check if the file contains a trap or PROMPT_COMMAND
            if grep -q "trap" "$FILE" || grep -q "PROMPT_COMMAND" $FILE; then
                # get the contents of the trap or PROMPT_COMMAND
                if grep -q "^[^#]*trap" "$FILE"; then
                    TRAP_CONTENT=$(grep "^[^#]*trap" "$FILE")
                fi
                if grep -q "^[^#]*PROMPT_COMMAND" "$FILE"; then
                    PROMPT_COMMAND_CONTENT=$(grep "^[^#]*PROMPT_COMMAND" $FILE)
                fi

                # remove the trap or PROMPT_COMMAND
                sed -i '/^[^#]*trap/d' "$FILE"
                sed -i '/^[^#]*PROMPT_COMMAND/d' "$FILE"

                # print the contents of the trap or PROMPT_COMMAND to a file
                if [ -n "$TRAP_CONTENT" ]; then
                    echo "$TRAP_CONTENT   Found in $FILE On $(date)" >> /ccdc/logs/malicious_bash.txt
                fi
                if [ -n "$PROMPT_COMMAND_CONTENT" ]; then
                    echo "$PROMPT_COMMAND_CONTENT   Found in $FILE On $(date)" >> /ccdc/logs/malicious_bash.txt
                fi
            fi
        fi
    done

    # set PROMPT_COMMAND to '', and remove any traps
    export PROMPT_COMMAND=''
    TRAPS=$(trap -p | awk '{print $NF}')
    for TRAP in $TRAPS
    do
        trap $TRAP
    done
}




# Fancy GUI
cronjail > /dev/null 2>&1 &
cronjail_pid=$!
check_for_malicious_bash > /dev/null 2>&1 &
malicious_bash_pid=$!

#output the services that we are still waiting on, and when they complete then put an ok message next to the service
while [ -e /proc/$cronjail_pid ] || [ -e /proc/$malicious_bash_pid ]; do
    clear
    printf "Waiting for cronjail to complete... $(if [ ! -e /proc/$cronjail_pid ]; then printf "[$GREEN OK $NC]\n"; else printf "[$RED WAITING $NC]\n"; fi)\n"
    printf "Checking for malicious bash scripts... $(if [ ! -e /proc/$malicious_bash_pid ]; then printf "[$GREEN OK $NC]\n"; else printf "[$RED WAITING $NC]\n"; fi)\n"
    sleep 5
done


prescripts > /dev/null 2>&1 &
prescripts_pid=$!

#output the services that we are still waiting on, and when they complete then put an ok message next to the service
while [ -e /proc/$prescripts_pid ]; do
    clear
    prinft "Waiting for cronjail to complete... $(if [ ! -e /proc/$cronjail_pid ]; then printf "[$GREEN OK $NC]\n"; else printf "[$RED WAITING $NC]\n"; fi)\n"
    printf "Checking for malicious bash scripts... $(if [ ! -e /proc/$malicious_bash_pid ]; then printf "[$GREEN OK $NC]\n"; else printf "[$RED WAITING $NC]\n"; fi)\n"
    printf "Running pre-scripts... $(if [ ! -e /proc/$prescripts_pid ]; then printf "[$GREEN OK $NC]\n"; else printf "[$RED WAITING $NC]\n"; fi)\n"
    sleep 5
done


configure_networking > /dev/null 2>&1 &
networking_pid=$!

#output the services that we are still waiting on, and when they complete then put an ok message next to the service
while [ -e /proc/$networking_pid ]; do
    clear
    printf "Waiting for cronjail to complete... $(if [ ! -e /proc/$cronjail_pid ]; then printf "[$GREEN OK $NC]\n"; else printf "[$RED WAITING $NC]\n"; fi)\n"
    printf "Checking for malicious bash scripts... $(if [ ! -e /proc/$malicious_bash_pid ]; then printf "[$GREEN OK $NC]\n"; else printf "[$RED WAITING $NC]\n"; fi)\n"
    printf "Running pre-scripts... $(if [ ! -e /proc/$prescripts_pid ]; then printf "[$GREEN OK $NC]\n"; else printf "[$RED WAITING $NC]\n"; fi)\n"
    printf "Configuring networking... $(if [ ! -e /proc/$networking_pid ]; then printf "[$GREEN OK $NC]\n"; else printf "[$RED WAITING $NC]\n"; fi)\n"
    sleep 5
done

iptables > /dev/null 2>&1 &
iptables_pid=$!

#output the services that we are still waiting on, and when they complete then put an ok message next to the service
while [ -e /proc/$iptables_pid ]; do
    clear
    printf "Waiting for cronjail to complete... $(if [ ! -e /proc/$cronjail_pid ]; then printf "[$GREEN OK $NC]\n"; else printf "[$RED WAITING $NC]\n"; fi)\n"
    printf "Checking for malicious bash scripts... $(if [ ! -e /proc/$malicious_bash_pid ]; then printf "[$GREEN OK $NC]\n"; else printf "[$RED WAITING $NC]\n"; fi)\n"
    printf "Running pre-scripts... $(if [ ! -e /proc/$prescripts_pid ]; then printf "[$GREEN OK $NC]\n"; else printf "[$RED WAITING $NC]\n"; fi)\n"
    printf "Configuring networking... $(if [ ! -e /proc/$networking_pid ]; then printf "[$GREEN OK $NC]\n"; else printf "[$RED WAITING $NC]\n"; fi)\n"
    printf "Configuring iptables... $(if [ ! -e /proc/$iptables_pid ]; then printf "[$GREEN OK $NC]\n"; else printf "[$RED WAITING $NC]\n"; fi)\n"
    sleep 5
done

if [ "$APACHE" == "true" ]; then
    prestashop_config > /dev/null 2>&1 &
    prestashop_pid=$!

    #output the services that we are still waiting on, and when they complete then put an ok message next to the service
    while [ -e /proc/$prestashop_pid ]; do
        clear
        printf "Waiting for cronjail to complete... $(if [ ! -e /proc/$cronjail_pid ]; then printf "[$GREEN OK $NC]\n"; else printf "[$RED WAITING $NC]\n"; fi)\n"
        printf "Checking for malicious bash scripts... $(if [ ! -e /proc/$malicious_bash_pid ]; then printf "[$GREEN OK $NC]\n"; else printf "[$RED WAITING $NC]\n"; fi)\n"
        printf "Running pre-scripts... $(if [ ! -e /proc/$prescripts_pid ]; then printf "[$GREEN OK $NC]\n"; else printf "[$RED WAITING $NC]\n"; fi)\n"
        printf "Configuring networking... $(if [ ! -e /proc/$networking_pid ]; then printf "[$GREEN OK $NC]\n"; else printf "[$RED WAITING $NC]\n"; fi)\n"
        printf "Configuring iptables... $(if [ ! -e /proc/$iptables_pid ]; then printf "[$GREEN OK $NC]\n"; else printf "[$RED WAITING $NC]\n"; fi)\n"
        printf "Configuring Prestashop... $(if [ ! -e /proc/$prestashop_pid ]; then printf "[$GREEN OK $NC]\n"; else printf "[$RED WAITING $NC]\n"; fi)\n"
        sleep 5
    done
fi

legalese > /dev/null 2>&1 &
legalese_pid=$!

#output the services that we are still waiting on, and when they complete then put an ok message next to the service
while [ -e /proc/$legalese_pid ]; do
    clear
    printf "Waiting for cronjail to complete... $(if [ ! -e /proc/$cronjail_pid ]; then printf "[$GREEN OK $NC]\n"; else printf "[$RED WAITING $NC]\n"; fi)\n"
    printf "Checking for malicious bash scripts... $(if [ ! -e /proc/$malicious_bash_pid ]; then printf "[$GREEN OK $NC]\n"; else printf "[$RED WAITING $NC]\n"; fi)\n"
    printf "Running pre-scripts... $(if [ ! -e /proc/$prescripts_pid ]; then printf "[$GREEN OK $NC]\n"; else printf "[$RED WAITING $NC]\n"; fi)\n"
    printf "Configuring networking... $(if [ ! -e /proc/$networking_pid ]; then printf "[$GREEN OK $NC]\n"; else printf "[$RED WAITING $NC]\n"; fi)\n"
    printf "Configuring iptables... $(if [ ! -e /proc/$iptables_pid ]; then printf "[$GREEN OK $NC]\n"; else printf "[$RED WAITING $NC]\n"; fi)\n"
    printf "Configuring Prestashop... $(if [ ! -e /proc/$prestashop_pid ]; then printf "[$GREEN OK $NC]\n"; else printf "[$RED WAITING $NC]\n"; fi)\n"
    printf "Adding legalese... $(if [ ! -e /proc/$legalese_pid ]; then printf "[$GREEN OK $NC]\n"; else printf "[$RED WAITING $NC]\n"; fi)\n"
    sleep 5
done

harden > /dev/null 2>&1 &
harden_pid=$!

#output the services that we are still waiting on, and when they complete then put an ok message next to the service
while [ -e /proc/$harden_pid ]; do
    clear
    printf "Waiting for cronjail to complete... $(if [ ! -e /proc/$cronjail_pid ]; then printf "[$GREEN OK $NC]\n"; else printf "[$RED WAITING $NC]\n"; fi)\n"
    printf "Checking for malicious bash scripts... $(if [ ! -e /proc/$malicious_bash_pid ]; then printf "[$GREEN OK $NC]\n"; else printf "[$RED WAITING $NC]\n"; fi)\n"
    printf "Running pre-scripts... $(if [ ! -e /proc/$prescripts_pid ]; then printf "[$GREEN OK $NC]\n"; else printf "[$RED WAITING $NC]\n"; fi)\n"
    printf "Configuring networking... $(if [ ! -e /proc/$networking_pid ]; then printf "[$GREEN OK $NC]\n"; else printf "[$RED WAITING $NC]\n"; fi)\n"
    printf "Configuring iptables... $(if [ ! -e /proc/$iptables_pid ]; then printf "[$GREEN OK $NC]\n"; else printf "[$RED WAITING $NC]\n"; fi)\n"
    printf "Configuring Prestashop... $(if [ ! -e /proc/$prestashop_pid ]; then printf "[$GREEN OK $NC]\n"; else printf "[$RED WAITING $NC]\n"; fi)\n"
    printf "Adding legalese... $(if [ ! -e /proc/$legalese_pid ]; then printf "[$GREEN OK $NC]\n"; else printf "[$RED WAITING $NC]\n"; fi)\n"
    printf "Hardening system... $(if [ ! -e /proc/$harden_pid ]; then printf "[$GREEN OK $NC]\n"; else printf "[$RED WAITING $NC]\n"; fi)\n"
    sleep 5
done

remove_unneeded_services > /dev/null 2>&1 &
remove_services_pid=$!

#output the services that we are still waiting on, and when they complete then put an ok message next to the service
while [ -e /proc/$remove_services_pid ]; do
    clear
    printf "Waiting for cronjail to complete... $(if [ ! -e /proc/$cronjail_pid ]; then printf "[$GREEN OK $NC]\n"; else printf "[$RED WAITING $NC]\n"; fi)\n"
    printf "Checking for malicious bash scripts... $(if [ ! -e /proc/$malicious_bash_pid ]; then printf "[$GREEN OK $NC]\n"; else printf "[$RED WAITING $NC]\n"; fi)\n"
    printf "Running pre-scripts... $(if [ ! -e /proc/$prescripts_pid ]; then printf "[$GREEN OK $NC]\n"; else printf "[$RED WAITING $NC]\n"; fi)\n"
    printf "Configuring networking... $(if [ ! -e /proc/$networking_pid ]; then printf "[$GREEN OK $NC]\n"; else printf "[$RED WAITING $NC]\n"; fi)\n"
    printf "Configuring iptables... $(if [ ! -e /proc/$iptables_pid ]; then printf "[$GREEN OK $NC]\n"; else printf "[$RED WAITING $NC]\n"; fi)\n"
    printf "Configuring Prestashop... $(if [ ! -e /proc/$prestashop_pid ]; then printf "[$GREEN OK $NC]\n"; else printf "[$RED WAITING $NC]\n"; fi)\n"
    printf "Adding legalese... $(if [ ! -e /proc/$legalese_pid ]; then printf "[$GREEN OK $NC]\n"; else printf "[$RED WAITING $NC]\n"; fi)\n"
    printf "Hardening system... $(if [ ! -e /proc/$harden_pid ]; then printf "[$GREEN OK $NC]\n"; else printf "[$RED WAITING $NC]\n"; fi)\n"
    printf "Removing unneeded services... $(if [ ! -e /proc/$remove_services_pid ]; then printf "[$GREEN OK $NC]\n"; else printf "[$RED WAITING $NC]\n"; fi)\n"
    sleep 5
done


update_packages  > /dev/null 2>&1 &
update_packages_pid=$!

#output the services that we are still waiting on, and when they complete then put an ok message next to the service
while [ -e /proc/$update_packages_pid ]; do
    clear
    printf "Waiting for cronjail to complete... $(if [ ! -e /proc/$cronjail_pid ]; then printf "[$GREEN OK $NC]\n"; else printf "[$RED WAITING $NC]\n"; fi)\n"
    printf "Checking for malicious bash scripts... $(if [ ! -e /proc/$malicious_bash_pid ]; then printf "[$GREEN OK $NC]\n"; else printf "[$RED WAITING $NC]\n"; fi)\n"
    printf "Running pre-scripts... $(if [ ! -e /proc/$prescripts_pid ]; then printf "[$GREEN OK $NC]\n"; else printf "[$RED WAITING $NC]\n"; fi)\n"
    printf "Configuring networking... $(if [ ! -e /proc/$networking_pid ]; then printf "[$GREEN OK $NC]\n"; else printf "[$RED WAITING $NC]\n"; fi)\n"
    printf "Configuring iptables... $(if [ ! -e /proc/$iptables_pid ]; then printf "[$GREEN OK $NC]\n"; else printf "[$RED WAITING $NC]\n"; fi)\n"
    printf "Configuring Prestashop... $(if [ ! -e /proc/$prestashop_pid ]; then printf "[$GREEN OK $NC]\n"; else printf "[$RED WAITING $NC]\n"; fi)\n"
    printf "Adding legalese... $(if [ ! -e /proc/$legalese_pid ]; then printf "[$GREEN OK $NC]\n"; else printf "[$RED WAITING $NC]\n"; fi)\n"
    printf "Hardening system... $(if [ ! -e /proc/$harden_pid ]; then printf "[$GREEN OK $NC]\n"; else printf "[$RED WAITING $NC]\n"; fi)\n"
    printf "Removing unneeded services... $(if [ ! -e /proc/$remove_services_pid ]; then printf "[$GREEN OK $NC]\n"; else printf "[$RED WAITING $NC]\n"; fi)\n"
    printf "Updating packages... $(if [ ! -e /proc/$update_packages_pid ]; then printf "[$GREEN OK $NC]\n"; else printf "[$RED WAITING $NC]\n"; fi)\n"
    sleep 5
done


ipv6_config  > /dev/null 2>&1 &
ipv6_config_pid=$!

#output the services that we are still waiting on, and when they complete then put an ok message next to the service
while [ -e /proc/$ipv6_config_pid ]; do
    clear
    printf "Waiting for cronjail to complete... $(if [ ! -e /proc/$cronjail_pid ]; then printf "[$GREEN OK $NC]\n"; else printf "[$RED WAITING $NC]\n"; fi)\n"
    printf "Checking for malicious bash scripts... $(if [ ! -e /proc/$malicious_bash_pid ]; then printf "[$GREEN OK $NC]\n"; else printf "[$RED WAITING $NC]\n"; fi)\n"
    printf "Running pre-scripts... $(if [ ! -e /proc/$prescripts_pid ]; then printf "[$GREEN OK $NC]\n"; else printf "[$RED WAITING $NC]\n"; fi)\n"
    printf "Configuring networking... $(if [ ! -e /proc/$networking_pid ]; then printf "[$GREEN OK $NC]\n"; else printf "[$RED WAITING $NC]\n"; fi)\n"
    printf "Configuring iptables... $(if [ ! -e /proc/$iptables_pid ]; then printf "[$GREEN OK $NC]\n"; else printf "[$RED WAITING $NC]\n"; fi)\n"
    printf "Configuring Prestashop... $(if [ ! -e /proc/$prestashop_pid ]; then printf "[$GREEN OK $NC]\n"; else printf "[$RED WAITING $NC]\n"; fi)\n"
    printf "Adding legalese... $(if [ ! -e /proc/$legalese_pid ]; then printf "[$GREEN OK $NC]\n"; else printf "[$RED WAITING $NC]\n"; fi)\n"
    printf "Hardening system... $(if [ ! -e /proc/$harden_pid ]; then printf "[$GREEN OK $NC]\n"; else printf "[$RED WAITING $NC]\n"; fi)\n"
    printf "Removing unneeded services... $(if [ ! -e /proc/$remove_services_pid ]; then printf "[$GREEN OK $NC]\n"; else printf "[$RED WAITING $NC]\n"; fi)\n"
    printf "Updating packages... $(if [ ! -e /proc/$update_packages_pid ]; then printf "[$GREEN OK $NC]\n"; else printf "[$RED WAITING $NC]\n"; fi)\n"
    printf "Configuring IPv6... $(if [ ! -e /proc/$ipv6_config_pid ]; then printf "[$GREEN OK $NC]\n"; else printf "[$RED WAITING $NC]\n"; fi)\n"
    sleep 5
done

install_packages  > /dev/null 2>&1 &
install_packages_pid=$!

#output the services that we are still waiting on, and when they complete then put an ok message next to the service
while [ -e /proc/$install_packages_pid ]; do
    clear
    printf "Waiting for cronjail to complete... $(if [ ! -e /proc/$cronjail_pid ]; then printf "[$GREEN OK $NC]\n"; else printf "[$RED WAITING $NC]\n"; fi)\n"
    printf "Checking for malicious bash scripts... $(if [ ! -e /proc/$malicious_bash_pid ]; then printf "[$GREEN OK $NC]\n"; else printf "[$RED WAITING $NC]\n"; fi)\n"
    printf "Running pre-scripts... $(if [ ! -e /proc/$prescripts_pid ]; then printf "[$GREEN OK $NC]\n"; else printf "[$RED WAITING $NC]\n"; fi)\n"
    printf "Configuring networking... $(if [ ! -e /proc/$networking_pid ]; then printf "[$GREEN OK $NC]\n"; else printf "[$RED WAITING $NC]\n"; fi)\n"
    printf "Configuring iptables... $(if [ ! -e /proc/$iptables_pid ]; then printf "[$GREEN OK $NC]\n"; else printf "[$RED WAITING $NC]\n"; fi)\n"
    printf "Configuring Prestashop... $(if [ ! -e /proc/$prestashop_pid ]; then printf "[$GREEN OK $NC]\n"; else printf "[$RED WAITING $NC]\n"; fi)\n"
    printf "Adding legalese... $(if [ ! -e /proc/$legalese_pid ]; then printf "[$GREEN OK $NC]\n"; else printf "[$RED WAITING $NC]\n"; fi)\n"
    printf "Hardening system... $(if [ ! -e /proc/$harden_pid ]; then printf "[$GREEN OK $NC]\n"; else printf "[$RED WAITING $NC]\n"; fi)\n"
    printf "Removing unneeded services... $(if [ ! -e /proc/$remove_services_pid ]; then printf "[$GREEN OK $NC]\n"; else printf "[$RED WAITING $NC]\n"; fi)\n"
    printf "Updating packages... $(if [ ! -e /proc/$update_packages_pid ]; then printf "[$GREEN OK $NC]\n"; else printf "[$RED WAITING $NC]\n"; fi)\n"
    printf "Configuring IPv6... $(if [ ! -e /proc/$ipv6_config_pid ]; then printf "[$GREEN OK $NC]\n"; else printf "[$RED WAITING $NC]\n"; fi)\n"
    printf "Installing packages... $(if [ ! -e /proc/$install_packages_pid ]; then printf "[$GREEN OK $NC]\n"; else printf "[$RED WAITING $NC]\n"; fi)\n"
    sleep 5
done



initialize_clamav &
clamav_pid=$!
configure_and_init_aide &
aide_pid=$!
install_additional_scripts &
scripts_pid=$!
initialize_auditd &
auditd_pid=$!
netconfig_script &
netconfig_pid=$!
create_deny_access_script &
deny_access_pid=$!



#output the services that we are still waiting on, and when they complete then put an ok message next to the service
while [ -e /proc/$clamav_pid ] || [ -e /proc/$aide_pid ] || [ -e /proc/$scripts_pid ] || [ -e /proc/$auditd_pid ] || [ -e /proc/$netconfig_pid ] || [ -e /proc/$deny_access_pid ]; do
    clear
    printf "Waiting for ClamAV to initialize... $(if [ ! -e /proc/$clamav_pid ]; then printf "[$GREEN OK $NC]\n"; else printf "[$RED WAITING $NC]\n"; fi)\n"
    printf "Waiting for AIDE to initialize... $(if [ ! -e /proc/$aide_pid ]; then printf "[$GREEN OK $NC]\n"; else printf "[$RED WAITING $NC]\n"; fi)\n"
    printf "Waiting for additional scripts to install... $(if [ ! -e /proc/$scripts_pid ]; then printf "[$GREEN OK $NC]\n"; else printf "[$RED WAITING $NC]\n"; fi)\n"
    printf "Waiting for Auditd to initialize... $(if [ ! -e /proc/$auditd_pid ]; then printf "[$GREEN OK $NC]\n"; else printf "[$RED WAITING $NC]\n"; fi)\n"
    printf "Waiting for netconfig script to complete... $(if [ ! -e /proc/$netconfig_pid ]; then printf "[$GREEN OK $NC]\n"; else printf "[$RED WAITING $NC]\n"; fi)\n"
    printf "Waiting for deny access script to complete... $(if [ ! -e /proc/$deny_access_pid ]; then printf "[$GREEN OK $NC]\n"; else printf "[$RED WAITING $NC]\n"; fi)\n"
    sleep 5
    # remove the last 6 lines
done

echo "Finished running init.sh, please reboot the system to apply changes"