#!/bin/bash
echo "=== Exporting tune_mariadb_performance result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Check if service is active
SERVICE_ACTIVE="false"
if systemctl is-active --quiet mariadb; then
    SERVICE_ACTIVE="true"
fi

# Query runtime variables from MySQL
MAX_CONN=$(mysql -u root -N -e "SELECT @@global.max_connections;" 2>/dev/null || echo "0")
BUFFER_POOL=$(mysql -u root -N -e "SELECT @@global.innodb_buffer_pool_size;" 2>/dev/null || echo "0")
SLOW_LOG=$(mysql -u root -N -e "SELECT @@global.slow_query_log;" 2>/dev/null || echo "0")
LONG_TIME=$(mysql -u root -N -e "SELECT @@global.long_query_time;" 2>/dev/null || echo "0")

# Check configuration files for persistence
# We use case-insensitive, space-tolerant grep to find the settings in any config file
CONFIG_MAX_CONN=$(grep -rEi "^[[:space:]]*max_connections[[:space:]]*=[[:space:]]*400" /etc/mysql/ 2>/dev/null | wc -l)
CONFIG_BUFFER=$(grep -rEi "^[[:space:]]*innodb_buffer_pool_size[[:space:]]*=[[:space:]]*(512M|536870912)" /etc/mysql/ 2>/dev/null | wc -l)
CONFIG_SLOW=$(grep -rEi "^[[:space:]]*slow_query_log[[:space:]]*=[[:space:]]*(1|ON|TRUE)" /etc/mysql/ 2>/dev/null | wc -l)
CONFIG_TIME=$(grep -rEi "^[[:space:]]*long_query_time[[:space:]]*=[[:space:]]*2(\.0*)?" /etc/mysql/ 2>/dev/null | wc -l)

# Create JSON output
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "service_active": $SERVICE_ACTIVE,
    "runtime": {
        "max_connections": "$MAX_CONN",
        "innodb_buffer_pool_size": "$BUFFER_POOL",
        "slow_query_log": "$SLOW_LOG",
        "long_query_time": "$LONG_TIME"
    },
    "config": {
        "max_connections_found": $CONFIG_MAX_CONN,
        "buffer_pool_found": $CONFIG_BUFFER,
        "slow_query_log_found": $CONFIG_SLOW,
        "long_query_time_found": $CONFIG_TIME
    },
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result JSON saved to /tmp/task_result.json"
cat /tmp/task_result.json

echo "=== Export Complete ==="