#!/bin/bash
echo "=== Exporting secure_agent_enrollment results ==="

source /workspace/scripts/task_utils.sh

CONTAINER="wazuh-wazuh.manager-1"
RESULT_FILE="/tmp/task_result.json"
TARGET_PASS="SecuRe!Enroll2024"

# Record Task End Time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# --- 1. Check Password File Existence & Content ---
PASS_FILE_EXISTS="false"
PASS_CONTENT_MATCH="false"
PASS_FILE_PERMS=""
PASS_FILE_OWNER=""
PASS_FILE_GROUP=""

if docker exec "$CONTAINER" [ -f /var/ossec/etc/authd.pass ]; then
    PASS_FILE_EXISTS="true"
    
    # Read content
    ACTUAL_PASS=$(docker exec "$CONTAINER" cat /var/ossec/etc/authd.pass | tr -d '\n' | tr -d '\r')
    if [ "$ACTUAL_PASS" == "$TARGET_PASS" ]; then
        PASS_CONTENT_MATCH="true"
    fi
    
    # Check permissions/ownership
    # stat format: %a (octal), %U (user), %G (group)
    STAT_OUTPUT=$(docker exec "$CONTAINER" stat -c "%a %U %G" /var/ossec/etc/authd.pass)
    PASS_FILE_PERMS=$(echo "$STAT_OUTPUT" | awk '{print $1}')
    PASS_FILE_OWNER=$(echo "$STAT_OUTPUT" | awk '{print $2}')
    PASS_FILE_GROUP=$(echo "$STAT_OUTPUT" | awk '{print $3}')
fi

# --- 2. Check ossec.conf Configuration ---
CONFIG_USE_PASSWORD="false"
CONFIG_FORCE_INSERT="false"

# Grep specifically for the enabled tags inside the container
if docker exec "$CONTAINER" grep -q "<use_password>yes</use_password>" /var/ossec/etc/ossec.conf; then
    CONFIG_USE_PASSWORD="true"
fi

if docker exec "$CONTAINER" grep -q "<force_insert>yes</force_insert>" /var/ossec/etc/ossec.conf; then
    CONFIG_FORCE_INSERT="true"
fi

# --- 3. Check Service Status ---
# Check if wazuh-authd process is running inside container
SERVICE_RUNNING="false"
if docker exec "$CONTAINER" pgrep -f "wazuh-authd" > /dev/null; then
    SERVICE_RUNNING="true"
fi

# --- 4. Functional Network Check (Port 1515) ---
# Check if port 1515 is listening and reachable
PORT_OPEN="false"
if nc -z -w 2 localhost 1515; then
    PORT_OPEN="true"
fi

# --- 5. Generate Result JSON ---
# Create temp file to avoid permission issues
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "pass_file_exists": $PASS_FILE_EXISTS,
    "pass_content_match": $PASS_CONTENT_MATCH,
    "pass_file_perms": "$PASS_FILE_PERMS",
    "pass_file_owner": "$PASS_FILE_OWNER",
    "pass_file_group": "$PASS_FILE_GROUP",
    "config_use_password": $CONFIG_USE_PASSWORD,
    "config_force_insert": $CONFIG_FORCE_INSERT,
    "service_running": $SERVICE_RUNNING,
    "port_open": $PORT_OPEN
}
EOF

# Take final screenshot
take_screenshot /tmp/task_final.png

# Safely copy result to destination
rm -f "$RESULT_FILE" 2>/dev/null || sudo rm -f "$RESULT_FILE" 2>/dev/null || true
cp "$TEMP_JSON" "$RESULT_FILE" 2>/dev/null || sudo cp "$TEMP_JSON" "$RESULT_FILE"
chmod 666 "$RESULT_FILE" 2>/dev/null || sudo chmod 666 "$RESULT_FILE" 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Export complete. Result:"
cat "$RESULT_FILE"