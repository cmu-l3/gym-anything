#!/bin/bash
set -e
echo "=== Exporting configure_fim_syscheck results ==="

source /workspace/scripts/task_utils.sh

# Output file
RESULT_FILE="/tmp/task_result.json"
CONTAINER="wazuh-wazuh.manager-1"

# Get task timings
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)
INITIAL_HASH=$(cat /tmp/initial_ossec_hash.txt 2>/dev/null || echo "none")

# 1. Capture content of ossec.conf from container
OSSEC_CONF_CONTENT=""
CURRENT_HASH="none"
FILE_MODIFIED="false"

if docker exec "$CONTAINER" [ -f /var/ossec/etc/ossec.conf ]; then
    # Get content (base64 encoded to safely transport inside JSON)
    OSSEC_CONF_CONTENT=$(docker exec "$CONTAINER" cat /var/ossec/etc/ossec.conf | base64 -w 0)
    
    # Check hash
    CURRENT_HASH=$(docker exec "$CONTAINER" md5sum /var/ossec/etc/ossec.conf | awk '{print $1}')
    
    if [ "$CURRENT_HASH" != "$INITIAL_HASH" ]; then
        FILE_MODIFIED="true"
    fi
fi

# 2. Check Wazuh API for active configuration
# This proves the manager was restarted and loaded the config
API_CONFIG=""
MANAGER_ACTIVE="false"

# Check if API is responsive
if check_api_health; then
    MANAGER_ACTIVE="true"
    # Fetch syscheck config specifically
    API_RESPONSE=$(wazuh_api GET "/manager/configuration?section=syscheck" 2>/dev/null || echo "{}")
    # Base64 encode to prevent JSON formatting issues
    API_CONFIG=$(echo "$API_RESPONSE" | base64 -w 0)
fi

# 3. Take final screenshot
take_screenshot /tmp/task_final.png

# 4. Construct JSON result
# Use python to write JSON to avoid shell escaping hell
python3 -c "
import json
import sys

data = {
    'task_start': $TASK_START,
    'task_end': $TASK_END,
    'initial_hash': '$INITIAL_HASH',
    'current_hash': '$CURRENT_HASH',
    'file_modified': $FILE_MODIFIED,
    'ossec_conf_b64': '$OSSEC_CONF_CONTENT',
    'api_config_b64': '$API_CONFIG',
    'manager_active': $MANAGER_ACTIVE,
    'screenshot_path': '/tmp/task_final.png'
}

with open('$RESULT_FILE', 'w') as f:
    json.dump(data, f)
"

# Set permissions so verifier (running as user) can copy it
chmod 666 "$RESULT_FILE" 2>/dev/null || true

echo "Result saved to $RESULT_FILE"
echo "=== Export complete ==="