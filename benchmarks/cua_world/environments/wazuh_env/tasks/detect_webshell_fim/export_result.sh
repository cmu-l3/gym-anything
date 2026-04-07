#!/bin/bash
# post_task: Export results for detect_webshell_fim task
echo "=== Exporting detect_webshell_fim results ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
VERIFIER_FILE="verification_trigger.php"
CONTAINER="${WAZUH_MANAGER_CONTAINER}"

# 1. Live Fire Verification: Drop a file to see if it triggers the alert
echo "Performing live fire verification..."
# Create a unique PHP file
wazuh_exec touch "/var/www/html/${VERIFIER_FILE}"
wazuh_exec chmod 644 "/var/www/html/${VERIFIER_FILE}"
echo "Created /var/www/html/${VERIFIER_FILE} inside container"

# Wait for FIM and Analysis (Realtime FIM is fast, but give it buffer)
echo "Waiting 15 seconds for alert generation..."
sleep 15

# 2. Extract Configuration Files
echo "Extracting configuration files..."
wazuh_exec cat /var/ossec/etc/ossec.conf > /tmp/ossec.conf
wazuh_exec cat /var/ossec/etc/rules/local_rules.xml > /tmp/local_rules.xml

# 3. Extract Alerts
# We look for alerts generated AFTER the task started
echo "Extracting alerts..."
# We use docker exec to grep directly to avoid copying massive log files
# Look for Rule 100050
# Note: logs are rotated, but alerts.json is usually current.
ALERT_LOG=$(wazuh_exec grep "\"rule\":{\"id\":\"100050\"" /var/ossec/logs/alerts/alerts.json || echo "")

# 4. Check Manager Status
MANAGER_STATUS=$(wazuh_exec /var/ossec/bin/wazuh-control status 2>&1 || echo "stopped")
IS_RUNNING="false"
if echo "$MANAGER_STATUS" | grep -q "wazuh-analysisd is running"; then
    IS_RUNNING="true"
fi

# 5. Take final screenshot
take_screenshot /tmp/task_final.png

# 6. Prepare Result JSON
# Escape quotes for JSON embedding
OSSEC_CONF_CONTENT=$(cat /tmp/ossec.conf | python3 -c 'import sys, json; print(json.dumps(sys.stdin.read()))')
LOCAL_RULES_CONTENT=$(cat /tmp/local_rules.xml | python3 -c 'import sys, json; print(json.dumps(sys.stdin.read()))')
ALERTS_CONTENT=$(echo "$ALERT_LOG" | python3 -c 'import sys, json; print(json.dumps(sys.stdin.read()))')

# Create JSON file
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_time": $TASK_START,
    "timestamp": "$(date -Iseconds)",
    "manager_running": $IS_RUNNING,
    "verifier_file": "$VERIFIER_FILE",
    "ossec_conf": $OSSEC_CONF_CONTENT,
    "local_rules": $LOCAL_RULES_CONTENT,
    "alerts_json": $ALERTS_CONTENT,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
echo "=== Export complete ==="