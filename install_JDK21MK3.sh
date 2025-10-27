#!/bin/bash

# ===============================================================
# manage_JDK21MK3.sh
# ---------------------------------------------------------------
# Comprehensive Java 21 management script
# - Install or uninstall Java 21 locally or remotely
# - Verify database configuration and tables
# - SSH key management
# - Check Java status across systems
# ===============================================================

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Database defaults
DEFAULT_DB_HOST="localhost"
DEFAULT_DB_PORT="3306"
DEFAULT_DB_NAME="eliteel5_business"
DEFAULT_SERVERS_DB="user_servers"
DEFAULT_TABLE="servers"

# Trap errors with context
trap 'echo -e "${RED}❌ Error on line $LINENO. Exit code: $?${NC}" >&2' ERR

# Check if package is installed
is_package_installed() {
    local package="$1"
    if dpkg -l 2>/dev/null | grep -q "^ii.*$package"; then
        return 0
    fi
    return 1
}

# ----------------------------
# 🔐 SSH Key Management
# ----------------------------

create_ssh_key() {
    echo -e "${GREEN}=== SSH Key Creation ===${NC}\n"
    
    local key_name=""
    local key_path=""
    local key_comment=""
    
    echo -e "${BLUE}Enter SSH key name (default: id_rsa):${NC}"
    read -r key_name
    key_name=${key_name:-id_rsa}
    
    key_path="$HOME/.ssh/$key_name"
    
    if [ -f "$key_path" ]; then
        echo -e "${YELLOW}SSH key already exists at: $key_path${NC}"
        echo -e "${BLUE}Overwrite existing key? (y/N):${NC} "
        read -r OVERWRITE
        if [[ ! "$OVERWRITE" =~ ^[Yy]$ ]]; then
            echo -e "${YELLOW}Key creation cancelled${NC}"
            return 0
        fi
    fi
    
    mkdir -p "$HOME/.ssh"
    chmod 700 "$HOME/.ssh"
    
    echo -e "${BLUE}Enter key comment/description (optional, e.g., user@hostname):${NC}"
    read -r key_comment
    
    echo -e "${YELLOW}Generating SSH key pair...${NC}"
    
    if [ -z "$key_comment" ]; then
        ssh-keygen -t ed25519 -f "$key_path" -N "" -C "$key_name"
    else
        ssh-keygen -t ed25519 -f "$key_path" -N "" -C "$key_comment"
    fi
    
    chmod 600 "$key_path"
    chmod 644 "${key_path}.pub"
    
    echo -e "\n${GREEN}✓ SSH key pair created successfully!${NC}\n"
    echo -e "${BLUE}Key Details:${NC}"
    echo -e "  Private key: ${YELLOW}$key_path${NC}"
    echo -e "  Public key:  ${YELLOW}${key_path}.pub${NC}"
    
    echo -e "\n${BLUE}Key Fingerprint (SHA256):${NC}"
    ssh-keygen -l -f "${key_path}.pub"
    
    echo -e "\n${BLUE}Public Key Content:${NC}"
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    cat "${key_path}.pub"
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    
    echo -e "\n${BLUE}Add key to ssh-agent? (y/N):${NC} "
    read -r ADD_TO_AGENT
    
    if [[ "$ADD_TO_AGENT" =~ ^[Yy]$ ]]; then
        if pgrep -u "$USER" ssh-agent > /dev/null; then
            ssh-add "$key_path"
            echo -e "${GREEN}✓ Key added to ssh-agent${NC}"
        else
            eval "$(ssh-agent -s)"
            ssh-add "$key_path"
            echo -e "${GREEN}✓ ssh-agent started and key added${NC}"
        fi
    fi
}

