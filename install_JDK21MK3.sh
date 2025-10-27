#!/bin/bash

# Script to install Java 17/21 (Temurin) on Debian 12 Bookworm with easy switching
# Usage: ./install-java21.sh

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default database settings
DEFAULT_DB_HOST="localhost"
DEFAULT_DB_PORT="3306"
DEFAULT_DB_NAME="eliteel5_business"
DEFAULT_SERVERS_DB="user_servers"
DEFAULT_TABLE="servers"

# Installation commands for both versions
INSTALL_COMMANDS='
set -e
echo -e "\033[0;32m=== Installing Java (Eclipse Temurin) on Debian 12 ===\033[0m\n"

# Check if Java 17 and 21 are already installed
JAVA17_INSTALLED=0
JAVA21_INSTALLED=0

if dpkg -l | grep -q "temurin-17-jdk"; then
    echo -e "\033[0;32mJava 17 is already installed\033[0m"
    JAVA17_INSTALLED=1
else
    echo -e "\033[1;33mJava 17 is not installed\033[0m"
fi

if dpkg -l | grep -q "temurin-21-jdk"; then
    echo -e "\033[0;32mJava 21 is already installed\033[0m"
    JAVA21_INSTALLED=1
else
    echo -e "\033[1;33mJava 21 is not installed\033[0m"
fi

# If both are installed, ask if user wants to reinstall or skip
if [ $JAVA17_INSTALLED -eq 1 ] && [ $JAVA21_INSTALLED -eq 1 ]; then
    echo -e "\n\033[0;32mBoth Java 17 and 21 are already installed!\033[0m"
    echo -e "\033[1;33mSkipping installation...\033[0m\n"
    
    # Ensure switch-java exists
    if [ ! -f "/usr/local/bin/switch-java" ]; then
        echo -e "\033[1;33mCreating Java version switcher...\033[0m"
        cat > /usr/local/bin/switch-java << "SWITCHER_EOF"
#!/bin/bash

# Java version switcher for Temurin 17 and 21

RED="\033[0;31m"
GREEN="\033[0;32m"
YELLOW="\033[1;33m"
BLUE="\033[0;34m"
NC="\033[0m"

show_current() {
    if [ -L /etc/alternatives/java ]; then
        CURRENT=$(readlink -f /etc/alternatives/java)
        if [[ "$CURRENT" == *"temurin-17"* ]]; then
            echo -e "${GREEN}Current Java version: 17${NC}"
        elif [[ "$CURRENT" == *"temurin-21"* ]]; then
            echo -e "${GREEN}Current Java version: 21${NC}"
        else
            echo -e "${YELLOW}Current Java version: Unknown${NC}"
        fi
        java -version 2>&1 | head -n 1
    else
        echo -e "${RED}Java is not configured${NC}"
    fi
}

switch_to_17() {
    echo -e "${YELLOW}Switching to Java 17...${NC}"
    update-alternatives --set java /usr/lib/jvm/temurin-17-jdk-amd64/bin/java
    update-alternatives --set javac /usr/lib/jvm/temurin-17-jdk-amd64/bin/javac
    export JAVA_HOME=/usr/lib/jvm/temurin-17-jdk-amd64
    echo -e "${GREEN}Switched to Java 17${NC}"
    java -version
}

switch_to_21() {
    echo -e "${YELLOW}Switching to Java 21...${NC}"
    update-alternatives --set java /usr/lib/jvm/temurin-21-jdk-amd64/bin/java
    update-alternatives --set javac /usr/lib/jvm/temurin-21-jdk-amd64/bin/javac
    export JAVA_HOME=/usr/lib/jvm/temurin-21-jdk-amd64
    echo -e "${GREEN}Switched to Java 21${NC}"
    java -version
}

show_menu() {
    echo -e "${BLUE}╔═══════════════════════════════╗${NC}"
    echo -e "${BLUE}║   Java Version Switcher       ║${NC}"
    echo -e "${BLUE}╚═══════════════════════════════╝${NC}\n"
    show_current
    echo ""
    echo -e "${YELLOW}1)${NC} Switch to Java 17"
    echo -e "${YELLOW}2)${NC} Switch to Java 21"
    echo -e "${YELLOW}3)${NC} Show current version"
    echo -e "${YELLOW}4)${NC} Exit\n"
    echo -e "${BLUE}Select an option (1-4):${NC} "
}

