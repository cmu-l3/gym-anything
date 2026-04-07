#!/bin/bash
echo "=== Exporting PowerShell Obfuscation Rule Result ==="

source /workspace/scripts/task_utils.sh

# 1. Capture final screenshot
take_screenshot /tmp/task_final.png

# 2. Extract local_rules.xml content
RULES_CONTENT=$(docker exec "${WAZUH_MANAGER_CONTAINER}" cat /var/ossec/etc/rules/local_rules.xml 2>/dev/null)
RULES_HASH=$(docker exec "${WAZUH_MANAGER_CONTAINER}" md5sum /var/ossec/etc/rules/local_rules.xml 2>/dev/null || echo "0")
INITIAL_HASH=$(cat /tmp/initial_rules_hash.txt 2>/dev/null || echo "1")

# 3. Check if file was modified
if [ "$RULES_HASH" != "$INITIAL_HASH" ]; then
    FILE_MODIFIED="true"
else
    FILE_MODIFIED="false"
fi

# 4. Run wazuh-logtest verification INSIDE container
# We pipe the sample log into wazuh-logtest and capture output
SAMPLE_LOG=$(head -n 1 /home/ga/data/powershell_samples.json)
LOGTEST_OUTPUT=$(echo "$SAMPLE_LOG" | docker exec -i "${WAZUH_MANAGER_CONTAINER}" /var/ossec/bin/wazuh-logtest 2>&1)

# 5. Check if manager is running
MANAGER_STATUS=$(docker exec "${WAZUH_MANAGER_CONTAINER}" /var/ossec/bin/wazuh-control status 2>&1)
if echo "$MANAGER_STATUS" | grep -q "wazuh-analysisd is running"; then
    MANAGER_RUNNING="true"
else
    MANAGER_RUNNING="false"
fi

# 6. Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
# Use python to safely JSON-encode the large text blocks
python3 -c "
import json
import sys

data = {
    'file_modified': '$FILE_MODIFIED' == 'true',
    'manager_running': '$MANAGER_RUNNING' == 'true',
    'rules_content': sys.argv[1],
    'logtest_output': sys.argv[2],
    'task_start': $(cat /tmp/task_start_time.txt 2>/dev/null || echo 0),
    'task_end': $(date +%s)
}

print(json.dumps(data))
" "$RULES_CONTENT" "$LOGTEST_OUTPUT" > "$TEMP_JSON"

# 7. Move result to standard location
rm -f /tmp/task_result.json 2>/dev/null || true
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Export complete."