display_ssh_keys() {
    echo -e "${GREEN}=== Available SSH Keys ===${NC}\n"
    
    if [ ! -d "$HOME/.ssh" ]; then
        echo -e "${YELLOW}No .ssh directory found${NC}"
        return 1
    fi
    
    local key_count=0
    
    for key_file in "$HOME/.ssh"/id_*; do
        if [[ "$key_file" == *.pub || "$key_file" == *config* || "$key_file" == *known_hosts* ]]; then
            continue
        fi
        
        if [ -f "$key_file" ]; then
            ((key_count++))
            echo -e "${BLUE}Key $key_count: $(basename "$key_file")${NC}"
            echo -e "  Path: ${YELLOW}$key_file${NC}"
            
            if [ -f "${key_file}.pub" ]; then
                echo -e "  Fingerprint: $(ssh-keygen -l -f "${key_file}.pub" 2>/dev/null | awk '{print $2}')"
            fi
            
            local key_type=$(head -1 "$key_file" | grep -o "RSA\|OPENSSH\|EC\|DSA" || echo "Unknown")
            echo -e "  Type: $key_type"
            echo ""
        fi
    done
    
    if [ $key_count -eq 0 ]; then
        echo -e "${YELLOW}No SSH keys found in $HOME/.ssh${NC}"
        return 1
    fi
}

manage_ssh_keys_menu() {
    while true; do
        echo -e "\n${BLUE}╔═══════════════════════════════════════════╗${NC}"
        echo -e "${BLUE}║      SSH Key Management                  ║${NC}"
        echo -e "${BLUE}╚═══════════════════════════════════════════╝${NC}\n"
        
        echo -e "${YELLOW}1)${NC} Create new SSH key pair"
        echo -e "${YELLOW}2)${NC} Display available SSH keys"
        echo -e "${YELLOW}3)${NC} Return to main menu\n"
        echo -e "${BLUE}Select an option (1-3):${NC} "
        
        read -r SSH_CHOICE
        
        case $SSH_CHOICE in
            1) create_ssh_key ;;
            2) display_ssh_keys ;;
            3) return ;;
            *) echo -e "${RED}Invalid option. Please select 1-3.${NC}\n" ;;
        esac
    done
}

# ----------------------------
# 📊 Status Check Functions
# ----------------------------

check_java_local() {
    echo -e "${BLUE}Checking Java 21 installation status...${NC}\n"
    
    if is_package_installed "temurin-21-jdk"; then
        echo -e "${GREEN}✓ Java 21 (temurin-21-jdk) is installed${NC}"
        
        if command -v java &>/dev/null; then
            echo -e "\n${BLUE}Current Java version:${NC}"
            java -version 2>&1 || true
        fi
        return 0
    else
        echo -e "${YELLOW}✗ Java 21 is not installed${NC}"
        return 1
    fi
}

check_java_remote() {
    local host="$1"
    local ssh_opts="${2:-}"
    
    echo -e "${YELLOW}Checking Java on ${host}...${NC}"
    
    ssh $ssh_opts -o StrictHostKeyChecking=no "$host" "
        if dpkg -l 2>/dev/null | grep -q 'temurin-21-jdk'; then
            echo -e '${GREEN}✓ Java 21 installed${NC}'
        else
            echo -e '${YELLOW}✗ Java 21 not installed${NC}'
        fi
        
        if command -v java &>/dev/null; then
            echo -e '${BLUE}Current version:${NC}'
            java -version 2>&1
        fi
    " 2>/dev/null || echo -e "${RED}Failed to check ${host}${NC}"
}

# ----------------------------
# 💾 Database Functions
# ----------------------------

verify_db_connection() {
    local host="$1"
    local port="$2"
    local user="$3"
    local pass="$4"
    
    echo -e "${YELLOW}Verifying database connection...${NC}"
    
    if command -v mariadb &>/dev/null; then
        if mariadb -h "$host" -P "$port" -u "$user" -p"$pass" -e "SELECT 1;" &>/dev/null; then
            echo -e "${GREEN}✓ Database connection successful${NC}"
            return 0
        fi
    elif command -v mysql &>/dev/null; then
        if mysql -h "$host" -P "$port" -u "$user" -p"$pass" -e "SELECT 1;" &>/dev/null; then
            echo -e "${GREEN}✓ Database connection successful${NC}"
            return 0
        fi
    fi
    
    echo -e "${RED}✗ Database connection failed${NC}"
    return 1
}

