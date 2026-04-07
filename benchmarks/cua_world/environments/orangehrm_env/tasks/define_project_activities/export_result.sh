#!/bin/bash
echo "=== Exporting define_project_activities results ==="

source /workspace/scripts/task_utils.sh

# 1. Capture final screenshot
take_screenshot /tmp/task_final.png

# 2. Get Task Metadata
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
PROJ_NAME="Cloud Migration Phase 1"

# 3. Query Database for Result
# We need to find the activities associated with the project
# and ensure they are not deleted.

echo "Querying database for activities..."

# Get Project ID
PROJ_ID=$(orangehrm_db_query "SELECT project_id FROM ohrm_project WHERE name='$PROJ_NAME' LIMIT 1;" 2>/dev/null | tr -d '[:space:]')

ACTIVITIES_JSON="[]"
if [ -n "$PROJ_ID" ]; then
    # Fetch activity names and is_deleted status
    # Docker exec might return tab separated, we need to parse it carefully
    # We select activity_id to check creation order if needed, but name is most important
    
    # Using a python one-liner to format the SQL output directly to JSON would be robust,
    # but let's stick to bash + jq or simple text processing if possible.
    # Let's dump the raw list first.
    
    RAW_DATA=$(orangehrm_db_query "SELECT name FROM ohrm_project_activity WHERE project_id=$PROJ_ID AND is_deleted=0;")
    
    # Convert newline separated list to JSON array
    # e.g. "Activity A\nActivity B" -> ["Activity A", "Activity B"]
    if [ -n "$RAW_DATA" ]; then
        ACTIVITIES_JSON=$(echo "$RAW_DATA" | jq -R -s -c 'split("\n") | map(select(length > 0))')
    fi
fi

# 4. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_timestamp": $TASK_START,
    "project_found": $([ -n "$PROJ_ID" ] && echo "true" || echo "false"),
    "project_id": "${PROJ_ID:-null}",
    "activities": $ACTIVITIES_JSON,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="