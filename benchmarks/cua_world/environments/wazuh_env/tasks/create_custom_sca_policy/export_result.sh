#!/bin/bash
echo "=== Exporting create_custom_sca_policy results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

CONTAINER="${WAZUH_MANAGER_CONTAINER}"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Capture Policy File Content
POLICY_PATH="/var/ossec/etc/sca/payment_gateway_audit.yml"
POLICY_CONTENT=""
POLICY_EXISTS="false"

if docker exec "${CONTAINER}" [ -f "${POLICY_PATH}" ]; then
    POLICY_EXISTS="true"
    POLICY_CONTENT=$(docker exec "${CONTAINER}" cat "${POLICY_PATH}" | base64 -w 0)
    POLICY_MTIME=$(docker exec "${CONTAINER}" stat -c %Y "${POLICY_PATH}")
    
    if [ "$POLICY_MTIME" -gt "$TASK_START" ]; then
        CREATED_DURING_TASK="true"
    else
        CREATED_DURING_TASK="false"
    fi
else
    CREATED_DURING_TASK="false"
fi

# 2. Capture ossec.conf Content (SCA section only)
CONFIG_CONTENT=""
if docker exec "${CONTAINER}" [ -f /var/ossec/etc/ossec.conf ]; then
    # Extract just the SCA section to avoid massive files, strictly for debugging/verification
    CONFIG_CONTENT=$(docker exec "${CONTAINER}" grep -A 50 "<sca>" /var/ossec/etc/ossec.conf | grep -B 50 "</sca>" | base64 -w 0)
fi

# 3. Capture API Result for the Policy
# We query the SCA endpoint. Since the policy ID is 10005, we check agent 000 (manager)
API_RESULT_JSON="{}"
TOKEN=$(get_api_token)
if [ -n "$TOKEN" ]; then
    # Trigger a scan check or just get results
    # Force SCA scan might be needed, but usually it runs on restart.
    # We'll just fetch current results.
    API_RESPONSE=$(curl -sk -X GET "${WAZUH_API_URL}/sca/000" \
        -H "Authorization: Bearer ${TOKEN}")
    
    # Filter for our specific policy if possible, or dump all
    API_RESULT_JSON=$(echo "$API_RESPONSE" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    items = data.get('data', {}).get('affected_items', [])
    target = next((i for i in items if i.get('policy_id') == '10005'), None)
    print(json.dumps(target) if target else '{}')
except:
    print('{}')
")
fi

# 4. Check if Manager is Running
MANAGER_RUNNING="false"
if docker exec "${CONTAINER}" pgrep wazuh-modulesd > /dev/null; then
    MANAGER_RUNNING="true"
fi

# 5. Take Final Screenshot
take_screenshot /tmp/task_final.png

# 6. Construct Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "policy_exists": $POLICY_EXISTS,
    "created_during_task": $CREATED_DURING_TASK,
    "policy_content_b64": "$POLICY_CONTENT",
    "config_content_b64": "$CONFIG_CONTENT",
    "api_result": $API_RESULT_JSON,
    "manager_running": $MANAGER_RUNNING,
    "timestamp": $(date +%s)
}
EOF

# Save to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"