verify_db_tables() {
    local host="$1"
    local port="$2"
    local user="$3"
    local pass="$4"
    local db="$5"
    local table="$6"
    
    echo -e "${BLUE}Verifying database tables...${NC}\n"
    
    local cmd="mysql"
    if command -v mariadb &>/dev/null; then
        cmd="mariadb"
    fi
    
    local db_exists
    db_exists=$($cmd -h "$host" -P "$port" -u "$user" -p"$pass" -N -e "SHOW DATABASES LIKE '$db';" 2>/dev/null | grep -c "^$db$" || echo "0")
    
    if [ "$db_exists" -eq 0 ]; then
        echo -e "${RED}✗ Database '$db' does not exist${NC}"
        return 1
    fi
    
    echo -e "${GREEN}✓ Database '$db' exists${NC}"
    
    local table_exists
    table_exists=$($cmd -h "$host" -P "$port" -u "$user" -p"$pass" -D "$db" -N -e "SHOW TABLES LIKE '$table';" 2>/dev/null | grep -c "^$table$" || echo "0")
    
    if [ "$table_exists" -eq 0 ]; then
        echo -e "${RED}✗ Table '$table' does not exist in database '$db'${NC}"
        return 1
    fi
    
    echo -e "${GREEN}✓ Table '$table' exists in database '$db'${NC}"
    
    echo -e "\n${BLUE}Table structure:${NC}"
    $cmd -h "$host" -P "$port" -u "$user" -p"$pass" -D "$db" -e "DESCRIBE $table;" 2>/dev/null || true
    
    echo -e "\n${BLUE}Record count:${NC}"
    local record_count
    record_count=$($cmd -h "$host" -P "$port" -u "$user" -p"$pass" -D "$db" -N -e "SELECT COUNT(*) FROM $table;" 2>/dev/null || echo "0")
    echo -e "${GREEN}$record_count records in '$table'${NC}"
}

verify_database_config() {
    echo -e "${GREEN}=== Verifying Database Configuration ===${NC}\n"
    
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
    
    if ! command -v mysql &> /dev/null && ! command -v mariadb &> /dev/null; then
        echo -e "${YELLOW}Installing MariaDB client...${NC}"
        apt update && apt install -y mariadb-client || apt install -y default-mysql-client
    fi
    
    if ! verify_db_connection "$DB_HOST" "$DB_PORT" "$DB_USER" "$DB_PASS"; then
        echo -e "${RED}Cannot proceed without database connection${NC}"
        return 1
    fi
    
    echo -e "\n${BLUE}Select database configuration to verify:${NC}"
    echo -e "${YELLOW}1)${NC} EliteEL5 defaults ($DEFAULT_SERVERS_DB / $DEFAULT_TABLE)"
    echo -e "${YELLOW}2)${NC} Custom database configuration"
    read -r CONFIG_CHOICE
    
    if [ "$CONFIG_CHOICE" = "1" ]; then
        verify_db_tables "$DB_HOST" "$DB_PORT" "$DB_USER" "$DB_PASS" "$DEFAULT_SERVERS_DB" "$DEFAULT_TABLE"
    elif [ "$CONFIG_CHOICE" = "2" ]; then
        echo -e "${BLUE}Enter database name:${NC}"
        read -r CUSTOM_DB
        echo -e "${BLUE}Enter table name:${NC}"
        read -r CUSTOM_TABLE
        verify_db_tables "$DB_HOST" "$DB_PORT" "$DB_USER" "$DB_PASS" "$CUSTOM_DB" "$CUSTOM_TABLE"
    else
        echo -e "${RED}Invalid selection${NC}"
        return 1
    fi
}

