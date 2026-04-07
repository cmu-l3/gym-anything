#!/bin/bash
# Export script for "configure_alert_whitelist" task
echo "=== Exporting Configure Alert Whitelist Results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils"; exit 1; }

# 1. Capture Final Screenshot
take_screenshot /tmp/task_final.png

# 2. Check Verification File (Agent created)
VERIFICATION_FILE="/home/ga/whitelist_config.txt"
FILE_EXISTS="false"
FILE_CONTENT=""
FILE_TIMESTAMP=0
TASK_START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

if [ -f "$VERIFICATION_FILE" ]; then
    FILE_EXISTS="true"
    FILE_CONTENT=$(cat "$VERIFICATION_FILE" | tr '\n' ' ')
    FILE_TIMESTAMP=$(stat -c %Y "$VERIFICATION_FILE" 2>/dev/null || echo "0")
fi

# 3. Database Check (Ground Truth)
# We search the database for the IP address to confirm it was actually saved in a table.
# Since exact table names can vary by version, we search specifically for the IP string in relevant columns if possible,
# or dump relevant config tables.
TARGET_IP="172.16.0.50"
DB_MATCH_FOUND="false"

# Query the database for the IP address in likely tables
# Using the ela_db_query utility from environment
echo "Searching database for $TARGET_IP..."

# Try querying a generic configuration table or search all text columns (simulated by grep on dump if small, but let's try specific tables first)
# Note: In ELA, correlation whitelists might be in 'CorrelationWhiteList', 'AlertFilter', or stored as XML/JSON in a config table.
# A safe broad check is to query if the string exists in the DB dump of specific tables.

# We'll try to find it in the entire DB by dumping as text (risky if huge, but ELA dev DB is small)
# Limiting to grep for the IP to avoid huge output
DB_DUMP_MATCH=$(ela_db_query "COPY (SELECT * FROM pg_catalog.pg_tables) TO STDOUT" 2>/dev/null | grep -v "pg_" || true)

# More precise check: Check if any row in commonly used tables contains the IP
# This is a heuristic check.
DB_CHECK_OUTPUT=$(su - postgres -c "pg_dump -d eventlog -t '*WhiteList*' -t '*Filter*' --data-only" 2>/dev/null | grep "$TARGET_IP" || true)

if [ -n "$DB_CHECK_OUTPUT" ]; then
    DB_MATCH_FOUND="true"
    echo "Found IP in database dump: $DB_CHECK_OUTPUT"
else
    # Fallback: check if the agent perhaps added it as a Device instead (common mistake)
    DEVICE_CHECK=$(ela_db_query "SELECT * FROM DeviceList WHERE ip_address='$TARGET_IP'" 2>/dev/null)
    if [ -n "$DEVICE_CHECK" ]; then
        echo "WARNING: IP found in DeviceList (wrong place for whitelist)"
    fi
fi

# 4. Check if application is running
APP_RUNNING="false"
if pgrep -f "wrapper" > /dev/null || pgrep -f "java" > /dev/null; then
    APP_RUNNING="true"
fi

# 5. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_time": $TASK_START_TIME,
    "file_exists": $FILE_EXISTS,
    "file_content": "$FILE_CONTENT",
    "file_timestamp": $FILE_TIMESTAMP,
    "db_match_found": $DB_MATCH_FOUND,
    "db_evidence": "$(echo $DB_CHECK_OUTPUT | sed 's/"/\\"/g' | cut -c 1-200)",
    "app_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png",
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="