if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}Error: This script must be run as root or with sudo${NC}"
    exit 1
fi

# Handle command line argument
if [ "$1" == "17" ]; then
    switch_to_17
    exit 0
elif [ "$1" == "21" ]; then
    switch_to_21
    exit 0
elif [ "$1" == "status" ]; then
    show_current
    exit 0
fi

# Interactive menu
while true; do
    show_menu
    read -r CHOICE
    
    case $CHOICE in
        1)
            switch_to_17
            break
            ;;
        2)
            switch_to_21
            break
            ;;
        3)
            show_current
            echo ""
            ;;
        4)
            echo -e "${GREEN}Exiting...${NC}"
            exit 0
            ;;
        *)
            echo -e "${RED}Invalid option. Please select 1-4.${NC}\n"
            ;;
    esac
done
SWITCHER_EOF
        chmod +x /usr/local/bin/switch-java
    fi
    
    echo -e "\033[0;32mJava is already set up. Use \"sudo switch-java\" to switch versions.\033[0m"
    exit 0
fi

echo -e "\033[1;33mStep 1: Updating package list...\033[0m"
apt update

echo -e "\033[1;33mStep 2: Installing prerequisites...\033[0m"
apt install -y wget apt-transport-https gpg

echo -e "\033[1;33mStep 3: Adding Adoptium GPG key...\033[0m"
wget -qO - https://packages.adoptium.net/artifactory/api/gpg/key/public | gpg --dearmor | tee /etc/apt/trusted.gpg.d/adoptium.gpg > /dev/null

echo -e "\033[1;33mStep 4: Adding Adoptium repository...\033[0m"
CODENAME=$(awk -F= "/^VERSION_CODENAME/{print\$2}" /etc/os-release)
echo "deb https://packages.adoptium.net/artifactory/deb ${CODENAME} main" | tee /etc/apt/sources.list.d/adoptium.list

echo -e "\033[1;33mStep 5: Updating package list with new repository...\033[0m"
apt update

# Install only what is needed
if [ $JAVA17_INSTALLED -eq 0 ] && [ $JAVA21_INSTALLED -eq 0 ]; then
    echo -e "\033[1;33mStep 6: Installing Temurin JDK 17 and 21...\033[0m"
    apt install -y temurin-17-jdk temurin-21-jdk
elif [ $JAVA17_INSTALLED -eq 0 ]; then
    echo -e "\033[1;33mStep 6: Installing Temurin JDK 17...\033[0m"
    apt install -y temurin-17-jdk
elif [ $JAVA21_INSTALLED -eq 0 ]; then
    echo -e "\033[1;33mStep 6: Installing Temurin JDK 21...\033[0m"
    apt install -y temurin-21-jdk
fi

echo -e "\n\033[0;32m=== Installation Complete ===\033[0m\n"

# Create java switcher script
echo -e "\033[1;33mCreating Java version switcher...\033[0m"
cat > /usr/local/bin/switch-java << "SWITCHER_EOF"
#!/bin/bash

# Java version switcher for Temurin 17 and 21

RED="\033[0;31m"
GREEN="\033[0;32m"
YELLOW="\033[1;33m"
BLUE="\033[0;34m"
NC="\033[0m"

show_current() {
    if [ -L /etc/alternatives/java ]; then
        CURRENT=$(readlink -f /etc/alternatives/java)
        if [[ "$CURRENT" == *"temurin-17"* ]]; then
            echo -e "${GREEN}Current Java version: 17${NC}"
        elif [[ "$CURRENT" == *"temurin-21"* ]]; then
            echo -e "${GREEN}Current Java version: 21${NC}"
        else
            echo -e "${YELLOW}Current Java version: Unknown${NC}"
        fi
        java -version 2>&1 | head -n 1
    else
        echo -e "${RED}Java is not configured${NC}"
    fi
}

switch_to_17() {
    echo -e "${YELLOW}Switching to Java 17...${NC}"
    update-alternatives --set java /usr/lib/jvm/temurin-17-jdk-amd64/bin/java
    update-alternatives --set javac /usr/lib/jvm/temurin-17-jdk-amd64/bin/javac
    export JAVA_HOME=/usr/lib/jvm/temurin-17-jdk-amd64
    echo -e "${GREEN}Switched to Java 17${NC}"
    java -version
}

