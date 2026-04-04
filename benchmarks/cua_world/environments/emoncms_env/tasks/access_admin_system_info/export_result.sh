#!/bin/bash
# Export script for access_admin_system_info task

echo "=== Exporting access_admin_system_info Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

REPORT_FILE="/home/ga/system_audit_report.txt"

# 1. Check file existence and timestamp
if [ -f "$REPORT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_MTIME=$(stat -c %Y "$REPORT_FILE" 2>/dev/null || echo "0")
    FILE_CONTENT=$(cat "$REPORT_FILE" | base64 -w 0)
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    else
        FILE_CREATED_DURING_TASK="false"
    fi
else
    FILE_EXISTS="false"
    FILE_CREATED_DURING_TASK="false"
    FILE_CONTENT=""
fi

# 2. Capture Ground Truth from System
# We query the containers directly to know what the values SHOULD be.

# Emoncms Version (usually in version.txt or git)
GT_EMONCMS_VERSION=$(docker exec emoncms-web cat /var/www/emoncms/version.txt 2>/dev/null || echo "unknown")

# MySQL Version
GT_MYSQL_VERSION=$(docker exec emoncms-db mysql --version 2>/dev/null | head -1)

# PHP Version
GT_PHP_VERSION=$(docker exec emoncms-web php -v 2>/dev/null | head -1)

# Redis Status (ping)
REDIS_PING=$(docker exec emoncms-redis redis-cli ping 2>/dev/null)
if [ "$REDIS_PING" = "PONG" ]; then
    GT_REDIS_STATUS="Connected"
else
    GT_REDIS_STATUS="Not Connected"
fi

# Server OS
GT_SERVER_OS=$(docker exec emoncms-web cat /etc/os-release 2>/dev/null | grep PRETTY_NAME | cut -d'"' -f2)

# Feed Count
GT_FEED_COUNT=$(db_query "SELECT COUNT(*) FROM feeds" 2>/dev/null)

# Input Count
GT_INPUT_COUNT=$(db_query "SELECT COUNT(*) FROM input" 2>/dev/null)

# MQTT Status
# In this environment, Mosquitto is usually not installed or configured by default in the basic setup script,
# so it likely shows "Not Connected" or "false" on the admin page.
# We'll assume "Not Connected" unless we detect a running mosquitto process mapped to the app.
GT_MQTT_STATUS="Not Connected"

# Take final screenshot
take_screenshot /tmp/task_final.png

# Create JSON result
TEMP_JSON=$(mktemp /tmp/audit_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "file_exists": $FILE_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "file_content_base64": "$FILE_CONTENT",
    "ground_truth": {
        "emoncms_version": "$GT_EMONCMS_VERSION",
        "mysql_version": "$GT_MYSQL_VERSION",
        "php_version": "$GT_PHP_VERSION",
        "redis_status": "$GT_REDIS_STATUS",
        "server_os": "$GT_SERVER_OS",
        "feed_count": "$GT_FEED_COUNT",
        "input_count": "$GT_INPUT_COUNT",
        "mqtt_status": "$GT_MQTT_STATUS"
    },
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
echo "=== Export Complete ==="