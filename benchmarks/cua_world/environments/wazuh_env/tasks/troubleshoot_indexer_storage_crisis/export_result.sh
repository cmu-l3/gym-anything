#!/bin/bash
echo "=== Exporting Task Results ==="

source /workspace/scripts/task_utils.sh

# Record timestamp
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Check for Legacy Indices (Should be 0)
echo "Checking for legacy indices..."
LEGACY_CHECK=$(wazuh_indexer_query "/_cat/indices/wazuh-alerts-2023.*?format=json")
# If output is empty array or error, count is 0. If indices exist, jq counts them.
LEGACY_COUNT=$(echo "$LEGACY_CHECK" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    if isinstance(data, list):
        print(len(data))
    else:
        print(0)
except:
    print(0)
")
echo "Legacy indices remaining: $LEGACY_COUNT"

# 2. Check Read-Only Block Status (Should be null or false)
# We check the current active index
CURRENT_DATE=$(date +%Y.%m.%d)
CURRENT_INDEX="wazuh-alerts-4.x-$CURRENT_DATE"

echo "Checking block status on $CURRENT_INDEX..."
SETTINGS_JSON=$(wazuh_indexer_query "/$CURRENT_INDEX/_settings")
IS_READ_ONLY=$(echo "$SETTINGS_JSON" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    # navigate to settings.index.blocks.read_only_allow_delete
    # keys are dynamic (index name), so iterate values
    is_locked = False
    for index_data in data.values():
        settings = index_data.get('settings', {}).get('index', {})
        blocks = settings.get('blocks', {})
        if str(blocks.get('read_only_allow_delete', '')).lower() == 'true':
            is_locked = True
    print('true' if is_locked else 'false')
except:
    print('error')
")
echo "Is read-only: $IS_READ_ONLY"

# 3. Verify Write Capability (Should succeed)
echo "Attempting to write test document..."
TEST_INDEX="test-recovery-verification"
WRITE_RESPONSE=$(wazuh_indexer_query "/$TEST_INDEX/_doc" '{"status": "verified", "timestamp": "'"$TASK_END"'"}' )
WRITE_SUCCESS="false"
if echo "$WRITE_RESPONSE" | grep -q '"result":"created"'; then
    WRITE_SUCCESS="true"
fi
# Clean up test index
wazuh_indexer_query "/$TEST_INDEX" -X DELETE > /dev/null 2>&1

echo "Write success: $WRITE_SUCCESS"

# 4. Take final screenshot
take_screenshot /tmp/task_final.png

# 5. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "legacy_indices_count": $LEGACY_COUNT,
    "is_read_only": $IS_READ_ONLY,
    "write_success": $WRITE_SUCCESS,
    "task_start": $TASK_START,
    "task_end": $TASK_END
}
EOF

safe_write_result "/tmp/task_result.json" "$(cat $TEMP_JSON)"
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="