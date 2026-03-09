#!/bin/bash
# Export script for provision_asset_to_user
# Captures final state of the asset from the database

echo "=== Exporting Provision Asset Result ==="
source /workspace/scripts/task_utils.sh

# 1. Capture Screenshot
take_screenshot /tmp/task_final.png

# 2. Query Database for Asset Details
# We need: Owner (User), Department, State, Description
# Table assumptions based on SDP schema:
# resources (RESOURCEID, RESOURCENAME, USERID, DEPTID, RESOURCESTATEID, COMPONENTID, DESCRIPTION)
# aaauser (USER_ID, FIRST_NAME)
# departmentdefinition (DEPTID, DEPTNAME)
# resourcestate (RESOURCESTATEID, DISPLAYSTATE)

echo "Querying database for asset WS-LPT-4402..."

SQL_QUERY="
SELECT 
    r.resourcename,
    u.first_name,
    d.deptname,
    rs.displaystate,
    r.description
FROM resources r
LEFT JOIN aaauser u ON r.userid = u.user_id
LEFT JOIN departmentdefinition d ON r.deptid = d.deptid
LEFT JOIN resourcestate rs ON r.resourcestateid = rs.resourcestateid
WHERE r.resourcename = 'WS-LPT-4402';
"

# Execute SQL and capture output (tab separated)
DB_RESULT=$(sdp_db_exec "$SQL_QUERY")

echo "Raw DB Result: $DB_RESULT"

# Parse Result
# Expected format: WS-LPT-4402 | Elena Fisher | Operations | In Use | Description...
IFS='|' read -r ASSET_NAME OWNER DEPT STATE DESC <<< "$DB_RESULT"

# Trim whitespace
ASSET_NAME=$(echo "$ASSET_NAME" | xargs)
OWNER=$(echo "$OWNER" | xargs)
DEPT=$(echo "$DEPT" | xargs)
STATE=$(echo "$STATE" | xargs)
DESC=$(echo "$DESC" | xargs)

# Create JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "asset_name": "$ASSET_NAME",
    "owner": "$OWNER",
    "department": "$DEPT",
    "state": "$STATE",
    "description": "$DESC",
    "task_start_time": $(cat /tmp/task_start_time.txt 2>/dev/null || echo 0),
    "export_time": $(date +%s),
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result JSON:"
cat /tmp/task_result.json

echo "=== Export Complete ==="