switch_to_21() {
    echo -e "${YELLOW}Switching to Java 21...${NC}"
    update-alternatives --set java /usr/lib/jvm/temurin-21-jdk-amd64/bin/java
    update-alternatives --set javac /usr/lib/jvm/temurin-21-jdk-amd64/bin/javac
    export JAVA_HOME=/usr/lib/jvm/temurin-21-jdk-amd64
    echo -e "${GREEN}Switched to Java 21${NC}"
    java -version
}

show_menu() {
    echo -e "${BLUE}╔═══════════════════════════════╗${NC}"
    echo -e "${BLUE}║   Java Version Switcher       ║${NC}"
    echo -e "${BLUE}╚═══════════════════════════════╝${NC}\n"
    show_current
    echo ""
    echo -e "${YELLOW}1)${NC} Switch to Java 17"
    echo -e "${YELLOW}2)${NC} Switch to Java 21"
    echo -e "${YELLOW}3)${NC} Show current version"
    echo -e "${YELLOW}4)${NC} Exit\n"
    echo -e "${BLUE}Select an option (1-4):${NC} "
}

if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}Error: This script must be run as root or with sudo${NC}"
    exit 1
fi

# Handle command line argument
if [ "$1" == "17" ]; then
    switch_to_17
    exit 0
elif [ "$1" == "21" ]; then
    switch_to_21
    exit 0
elif [ "$1" == "status" ]; then
    show_current
    exit 0
fi

# Interactive menu
while true; do
    show_menu
    read -r CHOICE
    
    case $CHOICE in
        1)
            switch_to_17
            break
            ;;
        2)
            switch_to_21
            break
            ;;
        3)
            show_current
            echo ""
            ;;
        4)
            echo -e "${GREEN}Exiting...${NC}"
            exit 0
            ;;
        *)
            echo -e "${RED}Invalid option. Please select 1-4.${NC}\n"
            ;;
    esac
done
SWITCHER_EOF

chmod +x /usr/local/bin/switch-java

echo -e "\n\033[0;32mJava 17 and 21 have been successfully installed!\033[0m"
echo -e "\033[1;33mTo switch between Java versions, run: sudo switch-java${NC}"
echo -e "\033[1;33mOr use: sudo switch-java 17  or  sudo switch-java 21${NC}"
'

# Function to install locally
install_local() {
    echo -e "${GREEN}=== Installing Java 17 & 21 Locally ===${NC}\n"
    
    # Check if running as root
    if [ "$EUID" -ne 0 ]; then 
        echo -e "${RED}Error: This script must be run as root or with sudo for local installation${NC}"
        exit 1
    fi
    
    eval "$INSTALL_COMMANDS"
    
    echo -e "\n${YELLOW}Initial setup complete. Configuring Java 21 as default...${NC}"
    update-alternatives --set java /usr/lib/jvm/temurin-21-jdk-amd64/bin/java
    update-alternatives --set javac /usr/lib/jvm/temurin-21-jdk-amd64/bin/javac
    
    echo -e "\n${GREEN}═══════════════════════════════════════════${NC}"
    echo -e "${GREEN}Installation and setup complete!${NC}"
    echo -e "${GREEN}═══════════════════════════════════════════${NC}\n"
    echo -e "${YELLOW}Current Java version:${NC}"
    java -version
    echo -e "\n${YELLOW}To switch between Java versions:${NC}"
    echo -e "  ${BLUE}sudo switch-java${NC}      - Interactive menu"
    echo -e "  ${BLUE}sudo switch-java 17${NC}   - Switch to Java 17"
    echo -e "  ${BLUE}sudo switch-java 21${NC}   - Switch to Java 21"
    echo -e "  ${BLUE}sudo switch-java status${NC} - Show current version"
}

