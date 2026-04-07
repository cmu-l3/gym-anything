#!/bin/bash
# post_task: Export result for configure_agent_group_policy
echo "=== Exporting configure_agent_group_policy result ==="

source /workspace/scripts/task_utils.sh

GROUP_ID="linux-webservers"
CONTAINER="${WAZUH_MANAGER_CONTAINER}"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 1. Check if Group Exists via API
TOKEN=$(get_api_token)
GROUP_EXISTS="false"
if [ -n "$TOKEN" ]; then
    HTTP_CODE=$(curl -sk -o /dev/null -w "%{http_code}" -X GET "${WAZUH_API_URL}/groups/${GROUP_ID}" \
        -H "Authorization: Bearer ${TOKEN}")
    if [ "$HTTP_CODE" == "200" ]; then
        GROUP_EXISTS="true"
    fi
fi

# 2. Retrieve agent.conf content from container
CONFIG_PATH="/var/ossec/etc/shared/${GROUP_ID}/agent.conf"
CONFIG_CONTENT=""
CONFIG_EXISTS="false"
FILE_MTIME="0"

# Check if file exists in container
if docker exec "${CONTAINER}" test -f "${CONFIG_PATH}"; then
    CONFIG_EXISTS="true"
    # Read content (base64 encode to safely transport via JSON)
    CONFIG_CONTENT=$(docker exec "${CONTAINER}" cat "${CONFIG_PATH}" | base64 -w 0)
    # Get modification time
    FILE_MTIME=$(docker exec "${CONTAINER}" stat -c %Y "${CONFIG_PATH}")
fi

# 3. Check modification time validity
CONFIG_CREATED_DURING_TASK="false"
if [ "$CONFIG_EXISTS" == "true" ]; then
    if [ "$FILE_MTIME" -ge "$TASK_START" ]; then
        CONFIG_CREATED_DURING_TASK="true"
    fi
fi

# 4. Take final screenshot
take_screenshot /tmp/task_final.png

# 5. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "group_id": "$GROUP_ID",
    "group_exists": $GROUP_EXISTS,
    "config_exists": $CONFIG_EXISTS,
    "config_content_b64": "$CONFIG_CONTENT",
    "config_created_during_task": $CONFIG_CREATED_DURING_TASK,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Save to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
echo "=== Export complete ==="