check_status_from_database() {
    echo -e "${GREEN}=== Checking Java Status from Database ===${NC}\n"
    
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
    
    if ! verify_db_connection "$DB_HOST" "$DB_PORT" "$DB_USER" "$DB_PASS"; then
        return 1
    fi
    
    echo -e "\n${BLUE}Enter database name (default: $DEFAULT_SERVERS_DB):${NC}"
    read -r DB_NAME
    DB_NAME=${DB_NAME:-$DEFAULT_SERVERS_DB}
    
    echo -e "${BLUE}Enter table name (default: $DEFAULT_TABLE):${NC}"
    read -r TABLE_NAME
    TABLE_NAME=${TABLE_NAME:-$DEFAULT_TABLE}
    
    local cmd="mysql"
    if command -v mariadb &>/dev/null; then
        cmd="mariadb"
    fi
    
    local hosts
    hosts=$($cmd -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -p"$DB_PASS" -D "$DB_NAME" -N -e \
        "SELECT CONCAT(ssh_user, '@', ip_address) FROM $TABLE_NAME WHERE active=1;" 2>/dev/null || echo "")
    
    if [ -z "$hosts" ]; then
        echo -e "${RED}No active hosts found in database${NC}"
        return 1
    fi
    
    echo -e "\n${GREEN}Checking Java status on active hosts:${NC}\n"
    
    echo -e "${BLUE}Use specific SSH key? (leave empty for default)${NC}"
    read -r SSH_KEY
    
    local SSH_OPTS=""
    if [ -n "$SSH_KEY" ]; then
        SSH_OPTS="-i $SSH_KEY"
    fi
    
    echo -e "${BLUE}Check in parallel? (y/n):${NC}"
    read -r PARALLEL
    
    while IFS= read -r HOST; do
        [[ -z "$HOST" ]] && continue
        
        if [ "$PARALLEL" = "y" ] || [ "$PARALLEL" = "Y" ]; then
            { check_java_remote "$HOST" "$SSH_OPTS"; } &
        else
            check_java_remote "$HOST" "$SSH_OPTS"
        fi
    done <<< "$hosts"
    
    if [ "$PARALLEL" = "y" ] || [ "$PARALLEL" = "Y" ]; then
        wait
    fi
}

# ----------------------------
# ⬆️ INSTALLATION FUNCTIONS
# ----------------------------

install_java_local() {
    if [ "$EUID" -ne 0 ]; then
        echo -e "${RED}Error: This operation requires root privileges${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}=== Installing Java 21 Locally ===${NC}\n"
    
    if is_package_installed "temurin-21-jdk"; then
        echo -e "${YELLOW}Java 21 is already installed${NC}"
        check_java_local
        return 0
    fi
    
    echo -e "${YELLOW}Step 1: Updating package list...${NC}"
    apt update -y
    
    echo -e "${YELLOW}Step 2: Installing prerequisites...${NC}"
    apt install -y wget apt-transport-https gpg
    
    echo -e "${YELLOW}Step 3: Adding Adoptium GPG key...${NC}"
    wget -qO - https://packages.adoptium.net/artifactory/api/gpg/key/public | gpg --dearmor | tee /etc/apt/trusted.gpg.d/adoptium.gpg > /dev/null
    
    echo -e "${YELLOW}Step 4: Adding Adoptium repository...${NC}"
    local CODENAME=$(awk -F= "/^VERSION_CODENAME/{print\$2}" /etc/os-release)
    echo "deb https://packages.adoptium.net/artifactory/deb ${CODENAME} main" | tee /etc/apt/sources.list.d/adoptium.list
    
    echo -e "${YELLOW}Step 5: Updating package list with new repository...${NC}"
    apt update -y
    
    echo -e "${YELLOW}Step 6: Installing Temurin JDK 21...${NC}"
    apt install -y temurin-21-jdk
    
    echo -e "${YELLOW}Step 7: Setting Java 21 as default...${NC}"
    update-alternatives --install /usr/bin/java java /usr/lib/jvm/temurin-21-jdk-amd64/bin/java 1
    update-alternatives --install /usr/bin/javac javac /usr/lib/jvm/temurin-21-jdk-amd64/bin/javac 1
    
    echo -e "\n${GREEN}✓ Java 21 installed successfully!${NC}\n"
    echo -e "${BLUE}Current Java version:${NC}"
    java -version
}