# Function to install on remote hosts
install_remote() {
    echo -e "${GREEN}=== Installing Java 17 & 21 on Remote Hosts ===${NC}\n"
    
    # Get remote hosts
    echo -e "${BLUE}Enter remote hosts (space-separated, e.g., user@host1 user@host2):${NC}"
    read -r REMOTE_HOSTS
    
    if [ -z "$REMOTE_HOSTS" ]; then
        echo -e "${RED}Error: No hosts specified${NC}"
        exit 1
    fi
    
    # Ask for SSH options
    echo -e "\n${BLUE}Do you want to use a specific SSH key? (leave empty for default)${NC}"
    read -r SSH_KEY
    
    SSH_OPTS=""
    if [ -n "$SSH_KEY" ]; then
        SSH_OPTS="-i $SSH_KEY"
    fi
    
    # Ask if parallel execution is desired
    echo -e "\n${BLUE}Install on all hosts in parallel? (y/n):${NC}"
    read -r PARALLEL
    
    # Process each host
    for HOST in $REMOTE_HOSTS; do
        if [ "$PARALLEL" = "y" ] || [ "$PARALLEL" = "Y" ]; then
            {
                echo -e "\n${YELLOW}[${HOST}] Starting installation...${NC}"
                ssh $SSH_OPTS -o StrictHostKeyChecking=no -t "$HOST" "sudo bash -c '$INSTALL_COMMANDS' && sudo update-alternatives --set java /usr/lib/jvm/temurin-21-jdk-amd64/bin/java && sudo update-alternatives --set javac /usr/lib/jvm/temurin-21-jdk-amd64/bin/javac" && \
                echo -e "${GREEN}[${HOST}] Installation completed successfully!${NC}" || \
                echo -e "${RED}[${HOST}] Installation failed!${NC}"
            } &
        else
            echo -e "\n${YELLOW}=== Installing on ${HOST} ===${NC}"
            ssh $SSH_OPTS -o StrictHostKeyChecking=no -t "$HOST" "sudo bash -c '$INSTALL_COMMANDS' && sudo update-alternatives --set java /usr/lib/jvm/temurin-21-jdk-amd64/bin/java && sudo update-alternatives --set javac /usr/lib/jvm/temurin-21-jdk-amd64/bin/javac" && \
            echo -e "${GREEN}[${HOST}] Installation completed successfully!${NC}" || \
            echo -e "${RED}[${HOST}] Installation failed!${NC}"
        fi
    done
    
    # Wait for all background jobs if parallel
    if [ "$PARALLEL" = "y" ] || [ "$PARALLEL" = "Y" ]; then
        wait
        echo -e "\n${GREEN}All installations completed!${NC}"
    fi
    
    echo -e "\n${YELLOW}On remote hosts, use: sudo switch-java${NC}"
}

