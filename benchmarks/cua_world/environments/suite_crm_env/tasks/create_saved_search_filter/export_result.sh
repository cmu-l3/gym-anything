#!/bin/bash
echo "=== Exporting create_saved_search_filter results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task variables
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_COUNT=$(cat /tmp/initial_search_count.txt 2>/dev/null || echo "0")
CURRENT_COUNT=$(suitecrm_db_query "SELECT COUNT(*) FROM saved_search WHERE deleted=0" | tr -d '[:space:]')

# Take final screenshot
take_screenshot /tmp/task_final.png

# Query the database for the newly created saved search
SEARCH_DATA=$(suitecrm_db_query "SELECT id, name, search_module, contents, UNIX_TIMESTAMP(date_entered) FROM saved_search WHERE name='Texas Tech Customers' AND deleted=0 LIMIT 1")

SEARCH_FOUND="false"
S_ID=""
S_NAME=""
S_MODULE=""
S_CONTENTS_B64=""
S_DATE_ENTERED="0"
S_DECODED_JSON="{}"

if [ -n "$SEARCH_DATA" ]; then
    SEARCH_FOUND="true"
    S_ID=$(echo "$SEARCH_DATA" | awk -F'\t' '{print $1}')
    S_NAME=$(echo "$SEARCH_DATA" | awk -F'\t' '{print $2}')
    S_MODULE=$(echo "$SEARCH_DATA" | awk -F'\t' '{print $3}')
    S_CONTENTS_B64=$(echo "$SEARCH_DATA" | awk -F'\t' '{print $4}')
    S_DATE_ENTERED=$(echo "$SEARCH_DATA" | awk -F'\t' '{print $5}')
    
    # SuiteCRM stores search criteria as a Base64-encoded serialized PHP array.
    # We use the existing suitecrm-app PHP container to safely decode it to JSON.
    echo "$S_CONTENTS_B64" > /tmp/b64.txt
    docker cp /tmp/b64.txt suitecrm-app:/tmp/b64.txt
    
    # Decode and JSON encode
    S_DECODED_JSON=$(docker exec suitecrm-app php -r "\$b64 = file_get_contents('/tmp/b64.txt'); \$arr = unserialize(base64_decode(\$b64)); echo json_encode(\$arr);")
fi

# Fallback in case PHP json_encode failed
if [ -z "$S_DECODED_JSON" ] || [ "$S_DECODED_JSON" = "null" ]; then
    S_DECODED_JSON="{}"
fi

# Build result JSON safely
TEMP_JSON=$(mktemp)
cat > "$TEMP_JSON" << EOF
{
  "task_start_time": $TASK_START,
  "initial_count": $INITIAL_COUNT,
  "current_count": $CURRENT_COUNT,
  "search_found": $SEARCH_FOUND,
  "search_id": "$(json_escape "$S_ID")",
  "name": "$(json_escape "$S_NAME")",
  "module": "$(json_escape "$S_MODULE")",
  "date_entered": $S_DATE_ENTERED,
  "decoded_contents": $S_DECODED_JSON
}
EOF

# Use safe write utility from task_utils.sh to prevent permission issues
safe_write_result "/tmp/task_result.json" "$(cat "$TEMP_JSON")"
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="