#!/bin/bash
echo "=== Exporting enable_remote_mysql result ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 1. Check Network Binding (Is MariaDB listening on 0.0.0.0 or :: ?)
LISTENING_ON_ALL="false"
BIND_ADDRESS_DETECTED=""

# Get the line for port 3306
NETSTAT_OUT=$(netstat -plnt 2>/dev/null | grep ":3306 ")

if echo "$NETSTAT_OUT" | grep -q "0.0.0.0:3306"; then
    LISTENING_ON_ALL="true"
    BIND_ADDRESS_DETECTED="0.0.0.0"
elif echo "$NETSTAT_OUT" | grep -q ":::3306"; then
    LISTENING_ON_ALL="true"
    BIND_ADDRESS_DETECTED="::"
else
    # Likely still 127.0.0.1
    BIND_ADDRESS_DETECTED=$(echo "$NETSTAT_OUT" | awk '{print $4}' | cut -d: -f1)
fi

# 2. Check User Permissions
USER_ACCESS_GRANTED="false"
SPECIFIC_IP_USED="false"
WILDCARD_USED="false"

# Query for the specific user and host
TARGET_HOST_COUNT=$(virtualmin_db_query "SELECT COUNT(*) FROM mysql.user WHERE User='acmecorp' AND Host='192.168.100.55';" | tail -1)
WILDCARD_HOST_COUNT=$(virtualmin_db_query "SELECT COUNT(*) FROM mysql.user WHERE User='acmecorp' AND Host='%';" | tail -1)

if [ "$TARGET_HOST_COUNT" -ge 1 ]; then
    USER_ACCESS_GRANTED="true"
    SPECIFIC_IP_USED="true"
fi

if [ "$WILDCARD_HOST_COUNT" -ge 1 ]; then
    # Wildcard grants access too, but is less secure
    USER_ACCESS_GRANTED="true"
    WILDCARD_USED="true"
fi

# 3. Check modification time of config files (Anti-gaming)
CONFIG_MODIFIED="false"
CNF_FILES=$(find /etc/mysql -name "*.cnf" -newermt "@$TASK_START")
if [ -n "$CNF_FILES" ]; then
    CONFIG_MODIFIED="true"
fi

# 4. Check if MariaDB is running
SERVICE_RUNNING="false"
if systemctl is-active --quiet mariadb; then
    SERVICE_RUNNING="true"
fi

# 5. Capture Final Screenshot
take_screenshot /tmp/task_final.png

# 6. Create JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "listening_on_all": $LISTENING_ON_ALL,
    "bind_address_detected": "$BIND_ADDRESS_DETECTED",
    "user_access_granted": $USER_ACCESS_GRANTED,
    "specific_ip_used": $SPECIFIC_IP_USED,
    "wildcard_used": $WILDCARD_USED,
    "config_modified": $CONFIG_MODIFIED,
    "service_running": $SERVICE_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="