#!/bin/bash
echo "=== Exporting Map CMDB Dependencies Result ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Capture Final Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Check if App is running
APP_RUNNING=$(pgrep -f "wrapper" > /dev/null && echo "true" || echo "false")

# 3. Database Extraction
# We need to extract the specific CIs and their relationships to verify the task.

# Define target names
SERVICE_NAME="Payroll Service"
SERVER_NAME="Payroll-DB-01"

# Query for CIs
# Returns: CIID | CINAME | TYPE_NAME (joined via citype if possible, or just base info)
# Note: Schema simplifies here. baseelement contains ciname. citype contains typename.
echo "Querying CIs..."
CI_DATA_JSON=$(sdp_db_exec "
WITH target_cis AS (
    SELECT be.ciid, be.ciname, ct.typename
    FROM baseelement be
    LEFT JOIN citype ct ON be.citypeid = ct.citypeid
    WHERE be.ciname IN ('$SERVICE_NAME', '$SERVER_NAME')
)
SELECT json_agg(row_to_json(target_cis)) FROM target_cis;
")

# If json_agg is null (no rows), make it an empty list
if [ -z "$CI_DATA_JSON" ] || [ "$CI_DATA_JSON" == "" ]; then
    CI_DATA_JSON="[]"
fi

# Query for Relationships
# We look for relationships between the two CIs found above.
# cirelationship table links parentciid and childciid.
# relationshipdefinition table contains the name (e.g., 'Depends On').
echo "Querying Relationships..."
REL_DATA_JSON=$(sdp_db_exec "
WITH rel_data AS (
    SELECT 
        r.parentciid, 
        p.ciname as parent_name,
        r.childciid, 
        c.ciname as child_name,
        rd.relationshipname
    FROM cirelationship r
    JOIN baseelement p ON r.parentciid = p.ciid
    JOIN baseelement c ON r.childciid = c.ciid
    JOIN relationshipdefinition rd ON r.relationshipid = rd.relationshipid
    WHERE p.ciname IN ('$SERVICE_NAME', '$SERVER_NAME')
      AND c.ciname IN ('$SERVICE_NAME', '$SERVER_NAME')
)
SELECT json_agg(row_to_json(rel_data)) FROM rel_data;
")

if [ -z "$REL_DATA_JSON" ] || [ "$REL_DATA_JSON" == "" ]; then
    REL_DATA_JSON="[]"
fi

# 4. Construct Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_was_running": $APP_RUNNING,
    "ci_data": $CI_DATA_JSON,
    "relationship_data": $REL_DATA_JSON,
    "initial_ci_count": $(cat /tmp/initial_ci_count.txt 2>/dev/null || echo "0"),
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location with permission handling
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="