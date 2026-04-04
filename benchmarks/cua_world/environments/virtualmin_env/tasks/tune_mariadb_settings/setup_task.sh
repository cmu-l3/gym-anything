#!/bin/bash
set -e
echo "=== Setting up tune_mariadb_settings task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Reset MariaDB to default state (remove any previous tuning)
echo "--- Resetting MariaDB config to defaults ---"

# Files where config might be stored
CONFIG_FILES=("/etc/mysql/mariadb.conf.d/50-server.cnf" "/etc/mysql/my.cnf" "/etc/mysql/mariadb.conf.d/50-mysql-clients.cnf")

for conf in "${CONFIG_FILES[@]}"; do
    if [ -f "$conf" ]; then
        # Remove lines starting with our target variables
        sed -i '/^max_connections/d' "$conf"
        sed -i '/^wait_timeout/d' "$conf"
        sed -i '/^innodb_buffer_pool_size/d' "$conf"
    fi
done

# Restart service to apply defaults
systemctl restart mariadb
sleep 3

# 2. Record initial state for verification reference
INITIAL_MAX=$(mysql -u root -pGymAnything123! -N -e "SHOW GLOBAL VARIABLES LIKE 'max_connections';" 2>/dev/null | awk '{print $2}' || echo "0")
echo "Initial max_connections: $INITIAL_MAX"

# 3. Prepare Environment (Firefox & Virtualmin)
ensure_virtualmin_ready

# Navigate directly to the MySQL module to save time/orient the agent
# The URL for the MySQL module in Webmin
MYSQL_MODULE_URL="${VIRTUALMIN_URL}/mysql/index.cgi"
navigate_to "$MYSQL_MODULE_URL"
sleep 5

# 4. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="