# Function to install from hosts file
install_from_file() {
    echo -e "${GREEN}=== Installing Java 17 & 21 from Hosts File ===${NC}\n"
    
    echo -e "${BLUE}Enter path to hosts file (one host per line, format: user@hostname):${NC}"
    read -r HOSTS_FILE
    
    if [ ! -f "$HOSTS_FILE" ]; then
        echo -e "${RED}Error: File not found: $HOSTS_FILE${NC}"
        exit 1
    fi
    
    # Ask for SSH options
    echo -e "\n${BLUE}Do you want to use a specific SSH key? (leave empty for default)${NC}"
    read -r SSH_KEY
    
    SSH_OPTS=""
    if [ -n "$SSH_KEY" ]; then
        SSH_OPTS="-i $SSH_KEY"
    fi
    
    # Ask if parallel execution is desired
    echo -e "\n${BLUE}Install on all hosts in parallel? (y/n):${NC}"
    read -r PARALLEL
    
    # Process each host from file
    while IFS= read -r HOST; do
        # Skip empty lines and comments
        [[ -z "$HOST" || "$HOST" =~ ^[[:space:]]*# ]] && continue
        
        if [ "$PARALLEL" = "y" ] || [ "$PARALLEL" = "Y" ]; then
            {
                echo -e "\n${YELLOW}[${HOST}] Starting installation...${NC}"
                ssh $SSH_OPTS -o StrictHostKeyChecking=no -t "$HOST" "sudo bash -c '$INSTALL_COMMANDS' && sudo update-alternatives --set java /usr/lib/jvm/temurin-21-jdk-amd64/bin/java && sudo update-alternatives --set javac /usr/lib/jvm/temurin-21-jdk-amd64/bin/javac" && \
                echo -e "${GREEN}[${HOST}] Installation completed successfully!${NC}" || \
                echo -e "${RED}[${HOST}] Installation failed!${NC}"
            } &
        else
            echo -e "\n${YELLOW}=== Installing on ${HOST} ===${NC}"
            ssh $SSH_OPTS -o StrictHostKeyChecking=no -t "$HOST" "sudo bash -c '$INSTALL_COMMANDS' && sudo update-alternatives --set java /usr/lib/jvm/temurin-21-jdk-amd64/bin/java && sudo update-alternatives --set javac /usr/lib/jvm/temurin-21-jdk-amd64/bin/javac" && \
            echo -e "${GREEN}[${HOST}] Installation completed successfully!${NC}" || \
            echo -e "${RED}[${HOST}] Installation failed!${NC}"
        fi
    done < "$HOSTS_FILE"
    
    # Wait for all background jobs if parallel
    if [ "$PARALLEL" = "y" ] || [ "$PARALLEL" = "Y" ]; then
        wait
        echo -e "\n${GREEN}All installations completed!${NC}"
    fi
    
    echo -e "\n${YELLOW}On remote hosts, use: sudo switch-java${NC}"
}

# Function to install from MariaDB database (eliteel5_servers)
install_from_eliteel5_database() {
    echo -e "${GREEN}=== Installing Java 17 & 21 from EliteEL5 Servers Database ===${NC}\n"
    
    # Check if mysql/mariadb client is installed
    if ! command -v mysql &> /dev/null && ! command -v mariadb &> /dev/null; then
        echo -e "${YELLOW}MariaDB/MySQL client not found. Installing...${NC}"
        apt update && apt install -y mariadb-client || apt install -y default-mysql-client
    fi
    
    # Get database connection details
    echo -e "${BLUE}Enter MariaDB host (default: $DEFAULT_DB_HOST):${NC}"
    read -r DB_HOST
    DB_HOST=${DB_HOST:-$DEFAULT_DB_HOST}
    
    echo -e "${BLUE}Enter MariaDB port (default: $DEFAULT_DB_PORT):${NC}"
    read -r DB_PORT
    DB_PORT=${DB_PORT:-$DEFAULT_DB_PORT}
    
    echo -e "${BLUE}Enter database username:${NC}"
    read -r DB_USER
    
    echo -e "${BLUE}Enter database password:${NC}"
    read -s DB_PASS
    echo ""
    
    echo -e "\n${YELLOW}Checking if setup_eliteel5_servers procedure needs to be run...${NC}"
    
    # Check if eliteel5_servers database exists
    DB_EXISTS=$(mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -p"$DB_PASS" -e "SHOW DATABASES LIKE '$DEFAULT_SERVERS_DB';" 2>/dev/null | grep -c "$DEFAULT_SERVERS_DB" || true)
    
    if [ "$DB_EXISTS" -eq 0 ]; then
        echo -e "${YELLOW}Database $DEFAULT_SERVERS_DB not found. Running setup procedure from $DEFAULT_DB_NAME...${NC}"
        
        # Call the stored procedure from eliteel5_business database
        mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -p"$DB_PASS" -D "$DEFAULT_DB_NAME" -e "CALL setup_eliteel5_servers();" 2>&1
        
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}Setup procedure completed successfully!${NC}"
            echo -e "${GREEN}Created database: $DEFAULT_SERVERS_DB${NC}"
            echo -e "${GREEN}Created table: $DEFAULT_TABLE${NC}"
        else
            echo -e "${RED}Error running setup procedure.${NC}"
            exit 1
        fi
    else
        echo -e "${GREEN}Database $DEFAULT_SERVERS_DB already exists.${NC}"
    fi
    
    # Optional: Filter by additional criteria
    echo -e "\n${BLUE}Do you want to filter hosts? (y/n):${NC}"
    read -r USE_FILTER
    
    WHERE_CLAUSE=""
    if [ "$USE_FILTER" = "y" ] || [ "$USE_FILTER" = "Y" ]; then
        echo -e "${BLUE}Enter WHERE clause (e.g., environment='production' AND active=1):${NC}"
        echo -e "${YELLOW}Leave empty for all active hosts (active=1)${NC}"
        read -r FILTER
        if [ -z "$FILTER" ]; then
            WHERE_CLAUSE="WHERE active=1"
        else
            WHERE_CLAUSE="WHERE $FILTER"
        fi
    else
        WHERE_CLAUSE="WHERE active=1"
    fi
    
    # Query to get hosts from eliteel5_servers.servers table (NOT eliteel5_business)
    if [ -z "$WHERE_CLAUSE" ]; then
        QUERY="SELECT CONCAT(ssh_user, '@', ip_address) as connection FROM $DEFAULT_SERVERS_DB.$DEFAULT_TABLE;"
    else
        QUERY="SELECT CONCAT(ssh_user, '@', ip_address) as connection FROM $DEFAULT_SERVERS_DB.$DEFAULT_TABLE $WHERE_CLAUSE;"
    fi
    
    echo -e "\n${YELLOW}Fetching hosts from database...${NC}"
    echo -e "${BLUE}Executing query: $QUERY${NC}"
    
    # Execute query - NOTE: No -D flag here, we use fully qualified table name
    HOSTS=$(mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -p"$DB_PASS" -N -e "$QUERY" 2>&1)
    QUERY_EXIT_CODE=$?
    
    if [ $QUERY_EXIT_CODE -ne 0 ]; then
        echo -e "${RED}Error executing query (Exit code: $QUERY_EXIT_CODE):${NC}"
        echo "$HOSTS"
        exit 1
    fi
    
    if [ -z "$HOSTS" ]; then
        echo -e "${RED}No hosts found in database matching criteria${NC}"
        exit 1
    fi
    
    # Display found hosts
    echo -e "\n${GREEN}Found the following hosts:${NC}"
    echo "$HOSTS" | nl
    
    echo -e "\n${BLUE}Proceed with installation on these hosts? (y/n):${NC}"
    read -r CONFIRM
    
    if [ "$CONFIRM" != "y" ] && [ "$CONFIRM" != "Y" ]; then
        echo -e "${YELLOW}Installation cancelled${NC}"
        exit 0
    fi
    
    # Ask for SSH options
    echo -e "\n${BLUE}Do you want to use a specific SSH key? (leave empty for default)${NC}"
    read -r SSH_KEY
    
    SSH_OPTS=""
    if [ -n "$SSH_KEY" ]; then
        SSH_OPTS="-i $SSH_KEY"
    fi
    
    # Ask if parallel execution is desired
    echo -e "\n${BLUE}Install on all hosts in parallel? (y/n):${NC}"
    read -r PARALLEL
    
    # Convert hosts to array to avoid subshell issues
    mapfile -t HOST_ARRAY <<< "$HOSTS"
    
    # Process each host
    for HOST in "${HOST_ARRAY[@]}"; do
        # Skip empty lines
        [[ -z "$HOST" ]] && continue
        
        if [ "$PARALLEL" = "y" ] || [ "$PARALLEL" = "Y" ]; then
            {
                echo -e "\n${YELLOW}[${HOST}] Starting installation...${NC}"
                ssh $SSH_OPTS -o StrictHostKeyChecking=no -t "$HOST" "sudo bash -c '$INSTALL_COMMANDS' && sudo update-alternatives --set java /usr/lib/jvm/temurin-21-jdk-amd64/bin/java && sudo update-alternatives --set javac /usr/lib/jvm/temurin-21-jdk-amd64/bin/javac" && \
                echo -e "${GREEN}[${HOST}] Installation completed successfully!${NC}" || \
                echo -e "${RED}[${HOST}] Installation failed!${NC}"
            } &
        else
            echo -e "\n${YELLOW}=== Installing on ${HOST} ===${NC}"
            ssh $SSH_OPTS -o StrictHostKeyChecking=no -t "$HOST" "sudo bash -c '$INSTALL_COMMANDS' && sudo update-alternatives --set java /usr/lib/jvm/temurin-21-jdk-amd64/bin/java && sudo update-alternatives --set javac /usr/lib/jvm/temurin-21-jdk-amd64/bin/javac" && \
            echo -e "${GREEN}[${HOST}] Installation completed successfully!${NC}" || \
            echo -e "${RED}[${HOST}] Installation failed!${NC}"
        fi
    done
    
    # Wait for all background jobs if parallel
    if [ "$PARALLEL" = "y" ] || [ "$PARALLEL" = "Y" ]; then
        wait
        echo -e "\n${GREEN}All installations completed!${NC}"
    fi
    
    echo -e "\n${YELLOW}On remote hosts, use: sudo switch-java${NC}"
}

# Function to install from custom MariaDB/MySQL database
install_from_custom_database() {
    echo -e "${GREEN}=== Installing Java 17 & 21 from Custom Database ===${NC}\n"
    
    # Check if mysql/mariadb client is installed
    if ! command -v mysql &> /dev/null && ! command -v mariadb &> /dev/null; then
        echo -e "${YELLOW}MariaDB/MySQL client not found. Installing...${NC}"
        apt update && apt install -y mariadb-client || apt install -y default-mysql-client
    fi
    
    # Get database connection details
    echo -e "${BLUE}Enter database host (e.g., localhost or IP):${NC}"
    read -r DB_HOST
    
    echo -e "${BLUE}Enter database port (default: 3306):${NC}"
    read -r DB_PORT
    DB_PORT=${DB_PORT:-3306}
    
    echo -e "${BLUE}Enter database name:${NC}"
    read -r DB_NAME
    
    echo -e "${BLUE}Enter database username:${NC}"
    read -r DB_USER
    
    echo -e "${BLUE}Enter database password:${NC}"
    read -s DB_PASS
    echo ""
    
    echo -e "${BLUE}Enter table name containing host information:${NC}"
    read -r DB_TABLE
    
    echo -e "${BLUE}Enter column name for SSH user (e.g., ssh_user):${NC}"
    read -r COL_USER
    
    echo -e "${BLUE}Enter column name for hostname/IP (e.g., hostname or ip_address):${NC}"
    read -r COL_HOST
    
    # Optional: Filter by additional criteria
    echo -e "\n${BLUE}Do you want to filter hosts? (y/n):${NC}"
    read -r USE_FILTER
    
    WHERE_CLAUSE=""
    if [ "$USE_FILTER" = "y" ] || [ "$USE_FILTER" = "Y" ]; then
        echo -e "${BLUE}Enter WHERE clause (e.g., environment='production' AND active=1):${NC}"
        read -r FILTER
        if [ -n "$FILTER" ]; then
            WHERE_CLAUSE="WHERE $FILTER"
        fi
    fi
    
    # Query to get hosts
    if [ -z "$WHERE_CLAUSE" ]; then
        QUERY="SELECT CONCAT($COL_USER, '@', $COL_HOST) as connection FROM $DB_TABLE;"
    else
        QUERY="SELECT CONCAT($COL_USER, '@', $COL_HOST) as connection FROM $DB_TABLE $WHERE_CLAUSE;"
    fi
    
    echo -e "\n${YELLOW}Fetching hosts from database...${NC}"
    echo -e "${BLUE}Executing query: $QUERY${NC}"
    
    # Execute query and get results
    HOSTS=$(mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -p"$DB_PASS" -D "$DB_NAME" -N -e "$QUERY" 2>&1)
    QUERY_EXIT_CODE=$?
    
    if [ $QUERY_EXIT_CODE -ne 0 ]; then
        echo -e "${RED}Error connecting to database or executing query (Exit code: $QUERY_EXIT_CODE):${NC}"
        echo "$HOSTS"
        exit 1
    fi
    
    if [ -z "$HOSTS" ]; then
        echo -e "${RED}No hosts found in database matching criteria${NC}"
        exit 1
    fi
    
    # Display found hosts
    echo -e "\n${GREEN}Found the following hosts:${NC}"
    echo "$HOSTS" | nl
    
    echo -e "\n${BLUE}Proceed with installation on these hosts? (y/n):${NC}"
    read -r CONFIRM
    
    if [ "$CONFIRM" != "y" ] && [ "$CONFIRM" != "Y" ]; then
        echo -e "${YELLOW}Installation cancelled${NC}"
        exit 0
    fi
    
    # Ask for SSH options
    echo -e "\n${BLUE}Do you want to use a specific SSH key? (leave empty for default)${NC}"
    read -r SSH_KEY
    
    SSH_OPTS=""
    if [ -n "$SSH_KEY" ]; then
        SSH_OPTS="-i $SSH_KEY"
    fi
    
    # Ask if parallel execution is desired
    echo -e "\n${BLUE}Install on all hosts in parallel? (y/n):${NC}"
    read -r PARALLEL
    
    # Convert hosts to array to avoid subshell issues
    mapfile -t HOST_ARRAY <<< "$HOSTS"
    
    # Process each host
    for HOST in "${HOST_ARRAY[@]}"; do
        # Skip empty lines
        [[ -z "$HOST" ]] && continue
        
        if [ "$PARALLEL" = "y" ] || [ "$PARALLEL" = "Y" ]; then
            {
                echo -e "\n${YELLOW}[${HOST}] Starting installation...${NC}"
                ssh $SSH_OPTS -o StrictHostKeyChecking=no -t "$HOST" "sudo bash -c '$INSTALL_COMMANDS' && sudo update-alternatives --set java /usr/lib/jvm/temurin-21-jdk-amd64/bin/java && sudo update-alternatives --set javac /usr/lib/jvm/temurin-21-jdk-amd64/bin/javac" && \
                echo -e "${GREEN}[${HOST}] Installation completed successfully!${NC}" || \
                echo -e "${RED}[${HOST}] Installation failed!${NC}"
            } &
        else
            echo -e "\n${YELLOW}=== Installing on ${HOST} ===${NC}"
            ssh $SSH_OPTS -o StrictHostKeyChecking=no -t "$HOST" "sudo bash -c '$INSTALL_COMMANDS' && sudo update-alternatives --set java /usr/lib/jvm/temurin-21-jdk-amd64/bin/java && sudo update-alternatives --set javac /usr/lib/jvm/temurin-21-jdk-amd64/bin/javac" && \
            echo -e "${GREEN}[${HOST}] Installation completed successfully!${NC}" || \
            echo -e "${RED}[${HOST}] Installation failed!${NC}"
        fi
    done
    
    # Wait for all background jobs if parallel
    if [ "$PARALLEL" = "y" ] || [ "$PARALLEL" = "Y" ]; then
        wait
        echo -e "\n${GREEN}All installations completed!${NC}"
    fi
    
    echo -e "\n${YELLOW}On remote hosts, use: sudo switch-java${NC}"
}

# Function to switch Java version on local machine
switch_java_local() {
    if [ "$EUID" -ne 0 ]; then 
        echo -e "${RED}Error: This operation requires root or sudo privileges${NC}"
        exit 1
    fi
    
    if [ ! -f "/usr/local/bin/switch-java" ]; then
        echo -e "${RED}Error: switch-java command not found. Please install Java first (option 1).${NC}"
        exit 1
    fi
    
    /usr/local/bin/switch-java
}

# Main menu
show_menu() {
    echo -e "${BLUE}╔════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║   Java 17/21 Installation - Debian 12      ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════╝${NC}\n"
    echo -e "${YELLOW}1)${NC} Install on local machine"
    echo -e "${YELLOW}2)${NC} Install on remote hosts (manual entry)"
    echo -e "${YELLOW}3)${NC} Install on remote hosts (from file)"
    echo -e "${YELLOW}4)${NC} Install on remote hosts (EliteEL5 database)"
    echo -e "${YELLOW}5)${NC} Install on remote hosts (custom database)"
    echo -e "${YELLOW}6)${NC} Switch Java version (local)"
    echo -e "${YELLOW}7)${NC} Exit\n"
    echo -e "${BLUE}Select an option (1-7):${NC} "
}

# Main script execution
main() {
    while true; do
        show_menu
        read -r CHOICE
        
        case $CHOICE in
            1)
                install_local
                break
                ;;
            2)
                install_remote
                break
                ;;
            3)
                install_from_file
                break
                ;;
            4)
                install_from_eliteel5_database
                break
                ;;
            5)
                install_from_custom_database
                break
                ;;
            6)
                switch_java_local
                break
                ;;
            7)
                echo -e "${GREEN}Exiting...${NC}"
                exit 0
                ;;
            *)
                echo -e "${RED}Invalid option. Please select 1-7.${NC}\n"
                ;;
        esac
    done
}

# Run main function
main
