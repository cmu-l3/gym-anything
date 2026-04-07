#!/bin/bash
echo "=== Exporting investigate_apt_and_build_detection results ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
REPORT_PATH="/home/ga/apt_report.json"

# Take final screenshot
take_screenshot /tmp/task_final.png

# --- Check 1: Agent report file ---
REPORT_EXISTS="false"
REPORT_CREATED_DURING_TASK="false"
REPORT_SIZE="0"

if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    REPORT_SIZE=$(stat -c %s "$REPORT_PATH" 2>/dev/null || echo "0")
    REPORT_MTIME=$(stat -c %Y "$REPORT_PATH" 2>/dev/null || echo "0")

    if [ "$REPORT_MTIME" -gt "$TASK_START" ]; then
        REPORT_CREATED_DURING_TASK="true"
    fi

    # Stage report for verifier access
    cp "$REPORT_PATH" /tmp/exported_apt_report.json 2>/dev/null || true
    chmod 644 /tmp/exported_apt_report.json 2>/dev/null || true
fi

# --- Check 2: Extract local_rules.xml from container ---
echo "Extracting local_rules.xml from container..."
docker cp "${WAZUH_MANAGER_CONTAINER}:/var/ossec/etc/rules/local_rules.xml" \
    /tmp/local_rules.xml 2>/dev/null || \
    echo "<error>Could not copy rules file</error>" > /tmp/local_rules.xml

# --- Check 3: Manager running status ---
MANAGER_RUNNING="false"
if docker exec "${WAZUH_MANAGER_CONTAINER}" /var/ossec/bin/wazuh-control status \
    2>/dev/null | grep -q "wazuh-analysisd is running"; then
    MANAGER_RUNNING="true"
fi

# --- Check 4: Query API for loaded custom rules ---
echo "Querying API for custom rules..."
TOKEN=$(get_api_token)
API_RULES_RESPONSE="{}"
if [ -n "$TOKEN" ]; then
    API_RULES_RESPONSE=$(curl -sk -X GET \
        "${WAZUH_API_URL}/rules?search=local&limit=50" \
        -H "Authorization: Bearer ${TOKEN}" 2>/dev/null \
        || echo '{"error":"API query failed"}')
fi
echo "$API_RULES_RESPONSE" > /tmp/api_rules_check.json

# --- Check 5: Bash history evidence ---
HISTORY_EVIDENCE="false"
if grep -qE "curl.*(9200|55000)" /home/ga/.bash_history 2>/dev/null; then
    HISTORY_EVIDENCE="true"
fi

# --- Create result JSON ---
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "report_exists": $REPORT_EXISTS,
    "report_created_during_task": $REPORT_CREATED_DURING_TASK,
    "report_size": $REPORT_SIZE,
    "manager_running": $MANAGER_RUNNING,
    "history_evidence_found": $HISTORY_EVIDENCE,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location with permission fallbacks
rm -f /tmp/task_result.json 2>/dev/null || \
    sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || \
    sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || \
    sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
chmod 666 /tmp/local_rules.xml /tmp/api_rules_check.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "=== Export complete ==="
