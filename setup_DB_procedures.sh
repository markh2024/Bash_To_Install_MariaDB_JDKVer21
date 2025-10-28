#!/bin/bash
# ===============================================================
# setup_DB_procedures.sh (Secure Version - Special Char Fixed)
# ---------------------------------------------------------------
# Automates setup of MariaDB, user creation, stored procedure
# database (DB_Procedures), and execution of a procedure that
# creates the user_servers DB and servers table.
#
# Security improvements:
# - Secure password handling (no command-line exposure)
# - Input validation
# - Principle of least privilege
# - Better error handling
# - Tests for existing users before attempting creation
# - FIXED: Handles special characters (including #) in passwords
# ===============================================================

set -euo pipefail  # Exit on error, undefined vars, pipe failures

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Trap errors with context
trap 'echo "❌ Error on line $LINENO. Exit code: $?" >&2' ERR

# ----------------------------
# 🛡️ Helper Functions
# ----------------------------

# Validate username format
validate_username() {
    local username="$1"
    if [[ ! "$username" =~ ^[a-zA-Z0-9_]+$ ]]; then
        echo "❌ Invalid username. Use only letters, numbers, and underscores."
        return 1
    fi
    if [ ${#username} -lt 3 ] || [ ${#username} -gt 32 ]; then
        echo "❌ Username must be 3-32 characters long."
        return 1
    fi
    return 0
}

# Validate password strength
validate_password() {
    local password="$1"
    if [ ${#password} -lt 8 ]; then
        echo "❌ Password must be at least 8 characters long."
        return 1
    fi
    return 0
}

# Escape SQL strings (particularly for passwords with special characters)
escape_sql_string() {
    local str="$1"
    # Escape backslashes first, then single quotes
    str="${str//\\/\\\\}"
    str="${str//\'/\'\'}"
    echo "$str"
}

# Create temporary credentials file
create_creds_file() {
    local user="$1"
    local pass="$2"
    local creds_file
    creds_file=$(mktemp)
    chmod 600 "$creds_file"
    # Quote the password value to handle special characters like #
    # In .my.cnf format, values with special chars should be quoted
    cat > "$creds_file" <<CREDS_EOF
[client]
user=$user
password="$pass"
CREDS_EOF
    echo "$creds_file"
}

# Test database connection with credentials file
test_db_connection() {
    local creds_file="$1"
    # Try mariadb first, then mysql as fallback
    if command -v mariadb &>/dev/null; then
        mariadb --defaults-extra-file="$creds_file" -e "SELECT 1;" &>/dev/null
    elif command -v mysql &>/dev/null; then
        mysql --defaults-extra-file="$creds_file" -e "SELECT 1;" &>/dev/null
    else
        return 1
    fi
}

# Execute SQL with credentials file (uses mariadb or mysql)
execute_sql() {
    local creds_file="$1"
    shift
    if command -v mariadb &>/dev/null; then
        mariadb --defaults-extra-file="$creds_file" "$@"
    elif command -v mysql &>/dev/null; then
        mysql --defaults-extra-file="$creds_file" "$@"
    else
        echo "❌ Neither mariadb nor mysql command found"
        return 1
    fi
}

# Cleanup function
cleanup() {
    if [ -n "${MYSQL_CREDS:-}" ] && [ -f "$MYSQL_CREDS" ]; then
        shred -u "$MYSQL_CREDS" 2>/dev/null || rm -f "$MYSQL_CREDS"
    fi
    if [ -n "${ROOT_CREDS:-}" ] && [ -f "$ROOT_CREDS" ]; then
        shred -u "$ROOT_CREDS" 2>/dev/null || rm -f "$ROOT_CREDS"
    fi
    # Clear password from memory
    unset NEW_PASS ESCAPED_PASS 2>/dev/null || true
}

trap cleanup EXIT

# ----------------------------
# 🗂️ Step 1: Create workspace
# ----------------------------
WORKDIR="$HOME/DB_bashscripts"
mkdir -p "$WORKDIR"
echo "📁 Workspace created (or already exists): $WORKDIR"

# Copy this script to the workspace if not already there
SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
SCRIPT_NAME="$(basename "$SCRIPT_PATH")"
DEST_SCRIPT="$WORKDIR/$SCRIPT_NAME"

if [ "$SCRIPT_PATH" != "$DEST_SCRIPT" ]; then
    echo "📋 Copying script to workspace..."
    cp "$SCRIPT_PATH" "$DEST_SCRIPT"
    chmod +x "$DEST_SCRIPT"
    echo "✅ Script copied to: $DEST_SCRIPT"
else
    echo "✔ Script already in workspace."
fi

# ----------------------------
# 🧩 Step 2: Check for MariaDB
# ----------------------------
if ! command -v mariadb &>/dev/null; then
    echo "📦 MariaDB not found — installing..."
    sudo apt update -y
    sudo apt install -y mariadb-server mariadb-client
    echo "✅ MariaDB installed successfully."
else
    echo "✔ MariaDB already installed."
fi

# ----------------------------
# 🔧 Step 3: Ensure MariaDB is running
# ----------------------------
if ! sudo systemctl is-active --quiet mariadb; then
    echo "🔄 Starting MariaDB service..."
    sudo systemctl start mariadb
    sudo systemctl enable mariadb
    echo "✅ MariaDB service started and enabled."
else
    echo "✔ MariaDB service is running."
fi

# ----------------------------
# 🔐 Step 3.5: Check/Set MariaDB root password
# ----------------------------
echo
echo "🔐 Checking MariaDB root authentication..."

# Test if root can connect without password (socket auth or no password)
ROOT_NO_PASS=false
if sudo mariadb -u root -e "SELECT 1;" &>/dev/null; then
    ROOT_NO_PASS=true
    echo "✔ Root can connect via socket authentication."
    
    # Check if root has a password set
    ROOT_HAS_PASS=$(sudo mariadb -u root -sse "SELECT IF(LENGTH(Password) > 0 OR LENGTH(authentication_string) > 0, 'yes', 'no') FROM mysql.user WHERE User='root' AND Host='localhost';" 2>/dev/null | head -1)
    
    if [ "$ROOT_HAS_PASS" = "no" ]; then
        echo "⚠️  MariaDB root user has no password set."
        echo
        read -p "Would you like to set a root password for MariaDB? (recommended) (y/N): " SET_ROOT_PASS
        
        if [[ "$SET_ROOT_PASS" =~ ^[Yy]$ ]]; then
            echo
            echo "💡 Tip: Many admins use the same password as the system root user for convenience."
            echo
            
            while true; do
                read -s -p "Enter new password for MariaDB root user: " MARIADB_ROOT_PASS
                echo
                read -s -p "Confirm password: " MARIADB_ROOT_PASS_CONFIRM
                echo
                
                if [ "$MARIADB_ROOT_PASS" != "$MARIADB_ROOT_PASS_CONFIRM" ]; then
                    echo "❌ Passwords do not match. Try again."
                    continue
                fi
                
                if validate_password "$MARIADB_ROOT_PASS"; then
                    break
                fi
            done
            unset MARIADB_ROOT_PASS_CONFIRM
            
            # Escape password for SQL
            ESCAPED_ROOT_PASS=$(escape_sql_string "$MARIADB_ROOT_PASS")
            
            # Set root password
            echo "🔧 Setting MariaDB root password..."
            {
                printf "ALTER USER 'root'@'localhost' IDENTIFIED BY '%s';\n" "$ESCAPED_ROOT_PASS"
                echo "FLUSH PRIVILEGES;"
            } | sudo mariadb -u root
            
            # Create root credentials file for future use
            ROOT_CREDS=$(create_creds_file "root" "$MARIADB_ROOT_PASS")
            unset MARIADB_ROOT_PASS ESCAPED_ROOT_PASS
            
            echo "✅ MariaDB root password has been set."
            echo "📝 Note: You can still use 'sudo mariadb' for socket authentication."
        else
            echo "⏭️  Skipping root password setup."
        fi
    else
        echo "✔ MariaDB root user has a password set."
    fi
else
    # Root cannot connect without password - need to prompt for it
    echo "🔑 MariaDB root requires password authentication."
    
    while true; do
        read -s -p "Enter MariaDB root password: " MARIADB_ROOT_PASS
        echo
        
        ROOT_CREDS=$(create_creds_file "root" "$MARIADB_ROOT_PASS")
        
        if test_db_connection "$ROOT_CREDS"; then
            echo "✓ Root password verified."
            break
        else
            shred -u "$ROOT_CREDS" 2>/dev/null || rm -f "$ROOT_CREDS"
            unset ROOT_CREDS
            echo "❌ Incorrect password. Please try again."
        fi
    done
    unset MARIADB_ROOT_PASS
    ROOT_NO_PASS=false
fi

# ----------------------------
# 🔐 Step 4: Get username and check if exists
# ----------------------------
echo
echo "📝 Database User Setup"
echo "──────────────────────────"

while true; do
    read -p "Enter database username: " NEW_USER
    if validate_username "$NEW_USER"; then
        break
    fi
done

# Escape username for SQL queries
ESCAPED_USER=$(escape_sql_string "$NEW_USER")

# Check if user already exists
USER_EXISTS_LOCAL=$(sudo mariadb -u root -sse "SELECT COUNT(*) FROM mysql.user WHERE User='$ESCAPED_USER' AND Host='localhost';" 2>/dev/null || echo "0")
USER_EXISTS_REMOTE=$(sudo mariadb -u root -sse "SELECT COUNT(*) FROM mysql.user WHERE User='$ESCAPED_USER' AND Host='%';" 2>/dev/null || echo "0")

CHANGE_PASSWORD="n"
if [ "$USER_EXISTS_LOCAL" -gt 0 ] || [ "$USER_EXISTS_REMOTE" -gt 0 ]; then
    echo "ℹ️  User '$NEW_USER' already exists."
    [ "$USER_EXISTS_LOCAL" -gt 0 ] && echo "   - Found: '$NEW_USER'@'localhost'"
    [ "$USER_EXISTS_REMOTE" -gt 0 ] && echo "   - Found: '$NEW_USER'@'%'"
    echo
    read -p "Do you want to change the password for this user? (y/N): " CHANGE_PASSWORD
    
    if [[ "$CHANGE_PASSWORD" =~ ^[Yy]$ ]]; then
        # Get new password
        while true; do
            read -s -p "Enter new password for $NEW_USER (min 8 chars): " NEW_PASS
            echo
            read -s -p "Confirm password: " NEW_PASS_CONFIRM
            echo
            
            if [ "$NEW_PASS" != "$NEW_PASS_CONFIRM" ]; then
                echo "❌ Passwords do not match. Try again."
                continue
            fi
            
            if validate_password "$NEW_PASS"; then
                break
            fi
        done
        unset NEW_PASS_CONFIRM
    else
        # User exists and not changing password - need current password for authentication
        while true; do
            read -s -p "Enter current password for $NEW_USER: " NEW_PASS
            echo
            
            # Verify the password works before proceeding
            TEST_CREDS=$(create_creds_file "$NEW_USER" "$NEW_PASS")
            
            if test_db_connection "$TEST_CREDS"; then
                shred -u "$TEST_CREDS" 2>/dev/null || rm -f "$TEST_CREDS"
                echo "✓ Password verified. Will keep existing password and update permissions."
                break
            else
                shred -u "$TEST_CREDS" 2>/dev/null || rm -f "$TEST_CREDS"
                echo "❌ Password incorrect. Please try again."
            fi
        done
    fi
else
    echo "➕ Creating new user '$NEW_USER'..."
    # Get password for new user
    while true; do
        read -s -p "Enter password for $NEW_USER (min 8 chars): " NEW_PASS
        echo
        read -s -p "Confirm password: " NEW_PASS_CONFIRM
        echo
        
        if [ "$NEW_PASS" != "$NEW_PASS_CONFIRM" ]; then
            echo "❌ Passwords do not match. Try again."
            continue
        fi
        
        if validate_password "$NEW_PASS"; then
            break
        fi
    done
    unset NEW_PASS_CONFIRM
fi

# Escape password for SQL (handles #, ', \, and other special characters)
ESCAPED_PASS=$(escape_sql_string "$NEW_PASS")

# ----------------------------
# 👤 Step 5: Setup DB user
# ----------------------------
echo
echo "👤 Setting up database user..."

# Determine how to connect as root
if [ "$ROOT_NO_PASS" = true ]; then
    # Use sudo for socket authentication
    MYSQL_ROOT_CMD="sudo mariadb -u root"
elif [ -n "${ROOT_CREDS:-}" ] && [ -f "$ROOT_CREDS" ]; then
    # Use credentials file
    if command -v mariadb &>/dev/null; then
        MYSQL_ROOT_CMD="mariadb --defaults-extra-file=$ROOT_CREDS"
    else
        MYSQL_ROOT_CMD="mysql --defaults-extra-file=$ROOT_CREDS"
    fi
else
    echo "❌ Cannot determine root authentication method."
    exit 1
fi

# Check if we can connect as root
if eval "$MYSQL_ROOT_CMD -e 'SELECT 1;'" &>/dev/null; then
    
    if [ "$USER_EXISTS_LOCAL" -gt 0 ] || [ "$USER_EXISTS_REMOTE" -gt 0 ]; then
        if [[ "$CHANGE_PASSWORD" =~ ^[Yy]$ ]]; then
            echo "📝 Updating password and permissions..."
            
            # Use printf to avoid heredoc issues with special characters
            {
                echo "-- Create databases first"
                echo "CREATE DATABASE IF NOT EXISTS DB_Procedures;"
                echo "CREATE DATABASE IF NOT EXISTS user_servers;"
                echo ""
                echo "-- Update password for existing users (both localhost and remote)"
                printf "ALTER USER IF EXISTS '%s'@'localhost' IDENTIFIED BY '%s';\n" "$ESCAPED_USER" "$ESCAPED_PASS"
                printf "ALTER USER IF EXISTS '%s'@'%%' IDENTIFIED BY '%s';\n" "$ESCAPED_USER" "$ESCAPED_PASS"
                echo ""
                echo "-- Create users if they don't exist"
                printf "CREATE USER IF NOT EXISTS '%s'@'localhost' IDENTIFIED BY '%s';\n" "$ESCAPED_USER" "$ESCAPED_PASS"
                printf "CREATE USER IF NOT EXISTS '%s'@'%%' IDENTIFIED BY '%s';\n" "$ESCAPED_USER" "$ESCAPED_PASS"
                echo ""
                echo "-- Grant all privileges on the specific databases"
                printf "GRANT ALL PRIVILEGES ON DB_Procedures.* TO '%s'@'localhost';\n" "$ESCAPED_USER"
                printf "GRANT ALL PRIVILEGES ON user_servers.* TO '%s'@'localhost';\n" "$ESCAPED_USER"
                printf "GRANT ALL PRIVILEGES ON DB_Procedures.* TO '%s'@'%%';\n" "$ESCAPED_USER"
                printf "GRANT ALL PRIVILEGES ON user_servers.* TO '%s'@'%%';\n" "$ESCAPED_USER"
                echo ""
                echo "-- Flush to ensure privileges take effect immediately"
                echo "FLUSH PRIVILEGES;"
            } | eval "$MYSQL_ROOT_CMD"
            
            echo "✅ User '$NEW_USER' password updated and privileges granted."
        else
            echo "📝 Updating permissions (keeping existing password)..."
            
            {
                echo "-- Create databases first"
                echo "CREATE DATABASE IF NOT EXISTS DB_Procedures;"
                echo "CREATE DATABASE IF NOT EXISTS user_servers;"
                echo ""
                echo "-- Grant all privileges on the specific databases (no password change)"
                printf "GRANT ALL PRIVILEGES ON DB_Procedures.* TO '%s'@'localhost';\n" "$ESCAPED_USER"
                printf "GRANT ALL PRIVILEGES ON user_servers.* TO '%s'@'localhost';\n" "$ESCAPED_USER"
                printf "GRANT ALL PRIVILEGES ON DB_Procedures.* TO '%s'@'%%';\n" "$ESCAPED_USER"
                printf "GRANT ALL PRIVILEGES ON user_servers.* TO '%s'@'%%';\n" "$ESCAPED_USER"
                echo ""
                echo "-- Flush to ensure privileges take effect immediately"
                echo "FLUSH PRIVILEGES;"
            } | eval "$MYSQL_ROOT_CMD"
            
            echo "✅ User '$NEW_USER' permissions updated (password unchanged)."
        fi
    else
        echo "➕ Creating new user '$NEW_USER' for local and remote access..."
        
        {
            echo "-- Create databases first"
            echo "CREATE DATABASE IF NOT EXISTS DB_Procedures;"
            echo "CREATE DATABASE IF NOT EXISTS user_servers;"
            echo ""
            echo "-- Create new user with password for both localhost and remote"
            printf "CREATE USER '%s'@'localhost' IDENTIFIED BY '%s';\n" "$ESCAPED_USER" "$ESCAPED_PASS"
            printf "CREATE USER '%s'@'%%' IDENTIFIED BY '%s';\n" "$ESCAPED_USER" "$ESCAPED_PASS"
            echo ""
            echo "-- Grant all privileges on the specific databases"
            printf "GRANT ALL PRIVILEGES ON DB_Procedures.* TO '%s'@'localhost';\n" "$ESCAPED_USER"
            printf "GRANT ALL PRIVILEGES ON user_servers.* TO '%s'@'localhost';\n" "$ESCAPED_USER"
            printf "GRANT ALL PRIVILEGES ON DB_Procedures.* TO '%s'@'%%';\n" "$ESCAPED_USER"
            printf "GRANT ALL PRIVILEGES ON user_servers.* TO '%s'@'%%';\n" "$ESCAPED_USER"
            echo ""
            echo "-- Flush to ensure privileges take effect immediately"
            echo "FLUSH PRIVILEGES;"
        } | sudo mariadb -u root
        
        echo "✅ User '$NEW_USER' created with appropriate privileges (local + remote)."
    fi
    
    # Verify the grants were applied
    echo "🔍 Verifying grants..."
    if [ "$USER_EXISTS_LOCAL" -gt 0 ] || [ -z "$USER_EXISTS_LOCAL" ]; then
        eval "$MYSQL_ROOT_CMD -e \"SHOW GRANTS FOR '$ESCAPED_USER'@'localhost';\"" 2>/dev/null || true
    fi
    if [ "$USER_EXISTS_REMOTE" -gt 0 ] || [ -z "$USER_EXISTS_REMOTE" ]; then
        eval "$MYSQL_ROOT_CMD -e \"SHOW GRANTS FOR '$ESCAPED_USER'@'%';\"" 2>/dev/null || true
    fi
else
    echo "⚠️  Cannot connect to MariaDB as root."
    echo "Please ensure MariaDB root authentication is properly configured."
    exit 1
fi

# Create secure credentials file for new user
MYSQL_CREDS=$(create_creds_file "$NEW_USER" "$NEW_PASS")

# Clear password from memory after credential file is created
unset ESCAPED_PASS

# ----------------------------
# 🧱 Step 6: Create procedures table
# ----------------------------
echo
echo "🧱 Creating procedures table in DB_Procedures..."

# Attempt to create table; if fails, show credentials file path for debugging
if ! execute_sql "$MYSQL_CREDS" DB_Procedures <<'MYSQL_SCRIPT'
CREATE TABLE IF NOT EXISTS procedures (
    id INT AUTO_INCREMENT PRIMARY KEY,
    procedure_name VARCHAR(255) NOT NULL UNIQUE,
    explanation TEXT,
    file_location VARCHAR(255),
    script_location CHAR(255),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    INDEX idx_procedure_name (procedure_name)
);
MYSQL_SCRIPT
then
    echo "❌ Failed to create procedures table."
    echo "🔍 Debug: The credentials file used is at:"
    echo "   $MYSQL_CREDS"
    echo "   (Contents: user and password, DO NOT SHARE publicly!)"
    exit 1
else
    echo "✅ Procedures table created in DB_Procedures."
fi


# ----------------------------
# ⚙️ Step 7: Create stored procedure
# ----------------------------
echo
echo "⚙️ Creating stored procedure 'setup_user_servers'..."

# First, save the procedure to a SQL file
PROCEDURE_FILE="$WORKDIR/setup_user_servers.sql"
cat > "$PROCEDURE_FILE" <<'SQL_CONTENT'
-- ================================================================
-- Stored Procedure: setup_user_servers
-- ================================================================
-- Purpose: Creates the user_servers database with a servers table
--          for tracking remote hosts/servers
-- 
-- Usage:   CALL setup_user_servers();
--
-- Note:    This will DROP and recreate the user_servers database
-- ================================================================

DELIMITER //

DROP PROCEDURE IF EXISTS setup_user_servers//

CREATE PROCEDURE setup_user_servers()
BEGIN
    -- Declare variables for error handling
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        -- Rollback on error
        ROLLBACK;
        -- Re-signal the error
        RESIGNAL;
    END;

    -- Start transaction
    START TRANSACTION;

    -- Step 1: Drop and recreate the user_servers database
    DROP DATABASE IF EXISTS user_servers;
    CREATE DATABASE user_servers;

    -- Step 2: Create the servers table
    CREATE TABLE user_servers.servers (
        id INT PRIMARY KEY AUTO_INCREMENT,
        ssh_user VARCHAR(50) NOT NULL,
        hostname VARCHAR(255) NOT NULL,
        ip_address VARCHAR(45) NOT NULL,
        environment ENUM('production', 'staging', 'development', 'testing') DEFAULT 'production',
        active BOOLEAN DEFAULT 1,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        UNIQUE KEY unique_host (hostname, ip_address),
        INDEX idx_environment (environment),
        INDEX idx_active (active)
    );

    -- Commit transaction
    COMMIT;
END //

DELIMITER ;
SQL_CONTENT

echo "💾 Stored procedure saved to: $PROCEDURE_FILE"

# Now execute the procedure creation from the file
execute_sql "$MYSQL_CREDS" DB_Procedures < "$PROCEDURE_FILE"

echo "✅ Stored procedure 'setup_user_servers' created in database."

# ----------------------------
# 📝 Step 8: Log procedure metadata
# ----------------------------
echo
echo "📝 Logging procedure metadata..."

# Escape the workdir path for SQL
ESCAPED_WORKDIR=$(escape_sql_string "$WORKDIR")
ESCAPED_SCRIPT_LOCATION=$(escape_sql_string "$PROCEDURE_FILE")

execute_sql "$MYSQL_CREDS" DB_Procedures <<EOF
INSERT INTO procedures (procedure_name, explanation, file_location, script_location)
VALUES (
    'setup_user_servers',
    'Creates a database (user_servers) with a servers table for remote host tracking. Includes error handling and constraints.',
    '$ESCAPED_WORKDIR/setup_DB_procedures.sh',
    '$ESCAPED_SCRIPT_LOCATION'
)
ON DUPLICATE KEY UPDATE
    explanation = VALUES(explanation),
    file_location = VALUES(file_location),
    script_location = VALUES(script_location);
EOF

echo "✅ Procedure metadata logged."

# ----------------------------
# 🚀 Step 9: Execute procedure
# ----------------------------
echo
echo "🚀 Executing procedure to create 'user_servers' database..."

if execute_sql "$MYSQL_CREDS" DB_Procedures -e "CALL setup_user_servers();"; then
    echo "✅ Procedure executed successfully."
else
    echo "❌ Procedure execution failed."
    exit 1
fi

# ----------------------------
# 🔍 Step 10: Verify results
# ----------------------------
echo
echo "🔎 Verifying database structure..."
echo
echo "Database: user_servers"
echo "Table: servers"
echo "──────────────────────────────────────────────────────────────"

execute_sql "$MYSQL_CREDS" -e "DESCRIBE user_servers.servers;"

echo
echo "──────────────────────────────────────────────────────────────"
echo "Stored Procedures in DB_Procedures:"
echo "──────────────────────────────────────────────────────────────"

execute_sql "$MYSQL_CREDS" -e "
SELECT routine_name, created 
FROM information_schema.routines 
WHERE routine_schema = 'DB_Procedures';"

# ----------------------------
# 🏁 Step 11: Completion message
# ----------------------------
echo
echo "🎉 Setup Complete!"
echo "════════════════════════════════════════════════════════════════"
echo
echo "📌 Next Steps:"
echo
echo "  1️⃣  Connect to MariaDB locally:"
echo "      mariadb -u $NEW_USER -p"
echo
echo "  2️⃣  Connect to MariaDB remotely:"
echo "      mariadb -h <server-ip> -u $NEW_USER -p"
echo "      Note: Ensure MariaDB is configured to accept remote connections"
echo "            Edit /etc/mysql/mariadb.conf.d/50-server.cnf"
echo "            Set: bind-address = 0.0.0.0"
echo "            Then: sudo systemctl restart mariadb"
echo
echo "  3️⃣  List databases:"
echo "      SHOW DATABASES;"
echo
echo "  4️⃣  Use the procedures database:"
echo "      USE DB_Procedures;"
echo
echo "  5️⃣  View available procedures:"
echo "      SELECT * FROM procedures;"
echo "      SHOW PROCEDURE STATUS WHERE Db='DB_Procedures';"
echo
echo "  5.5️⃣ Re-run a procedure from saved SQL file:"
echo "      mysql -u $NEW_USER -p DB_Procedures < $WORKDIR/setup_user_servers.sql"
echo
echo "  6️⃣  Add server information:"
echo "      USE user_servers;"
echo "      INSERT INTO servers (ssh_user, hostname, ip_address, environment)"
echo "      VALUES ('admin', 'web-server-01', '192.168.1.100', 'production');"
echo
echo "      Valid environment values: 'production', 'staging', 'development', 'testing'"
echo "      (Defaults to 'production' if not specified)"
echo
echo "  7️⃣  Query your servers:"
echo "      SELECT * FROM servers WHERE active = 1;"
echo "      SELECT * FROM servers WHERE environment = 'production';"
echo "      SELECT * FROM servers WHERE environment IN ('staging', 'development');"
echo
echo "════════════════════════════════════════════════════════════════"
echo "✅ All credentials have been securely handled and cleaned up."
echo
echo "📂 Files saved to $WORKDIR:"
echo "   - $(basename "$DEST_SCRIPT") (this setup script)"
echo "   - setup_user_servers.sql (stored procedure)"
echo
echo -e "${YELLOW}SCRIPTS MD HARRINGTON BEXLEYHEATH KENT LONDON {NC}"
echo -e "${YELLOW}Website https://eliteprojects.x10host.com {NC}"
echo -e "${GREEN}Instagram https://www.instagram.com/markukh2021/{NC}"
echo -e "${GREEN}FaceBook https://www.facebook.com/mark.harrington.14289/{NC}"
