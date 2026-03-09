#!/bin/bash
set -e
echo "=== Setting up enable_remote_mysql task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Ensure MariaDB is running
if ! systemctl is-active --quiet mariadb; then
    echo "Starting MariaDB..."
    systemctl start mariadb
fi

# 2. Reset MariaDB Bind Address to 127.0.0.1 (Restrictive State)
# Common location for bind-address in Debian/Ubuntu
CNF_FILE=$(grep -l "bind-address" /etc/mysql/mariadb.conf.d/*.cnf /etc/mysql/*.cnf 2>/dev/null | head -1)

if [ -z "$CNF_FILE" ]; then
    # Fallback if not found
    CNF_FILE="/etc/mysql/mariadb.conf.d/50-server.cnf"
fi

echo "Configuring bind-address in $CNF_FILE..."
# Ensure bind-address is set to 127.0.0.1
if grep -q "^bind-address" "$CNF_FILE"; then
    sed -i 's/^bind-address.*/bind-address = 127.0.0.1/' "$CNF_FILE"
else
    # Insert under [mysqld] if not present (simplified approach, assuming [mysqld] exists)
    if grep -q "\[mysqld\]" "$CNF_FILE"; then
        sed -i '/\[mysqld\]/a bind-address = 127.0.0.1' "$CNF_FILE"
    else
        echo "[mysqld]" >> "$CNF_FILE"
        echo "bind-address = 127.0.0.1" >> "$CNF_FILE"
    fi
fi

# Restart to apply restrictive setting
systemctl restart mariadb
sleep 2

# 3. Ensure 'acmecorp' user exists but remove specific remote access
echo "Resetting database permissions..."
# Ensure user exists for localhost (standard setup)
virtualmin_db_query "CREATE USER IF NOT EXISTS 'acmecorp'@'localhost' IDENTIFIED BY 'password';"
# Remove the target remote permission if it exists from previous run
virtualmin_db_query "DROP USER IF EXISTS 'acmecorp'@'192.168.100.55';"
virtualmin_db_query "FLUSH PRIVILEGES;"

# 4. Launch Virtualmin/Firefox
ensure_virtualmin_ready

# Navigate to a neutral starting page (e.g., System Information dashboard)
navigate_to "https://localhost:10000/sysinfo.cgi"
sleep 5

# 5. Capture Initial State Evidence
echo "Capturing initial state..."
# Capture netstat output to prove it's listening on localhost only
netstat -plnt | grep 3306 > /tmp/initial_netstat.txt
# Capture user list
virtualmin_db_query "SELECT User, Host FROM mysql.user WHERE User='acmecorp';" > /tmp/initial_db_users.txt

take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="