#!/bin/bash
# Export script for create_cdb_threat_intel task
set -e

echo "=== Exporting task results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot
take_screenshot /tmp/task_final.png

# 1. API Verification Data
echo "Collecting API data..."
TOKEN=$(get_api_token)

# Get List Metadata
LIST_META=$(curl -sk -X GET "${WAZUH_API_URL}/lists/files/threat-intel-blocklist" \
    -H "Authorization: Bearer ${TOKEN}")

# Get List Content (if it exists)
LIST_CONTENT=""
if echo "$LIST_META" | grep -q "threat-intel-blocklist"; then
    LIST_CONTENT=$(curl -sk -X GET "${WAZUH_API_URL}/lists/files/threat-intel-blocklist/content" \
        -H "Authorization: Bearer ${TOKEN}")
fi

# Get Rule Definition
RULE_DEF=$(curl -sk -X GET "${WAZUH_API_URL}/rules?rule_ids=100100" \
    -H "Authorization: Bearer ${TOKEN}")

# Get Manager Status
MANAGER_STATUS=$(curl -sk -X GET "${WAZUH_API_URL}/manager/status" \
    -H "Authorization: Bearer ${TOKEN}")

# 2. Filesystem Verification Data (Direct container check)
echo "Collecting container file data..."

# Check list file
CONTAINER_LIST_PATH="/var/ossec/etc/lists/threat-intel-blocklist"
CONTAINER_LIST_EXISTS="false"
CONTAINER_LIST_MTIME="0"
CONTAINER_LIST_CONTENT=""

if docker exec "${WAZUH_MANAGER_CONTAINER}" [ -f "$CONTAINER_LIST_PATH" ]; then
    CONTAINER_LIST_EXISTS="true"
    CONTAINER_LIST_MTIME=$(docker exec "${WAZUH_MANAGER_CONTAINER}" stat -c %Y "$CONTAINER_LIST_PATH")
    CONTAINER_LIST_CONTENT=$(docker exec "${WAZUH_MANAGER_CONTAINER}" cat "$CONTAINER_LIST_PATH")
fi

# Check rules file
CONTAINER_RULES_PATH="/var/ossec/etc/rules/local_rules.xml"
CONTAINER_RULES_MTIME=$(docker exec "${WAZUH_MANAGER_CONTAINER}" stat -c %Y "$CONTAINER_RULES_PATH" 2>/dev/null || echo "0")
CONTAINER_RULES_CONTENT=$(docker exec "${WAZUH_MANAGER_CONTAINER}" cat "$CONTAINER_RULES_PATH")

# 3. Construct Result JSON
# Using python to safely construct JSON to handle potential escaping issues with file content
python3 -c "
import json
import os
import sys

def safe_json_load(s):
    try:
        return json.loads(s)
    except:
        return {'raw': s}

api_list_meta = safe_json_load('''$LIST_META''')
api_rule_def = safe_json_load('''$RULE_DEF''')
api_manager_status = safe_json_load('''$MANAGER_STATUS''')

result = {
    'task_start': $TASK_START,
    'task_end': $TASK_END,
    'api': {
        'list_meta': api_list_meta,
        'list_content': '''$LIST_CONTENT''',
        'rule_def': api_rule_def,
        'manager_status': api_manager_status
    },
    'fs': {
        'list_exists': $CONTAINER_LIST_EXISTS,
        'list_mtime': $CONTAINER_LIST_MTIME,
        'list_content': '''$CONTAINER_LIST_CONTENT''',
        'rules_mtime': $CONTAINER_RULES_MTIME,
        'rules_content': '''$CONTAINER_RULES_CONTENT'''
    }
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
"

# Set permissions
chmod 666 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
echo "=== Export complete ==="