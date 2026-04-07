#!/bin/bash
echo "=== Exporting fix_broken_rules_configuration result ==="

source /workspace/scripts/task_utils.sh

CONTAINER="${WAZUH_MANAGER_CONTAINER}"
RESULT_JSON="/tmp/task_result.json"

# Capture final screenshot
take_screenshot /tmp/task_final.png

# 1. Check if Wazuh Manager process is running
# We check for wazuh-analysisd specifically as it's the core engine
echo "Checking service status..."
PROCESS_LIST=$(docker exec "${CONTAINER}" ps ax 2>/dev/null || echo "")
if echo "$PROCESS_LIST" | grep -q "wazuh-analysisd"; then
    SERVICE_RUNNING="true"
else
    SERVICE_RUNNING="false"
fi

# 2. Get the content of local_rules.xml
echo "Reading rules file..."
RULES_CONTENT_BASE64=$(docker exec "${CONTAINER}" cat /var/ossec/etc/rules/local_rules.xml 2>/dev/null | base64 -w 0)

# 3. Check loaded rules via API (only works if service is running)
LOADED_RULES="[]"
if [ "$SERVICE_RUNNING" = "true" ]; then
    echo "Querying API for loaded rules..."
    # We explicitly check for the expected IDs
    TOKEN=$(get_api_token)
    if [ -n "$TOKEN" ]; then
        API_RESPONSE=$(curl -sk -X GET "${WAZUH_API_URL}/rules?rule_ids=100200,100201,100202" \
            -H "Authorization: Bearer ${TOKEN}")
        LOADED_RULES=$(echo "$API_RESPONSE" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    items = data.get('data', {}).get('affected_items', [])
    ids = [item.get('id') for item in items]
    print(json.dumps(ids))
except:
    print('[]')
")
    fi
fi

# 4. Create result JSON
# We use python to ensure valid JSON creation
python3 -c "
import json
import time

result = {
    'service_running': $SERVICE_RUNNING,
    'rules_content_b64': '$RULES_CONTENT_BASE64',
    'loaded_rule_ids': $LOADED_RULES,
    'timestamp': time.time()
}
with open('$RESULT_JSON', 'w') as f:
    json.dump(result, f)
"

# Handle permissions
chmod 666 "$RESULT_JSON"

echo "Export completed. Result:"
cat "$RESULT_JSON"
echo ""
echo "=== Export complete ==="