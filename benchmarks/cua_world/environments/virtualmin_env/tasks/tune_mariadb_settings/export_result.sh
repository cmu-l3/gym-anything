#!/bin/bash
echo "=== Exporting tune_mariadb_settings results ==="

# Source shared utilities for screenshot/json helpers
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Check if MariaDB service is running
SERVICE_ACTIVE="false"
if systemctl is-active --quiet mariadb; then
    SERVICE_ACTIVE="true"
fi

# 2. Query running variables (this verifies if restart happened)
# We use the mysql CLI to get the actual in-memory values
MYSQL_CMD="mysql -u root -pGymAnything123! -N -e"

MAX_CONNECTIONS=$($MYSQL_CMD "SHOW GLOBAL VARIABLES LIKE 'max_connections';" 2>/dev/null | awk '{print $2}' || echo "0")
WAIT_TIMEOUT=$($MYSQL_CMD "SHOW GLOBAL VARIABLES LIKE 'wait_timeout';" 2>/dev/null | awk '{print $2}' || echo "0")
BUFFER_POOL=$($MYSQL_CMD "SHOW GLOBAL VARIABLES LIKE 'innodb_buffer_pool_size';" 2>/dev/null | awk '{print $2}' || echo "0")

# 3. Check configuration files (secondary evidence)
# This helps diagnose if they changed the file but forgot to restart
CONFIG_MATCH_MAX=$(grep -r "max_connections" /etc/mysql/ | grep "250" | wc -l)
CONFIG_MATCH_TIMEOUT=$(grep -r "wait_timeout" /etc/mysql/ | grep "300" | wc -l)
CONFIG_MATCH_BUFFER=$(grep -r "innodb_buffer_pool_size" /etc/mysql/ | grep -E "256M|268435456" | wc -l)

# 4. Take final screenshot
take_screenshot /tmp/task_final.png

# 5. Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "service_active": $SERVICE_ACTIVE,
    "runtime_values": {
        "max_connections": "$MAX_CONNECTIONS",
        "wait_timeout": "$WAIT_TIMEOUT",
        "innodb_buffer_pool_size": "$BUFFER_POOL"
    },
    "config_file_evidence": {
        "max_connections_found": $CONFIG_MATCH_MAX,
        "wait_timeout_found": $CONFIG_MATCH_TIMEOUT,
        "buffer_pool_found": $CONFIG_MATCH_BUFFER
    },
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location with permissive permissions
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="