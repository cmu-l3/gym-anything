#!/bin/bash
echo "=== Exporting configure_active_response result ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_MTIME=$(cat /tmp/initial_ossec_mtime.txt 2>/dev/null || echo "0")
CONTAINER="${WAZUH_MANAGER_CONTAINER}"

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Check if Wazuh manager is running
MANAGER_RUNNING="false"
if docker exec "${CONTAINER}" pgrep wazuh-modulesd > /dev/null; then
    MANAGER_RUNNING="true"
fi

# 3. Get ossec.conf content and stats
OSSEC_CONF_CONTENT=""
OSSEC_MTIME="0"
FILE_MODIFIED="false"

if docker exec "${CONTAINER}" [ -f /var/ossec/etc/ossec.conf ]; then
    # Read file content safely
    OSSEC_CONF_CONTENT=$(docker exec "${CONTAINER}" cat /var/ossec/etc/ossec.conf | base64 -w 0)
    OSSEC_MTIME=$(docker exec "${CONTAINER}" stat -c %Y /var/ossec/etc/ossec.conf)
    
    if [ "$OSSEC_MTIME" -gt "$INITIAL_MTIME" ]; then
        FILE_MODIFIED="true"
    fi
fi

# 4. Get active configuration via API (proof it's loaded)
# We specifically look at the active-response section of the config
API_CONFIG_JSON="{}"
TOKEN=$(get_api_token)
if [ -n "$TOKEN" ] && [ "$MANAGER_RUNNING" == "true" ]; then
    # Wazuh API: GET /manager/configuration?section=active-response
    API_RESPONSE=$(curl -sk -X GET "${WAZUH_API_URL}/manager/configuration?section=active-response&section=command" \
        -H "Authorization: Bearer ${TOKEN}")
    API_CONFIG_JSON=$(echo "$API_RESPONSE" | jq -c '.' 2>/dev/null || echo "{}")
fi

# 5. Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "manager_running": $MANAGER_RUNNING,
    "file_modified": $FILE_MODIFIED,
    "ossec_mtime": $OSSEC_MTIME,
    "ossec_conf_base64": "$OSSEC_CONF_CONTENT",
    "api_config_json": $API_CONFIG_JSON,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Save to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
echo "=== Export complete ==="