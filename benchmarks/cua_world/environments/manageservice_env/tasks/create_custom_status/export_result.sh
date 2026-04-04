#!/bin/bash
echo "=== Exporting Create Custom Status Result ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_MAX_ID=$(cat /tmp/initial_status_max_id.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Query the database for the created status
# We join with statustype to get the human-readable type (e.g., PENDING, IN PROGRESS)
echo "Querying database for 'Waiting for Vendor' status..."

SQL_QUERY="
SELECT 
    sd.statusid, 
    sd.statusname, 
    st.name as type_name 
FROM statusdefinition sd 
LEFT JOIN statustype st ON sd.statustype = st.statustypeid 
WHERE LOWER(sd.statusname) = 'waiting for vendor' 
ORDER BY sd.statusid DESC LIMIT 1;
"

# Execute query using helper
# Result format will be pipe-separated: ID|NAME|TYPE due to psql -A -t in sdp_db_exec
# Note: sdp_db_exec output might need cleaning depending on environment, assuming clean output here
DB_RESULT=$(sdp_db_exec "$SQL_QUERY")

# Parse results
STATUS_FOUND="false"
STATUS_ID="0"
STATUS_NAME=""
STATUS_TYPE=""

if [ -n "$DB_RESULT" ]; then
    STATUS_FOUND="true"
    STATUS_ID=$(echo "$DB_RESULT" | cut -d'|' -f1)
    STATUS_NAME=$(echo "$DB_RESULT" | cut -d'|' -f2)
    STATUS_TYPE=$(echo "$DB_RESULT" | cut -d'|' -f3)
fi

echo "Found Status: $STATUS_FOUND"
echo "ID: $STATUS_ID (Initial Max: $INITIAL_MAX_ID)"
echo "Name: $STATUS_NAME"
echo "Type: $STATUS_TYPE"

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "initial_max_id": $INITIAL_MAX_ID,
    "status_found": $STATUS_FOUND,
    "status_id": $STATUS_ID,
    "status_name": "$STATUS_NAME",
    "status_type": "$STATUS_TYPE",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location with permission handling
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="