install_java_remote() {
    echo -e "${GREEN}=== Installing Java 21 on Remote Hosts ===${NC}\n"
    
    echo -e "${BLUE}Enter remote hosts (space-separated, e.g., user@host1 user@host2):${NC}"
    read -r REMOTE_HOSTS
    
    if [ -z "$REMOTE_HOSTS" ]; then
        echo -e "${RED}Error: No hosts specified${NC}"
        return 1
    fi
    
    echo -e "\n${BLUE}Do you want to use a specific SSH key? (leave empty for default)${NC}"
    read -r SSH_KEY
    
    local SSH_OPTS=""
    if [ -n "$SSH_KEY" ]; then
        SSH_OPTS="-i $SSH_KEY"
    fi
    
    echo -e "\n${BLUE}Install on all hosts in parallel? (y/n):${NC}"
    read -r PARALLEL
    
    local INSTALL_CMD='
set -e
if ! dpkg -l 2>/dev/null | grep -q "temurin-21-jdk"; then
    echo -e "\033[1;33mInstalling Java 21...\033[0m"
    sudo apt update -y
    sudo apt install -y wget apt-transport-https gpg
    wget -qO - https://packages.adoptium.net/artifactory/api/gpg/key/public | gpg --dearmor | sudo tee /etc/apt/trusted.gpg.d/adoptium.gpg > /dev/null
    CODENAME=$(awk -F= "/^VERSION_CODENAME/{print\$2}" /etc/os-release)
    echo "deb https://packages.adoptium.net/artifactory/deb ${CODENAME} main" | sudo tee /etc/apt/sources.list.d/adoptium.list
    sudo apt update -y
    sudo apt install -y temurin-21-jdk
    sudo update-alternatives --install /usr/bin/java java /usr/lib/jvm/temurin-21-jdk-amd64/bin/java 1
    sudo update-alternatives --install /usr/bin/javac javac /usr/lib/jvm/temurin-21-jdk-amd64/bin/javac 1
    echo -e "\033[0;32m✓ Java 21 installed\033[0m"
else
    echo -e "\033[1;33m✓ Java 21 already installed\033[0m"
fi
java -version 2>&1
'
    
    for HOST in $REMOTE_HOSTS; do
        if [ "$PARALLEL" = "y" ] || [ "$PARALLEL" = "Y" ]; then
            {
                echo -e "\n${YELLOW}[${HOST}] Starting installation...${NC}"
                ssh $SSH_OPTS -o StrictHostKeyChecking=no -t "$HOST" "$INSTALL_CMD" && \
                echo -e "${GREEN}[${HOST}] Installation completed!${NC}" || \
                echo -e "${RED}[${HOST}] Installation failed!${NC}"
            } &
        else
            echo -e "\n${YELLOW}=== Installing on ${HOST} ===${NC}"
            ssh $SSH_OPTS -o StrictHostKeyChecking=no -t "$HOST" "$INSTALL_CMD"
        fi
    done
    
    if [ "$PARALLEL" = "y" ] || [ "$PARALLEL" = "Y" ]; then
        wait
        echo -e "\n${GREEN}All installations completed!${NC}"
    fi
}

