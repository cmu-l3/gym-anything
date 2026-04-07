#!/bin/bash
echo "=== Exporting Configure Wazuh Cluster Master result ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_MTIME=$(cat /tmp/initial_conf_mtime.txt 2>/dev/null || echo "0")
CONTAINER="${WAZUH_MANAGER_CONTAINER}"

# 1. Capture final screenshot
take_screenshot /tmp/task_final.png

# 2. Extract configuration from ossec.conf
echo "Extracting cluster configuration..."
# We use python inside the container (if available) or cat and parse outside
# Simpler: cat the file content to a temp file, then we'll parse it in Python verifier
# However, to reduce verifier complexity, let's extract key fields here using grep/sed if possible,
# or just dump the whole <cluster> block.
CLUSTER_BLOCK=$(docker exec "${CONTAINER}" sed -n '/<cluster>/,/<\/cluster>/p' /var/ossec/etc/ossec.conf)

# 3. Check file modification time
CURRENT_MTIME=$(docker exec "${CONTAINER}" stat -c %Y /var/ossec/etc/ossec.conf 2>/dev/null || echo "0")
FILE_MODIFIED="false"
if [ "$CURRENT_MTIME" -gt "$INITIAL_MTIME" ] && [ "$CURRENT_MTIME" -gt "$TASK_START" ]; then
    FILE_MODIFIED="true"
fi

# 4. Check if wazuh-clusterd process is running
CLUSTERD_RUNNING="false"
if docker exec "${CONTAINER}" pgrep -f "wazuh-clusterd" > /dev/null; then
    CLUSTERD_RUNNING="true"
fi

# 5. Check status via Wazuh Control
CONTROL_STATUS=$(docker exec "${CONTAINER}" /var/ossec/bin/wazuh-control status 2>&1 || echo "command failed")

# 6. Check status via API
API_STATUS=$(wazuh_api GET "/cluster/status" 2>/dev/null || echo "{}")

# 7. Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
# We need to escape the XML block for JSON
ESCAPED_BLOCK=$(echo "$CLUSTER_BLOCK" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')

cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "file_modified": $FILE_MODIFIED,
    "cluster_block": $ESCAPED_BLOCK,
    "daemon_running": $CLUSTERD_RUNNING,
    "control_status": "$(echo "$CONTROL_STATUS" | tr '\n' ';')",
    "api_status": $API_STATUS,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Export complete. Result:"
cat /tmp/task_result.json