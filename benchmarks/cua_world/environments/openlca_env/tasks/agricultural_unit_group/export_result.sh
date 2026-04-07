#!/bin/bash
# Export script for Agricultural Unit Group task

source /workspace/scripts/task_utils.sh

# Fallback definitions
if ! type close_openlca &>/dev/null; then
    close_openlca() { pkill -f "openLCA\|openlca" 2>/dev/null || true; sleep 3; }
fi
if ! type take_screenshot &>/dev/null; then
    take_screenshot() { DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true; }
fi

echo "=== Exporting Agricultural Unit Group Result ==="

# 1. Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# 2. Check if OpenLCA was running
OPENLCA_WAS_RUNNING="false"
if pgrep -f "openLCA\|openlca" > /dev/null; then
    OPENLCA_WAS_RUNNING="true"
fi

# 3. Close OpenLCA to unlock Derby database
echo "Closing OpenLCA to query database..."
close_openlca
sleep 3

# 4. Find the active database
# We look for the most recently modified directory in the databases folder
DB_DIR="/home/ga/openLCA-data-1.4/databases"
ACTIVE_DB=""
if [ -d "$DB_DIR" ]; then
    # Find active DB (most recently modified)
    ACTIVE_DB=$(ls -td "$DB_DIR"/*/ 2>/dev/null | head -1)
fi

DB_FOUND="false"
UNIT_GROUP_FOUND="false"
UNITS_DATA=""
FLOW_PROP_DATA=""

if [ -n "$ACTIVE_DB" ] && [ -d "$ACTIVE_DB" ]; then
    DB_FOUND="true"
    echo "Querying database at: $ACTIVE_DB"

    # Define Derby query function locally if needed or use task_utils
    # We use a comprehensive query to extract exactly what we need
    
    # Query 1: Get Units linked to our target Group Name
    # We join TBL_UNITS and TBL_UNIT_GROUPS
    SQL_UNITS="SELECT ug.NAME AS GROUP_NAME, u.NAME AS UNIT_NAME, u.CONVERSION_FACTOR, u.REF_ID 
               FROM TBL_UNITS u 
               JOIN TBL_UNIT_GROUPS ug ON u.F_UNIT_GROUP = ug.ID 
               WHERE UPPER(ug.NAME) LIKE '%AGRICULTURAL AREA-TIME%';"
    
    UNITS_DATA=$(derby_query "$ACTIVE_DB" "$SQL_UNITS")
    
    # Query 2: Get Flow Properties linked to our target Group Name
    # We join TBL_FLOW_PROPERTIES and TBL_UNIT_GROUPS
    SQL_FP="SELECT fp.NAME AS FP_NAME, ug.NAME AS GROUP_NAME 
            FROM TBL_FLOW_PROPERTIES fp 
            JOIN TBL_UNIT_GROUPS ug ON fp.F_UNIT_GROUP = ug.ID 
            WHERE UPPER(fp.NAME) LIKE '%IRRIGATED AREA-TIME%';"
            
    FLOW_PROP_DATA=$(derby_query "$ACTIVE_DB" "$SQL_FP")

else
    echo "No database found in $DB_DIR"
fi

# 5. Create JSON result
# We will embed the raw query output into the JSON for the python verifier to parse
# This avoids complex bash parsing

TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "openlca_was_running": $OPENLCA_WAS_RUNNING,
    "db_found": $DB_FOUND,
    "active_db_path": "$ACTIVE_DB",
    "units_query_output": $(echo "$UNITS_DATA" | jq -R -s '.'),
    "flow_prop_query_output": $(echo "$FLOW_PROP_DATA" | jq -R -s '.'),
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to standard location with permissions
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"