install_from_file() {
    echo -e "${GREEN}=== Installing Java 21 from Hosts File ===${NC}\n"
    
    echo -e "${BLUE}Enter path to hosts file (one host per line, format: user@hostname):${NC}"
    read -r HOSTS_FILE
    
    if [ ! -f "$HOSTS_FILE" ]; then
        echo -e "${RED}Error: File not found: $HOSTS_FILE${NC}"
        return 1
    fi
    
    echo -e "\n${BLUE}Do you want to use a specific SSH key? (leave empty for default)${NC}"
    read -r SSH_KEY
    
    local SSH_OPTS=""
    if [ -n "$SSH_KEY" ]; then
        SSH_OPTS="-i $SSH_KEY"
    fi
    
    echo -e "\n${BLUE}Install on all hosts in parallel? (y/n):${NC}"
    read -r PARALLEL
    
    local INSTALL_CMD='
set -e
if ! dpkg -l 2>/dev/null | grep -q "temurin-21-jdk"; then
    echo -e "\033[1;33mInstalling Java 21...\033[0m"
    sudo apt update -y
    sudo apt install -y wget apt-transport-https gpg
    wget -qO - https://packages.adoptium.net/artifactory/api/gpg/key/public | gpg --dearmor | sudo tee /etc/apt/trusted.gpg.d/adoptium.gpg > /dev/null
    CODENAME=$(awk -F= "/^VERSION_CODENAME/{print\$2}" /etc/os-release)
    echo "deb https://packages.adoptium.net/artifactory/deb ${CODENAME} main" | sudo tee /etc/apt/sources.list.d/adoptium.list
    sudo apt update -y
    sudo apt install -y temurin-21-jdk
    sudo update-alternatives --install /usr/bin/java java /usr/lib/jvm/temurin-21-jdk-amd64/bin/java 1
    sudo update-alternatives --install /usr/bin/javac javac /usr/lib/jvm/temurin-21-jdk-amd64/bin/javac 1
    echo -e "\033[0;32m✓ Java 21 installed\033[0m"
else
    echo -e "\033[1;33m✓ Java 21 already installed\033[0m"
fi
'
    
    while IFS= read -r HOST; do
        [[ -z "$HOST" || "$HOST" =~ ^[[:space:]]*# ]] && continue
        
        if [ "$PARALLEL" = "y" ] || [ "$PARALLEL" = "Y" ]; then
            {
                echo -e "\n${YELLOW}[${HOST}] Starting installation...${NC}"
                ssh $SSH_OPTS -o StrictHostKeyChecking=no -t "$HOST" "$INSTALL_CMD" && \
                echo -e "${GREEN}[${HOST}] Success!${NC}" || \
                echo -e "${RED}[${HOST}] Failed!${NC}"
            } &
        else
            echo -e "\n${YELLOW}=== Installing on ${HOST} ===${NC}"
            ssh $SSH_OPTS -o StrictHostKeyChecking=no -t "$HOST" "$INSTALL_CMD"
        fi
    done < "$HOSTS_FILE"
    
    if [ "$PARALLEL" = "y" ] || [ "$PARALLEL" = "Y" ]; then
        wait
        echo -e "\n${GREEN}All installations completed!${NC}"
    fi
}

# ----------------------------
# ⬇️ UNINSTALL FUNCTIONS
# ----------------------------

uninstall_java_local() {
    if [ "$EUID" -ne 0 ]; then
        echo -e "${RED}Error: This operation requires root privileges${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}=== Uninstalling Java 21 Locally ===${NC}\n"
    
    if ! is_package_installed "temurin-21-jdk"; then
        echo -e "${YELLOW}Java 21 is not installed${NC}"
        return 0
    fi
    
    echo -e "${GREEN}✓ Java 21 (temurin-21-jdk) is installed${NC}"
    
    if command -v java &>/dev/null; then
        echo -e "\n${BLUE}Current Java version:${NC}"
        java -version 2>&1 || true
    fi
    
    echo -e "\n${RED}⚠️  WARNING: This will remove Java 21 (temurin-21-jdk)${NC}"
    echo -e "${BLUE}Proceed with uninstallation? (y/N):${NC} "
    read -r CONFIRM
    
    if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}Uninstallation cancelled${NC}"
        return 0
    fi
    
    echo -e "${YELLOW}Removing Java 21 package...${NC}"
    apt remove -y temurin-21-jdk
    apt autoremove -y
    
    if ! is_package_installed "temurin-17-jdk"; then
        if [ -f "/usr/local/bin/switch-java" ]; then
            echo -e "${YELLOW}Removing switch-java utility...${NC}"
            rm -f /usr/local/bin/switch-java
            echo -e "${GREEN}✓ Removed switch-java${NC}"
        fi
    else
        echo -e "${GREEN}Note: Java 17 is still installed, keeping switch-java utility${NC}"
    fi
    
    if ! is_package_installed "temurin-17-jdk"; then
        echo -e "${YELLOW}Cleaning up alternatives...${NC}"
        update-alternatives --remove-all java 2>/dev/null || true
        update-alternatives --remove-all javac 2>/dev/null || true
    fi
    
    echo -e "${GREEN}✓ Java 21 successfully uninstalled locally${NC}"
}

uninstall_java_remote() {
    echo -e "${GREEN}=== Uninstalling Java 21 from Remote Hosts ===${NC}\n"
    
    echo -e "${BLUE}Enter remote hosts (space-separated, e.g., user@host1 user@host2):${NC}"
    read -r REMOTE_HOSTS
    
    if [ -z "$REMOTE_HOSTS" ]; then
        echo -e "${RED}Error: No hosts specified${NC}"
        return 1
    fi
    
    echo -e "\n${BLUE}Do you want to use a specific SSH key? (leave empty for default)${NC}"
    read -r SSH_KEY
    
    local SSH_OPTS=""
    if [ -n "$SSH_KEY" ]; then
        SSH_OPTS="-i $SSH_KEY"
    fi
    
    echo -e "\n${BLUE}Uninstall on all hosts in parallel? (y/n):${NC}"
    read -r PARALLEL
    
    local UNINSTALL_CMD='
set -e
if dpkg -l 2>/dev/null | grep -q "temurin-21-jdk"; then
    echo -e "\033[1;33mRemoving Java 21 package...\033[0m"
    sudo apt remove -y temurin-21-jdk 2>/dev/null || true
    sudo apt autoremove -y
    
    if ! dpkg -l 2>/dev/null | grep -q "temurin-17-jdk"; then
        [ -f "/usr/local/bin/switch-java" ] && sudo rm -f /usr/local/bin/switch-java
        sudo update-alternatives --remove-all java 2>/dev/null || true
        sudo update-alternatives --remove-all javac 2>/dev/null || true
        echo -e "\033[0;32m✓ Java 21 uninstalled (no other Java versions present)\033[0m"
    else
        echo -e "\033[0;32m✓ Java 21 uninstalled (Java 17 remains)\033[0m"
    fi
else
    echo -e "\033[1;33m✗ Java 21 is not installed\033[0m"
fi
'
    
    for HOST in $REMOTE_HOSTS; do
        if [ "$PARALLEL" = "y" ] || [ "$PARALLEL" = "Y" ]; then
            {
                echo -e "\n${YELLOW}[${HOST}] Starting uninstallation...${NC}"
                ssh $SSH_OPTS -o StrictHostKeyChecking=no -t "$HOST" "$UNINSTALL_CMD" && \
                echo -e "${GREEN}[${HOST}] Uninstallation completed successfully!${NC}" || \
                echo -e "${RED}[${HOST}] Uninstallation failed!${NC}"
            } &
        else
            echo -e "\n${YELLOW}=== Uninstalling on ${HOST} ===${NC}"
            ssh $SSH_OPTS -o StrictHostKeyChecking=no -t "$HOST" "$UNINSTALL_CMD"
        fi
    done
    
    if [ "$PARALLEL" = "y" ] || [ "$PARALLEL" = "Y" ]; then
        wait
        echo -e "\n${GREEN}All uninstallations completed!${NC}"
    fi
}

uninstall_from_file() {
    echo -e "${GREEN}=== Uninstalling Java 21 from Hosts File ===${NC}\n"
    
    echo -e "${BLUE}Enter path to hosts file (one host per line, format: user@hostname):${NC}"
    read -r HOSTS_FILE
    
    if [ ! -f "$HOSTS_FILE" ]; then
        echo -e "${RED}Error: File not found: $HOSTS_FILE${NC}"
        return 1
    fi
    
    echo -e "\n${BLUE}Do you want to use a specific SSH key? (leave empty for default)${NC}"
    read -r SSH_KEY
    
    local SSH_OPTS=""
    if [ -n "$SSH_KEY" ]; then
        SSH_OPTS="-i $SSH_KEY"
    fi
    
    echo -e "\n${BLUE}Uninstall on all hosts in parallel? (y/n):${NC}"
    read -r PARALLEL
    
    local UNINSTALL_CMD='
set -e
if dpkg -l 2>/dev/null | grep -q "temurin-21-jdk"; then
    echo -e "\033[1;33mRemoving Java 21 package...\033[0m"
    sudo apt remove -y temurin-21-jdk 2>/dev/null || true
    sudo apt autoremove -y
    
    if ! dpkg -l 2>/dev/null | grep -q "temurin-17-jdk"; then
        [ -f "/usr/local/bin/switch-java" ] && sudo rm -f /usr/local/bin/switch-java
        sudo update-alternatives --remove-all java 2>/dev/null || true
        sudo update-alternatives --remove-all javac 2>/dev/null || true
        echo -e "\033[0;32m✓ Java 21 uninstalled\033[0m"
    else
        echo -e "\033[0;32m✓ Java 21 uninstalled (Java 17 remains)\033[0m"
    fi
else
    echo -e "\033[1;33m✗ Java 21 is not installed\033[0m"
fi
'
    
    while IFS= read -r HOST; do
        [[ -z "$HOST" || "$HOST" =~ ^[[:space:]]*# ]] && continue
        
        if [ "$PARALLEL" = "y" ] || [ "$PARALLEL" = "Y" ]; then
            {
                echo -e "\n${YELLOW}[${HOST}] Starting uninstallation...${NC}"
                ssh $SSH_OPTS -o StrictHostKeyChecking=no -t "$HOST" "$UNINSTALL_CMD" && \
                echo -e "${GREEN}[${HOST}] Success!${NC}" || \
                echo -e "${RED}[${HOST}] Failed!${NC}"
            } &
        else
            echo -e "\n${YELLOW}=== Uninstalling on ${HOST} ===${NC}"
            ssh $SSH_OPTS -o StrictHostKeyChecking=no -t "$HOST" "$UNINSTALL_CMD"
        fi
    done < "$HOSTS_FILE"
    
    if [ "$PARALLEL" = "y" ] || [ "$PARALLEL" = "Y" ]; then
        wait
        echo -e "\n${GREEN}All uninstallations completed!${NC}"
    fi
}

# ----------------------------
# 🎯 Main Menu
# ----------------------------

show_menu() {
    echo -e "${BLUE}╔═══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║        Java 21 Management Tool (Install/Uninstall)           ║${NC}"
    echo -e "${BLUE}╚═══════════════════════════════════════════════════════════════╝${NC}\n"
    
    echo -e "${GREEN}INSTALL JAVA 21:${NC}"
    echo -e "${YELLOW}1)${NC}  Install Java 21 locally"
    echo -e "${YELLOW}2)${NC}  Install Java 21 on remote hosts (manual entry)"
    echo -e "${YELLOW}3)${NC}  Install Java 21 on remote hosts (from file)"
    
    echo -e "\n${RED}UNINSTALL JAVA 21:${NC}"
    echo -e "${YELLOW}4)${NC}  Check/Uninstall Java 21 locally"
    echo -e "${YELLOW}5)${NC}  Uninstall Java 21 from remote hosts (manual entry)"
    echo -e "${YELLOW}6)${NC}  Uninstall Java 21 from remote hosts (from file)"
    
    echo -e "\n${BLUE}STATUS CHECK:${NC}"
    echo -e "${YELLOW}7)${NC}  Check Java 21 status locally"
    echo -e "${YELLOW}8)${NC}  Check Java 21 status on remote host"
    echo -e "${YELLOW}9)${NC}  Check Java status on database hosts"
    
    echo -e "\n${BLUE}DATABASE VERIFICATION:${NC}"
    echo -e "${YELLOW}10)${NC} Verify database configuration"
    
    echo -e "\n${BLUE}SSH KEY MANAGEMENT:${NC}"
    echo -e "${YELLOW}11)${NC} Create/Manage SSH keys"
    
    echo -e "\n${YELLOW}12)${NC} Exit\n"
    echo -e "${BLUE}Select an option (1-12):${NC} "
}

# Main execution
main() {
    while true; do
        show_menu
        read -r CHOICE
        
        case $CHOICE in
            1)
                if [ "$EUID" -eq 0 ]; then
                    install_java_local
                else
                    echo -e "${RED}Please run with sudo for local installation${NC}"
                fi
                break
                ;;
            2)
                install_java_remote
                break
                ;;
            3)
                install_from_file
                break
                ;;
            4)
                if [ "$EUID" -eq 0 ]; then
                    uninstall_java_local
                else
                    echo -e "${RED}Please run with sudo for local uninstallation${NC}"
                fi
                break
                ;;
            5)
                uninstall_java_remote
                break
                ;;
            6)
                uninstall_from_file
                break
                ;;
            7)
                check_java_local
                break
                ;;
            8)
                echo -e "${BLUE}Enter remote host (user@hostname):${NC}"
                read -r REMOTE_HOST
                
                echo -e "${BLUE}Use specific SSH key? (leave empty for default):${NC}"
                read -r SSH_KEY
                
                local SSH_OPTS=""
                if [ -n "$SSH_KEY" ]; then
                    SSH_OPTS="-i $SSH_KEY"
                fi
                
                check_java_remote "$REMOTE_HOST" "$SSH_OPTS"
                break
                ;;
            9)
                check_status_from_database
                break
                ;;
            10)
                verify_database_config
                break
                ;;
            11)
                manage_ssh_keys_menu
                ;;
            12)
                echo -e "${GREEN}Exiting...${NC}"
                exit 0
                ;;
            *)
                echo -e "${RED}Invalid option. Please select 1-12.${NC}\n"
                ;;
        esac
    done
}

# Run main function
main
