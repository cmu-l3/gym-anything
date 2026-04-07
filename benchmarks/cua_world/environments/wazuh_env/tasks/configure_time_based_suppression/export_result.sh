#!/bin/bash
echo "=== Exporting Time-Based Suppression Results ==="

source /workspace/scripts/task_utils.sh

# Record end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
CONTAINER="${WAZUH_MANAGER_CONTAINER}"

# 1. Check if Wazuh manager is running (CRITICAL: syntax errors crash it)
MANAGER_RUNNING="false"
if docker exec "${CONTAINER}" /var/ossec/bin/wazuh-control status 2>/dev/null | grep -q "wazuh-analysisd is running"; then
    MANAGER_RUNNING="true"
fi

# 2. Extract local_rules.xml for verification
RULES_PATH="/tmp/submitted_rules.xml"
docker cp "${CONTAINER}:/var/ossec/etc/rules/local_rules.xml" "$RULES_PATH" 2>/dev/null || echo "<error>Could not retrieve rules file</error>" > "$RULES_PATH"

# 3. Check file modification time (Anti-gaming)
FILE_MODIFIED="false"
# We need to check the file inside the container
docker exec "${CONTAINER}" stat -c %Y /var/ossec/etc/rules/local_rules.xml > /tmp/rules_mtime.txt 2>/dev/null
RULES_MTIME=$(cat /tmp/rules_mtime.txt 2>/dev/null || echo "0")

if [ "$RULES_MTIME" -gt "$TASK_START" ]; then
    FILE_MODIFIED="true"
fi

# 4. Take final screenshot
take_screenshot /tmp/task_final.png

# 5. Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "manager_running": $MANAGER_RUNNING,
    "rules_file_modified": $FILE_MODIFIED,
    "rules_file_path": "$RULES_PATH",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move result to final location safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="