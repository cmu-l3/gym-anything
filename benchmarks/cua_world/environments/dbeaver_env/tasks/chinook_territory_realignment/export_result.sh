#!/bin/bash
# Export script for chinook_territory_realignment
# Verifies database state and file outputs

echo "=== Exporting Chinook Territory Realignment Result ==="

source /workspace/scripts/task_utils.sh

# Paths
CHINOOK_DB="/home/ga/Documents/databases/chinook.db"
OUTPUT_REPORT="/home/ga/Documents/exports/reassignment_verification.csv"
OUTPUT_SCRIPT="/home/ga/Documents/scripts/update_territories.sql"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# 1. Verify DBeaver Connection
# We check if a connection named 'Chinook' exists in data-sources.json
DBEAVER_CONFIG="/home/ga/.local/share/DBeaverData/workspace6/General/.dbeaver/data-sources.json"
CONNECTION_EXISTS="false"
if [ -f "$DBEAVER_CONFIG" ]; then
    if grep -q '"name": "Chinook"' "$DBEAVER_CONFIG"; then
        CONNECTION_EXISTS="true"
    fi
fi

# 2. Verify Database State (The "Meat" of the verification)
# We use sqlite3 to query the DB file directly to see if the agent actually updated the data.

TABLE_MAP_EXISTS="false"
MAP_ROW_COUNT=0
USA_UPDATED="false"
FRANCE_UPDATED="false"
AUSTRALIA_UPDATED="false"

if [ -f "$CHINOOK_DB" ]; then
    # Check if territory_map table exists
    if sqlite3 "$CHINOOK_DB" "SELECT count(*) FROM sqlite_master WHERE type='table' AND name='territory_map';" | grep -q "1"; then
        TABLE_MAP_EXISTS="true"
        # Check row count of import
        MAP_ROW_COUNT=$(sqlite3 "$CHINOOK_DB" "SELECT count(*) FROM territory_map;" 2>/dev/null || echo 0)
    fi

    # Check if updates were applied
    # USA should be Rep 4 (Margaret Park) - Was Rep 3
    USA_REP=$(sqlite3 "$CHINOOK_DB" "SELECT SupportRepId FROM customers WHERE Country='USA' LIMIT 1;" 2>/dev/null)
    if [ "$USA_REP" == "4" ]; then
        USA_UPDATED="true"
    fi

    # France should be Rep 3 (Jane Peacock) - Was Rep 4? (Actually usually Rep 3 covers it, but let's check mapping)
    # Mapping says France -> 3. Standard Chinook: France is usually Rep 3 (Jane). 
    # Let's check Canada. Mapping says Canada -> 4. Standard is 3.
    CANADA_REP=$(sqlite3 "$CHINOOK_DB" "SELECT SupportRepId FROM customers WHERE Country='Canada' LIMIT 1;" 2>/dev/null)
    if [ "$CANADA_REP" == "4" ]; then
        CANADA_UPDATED="true"
    else
        CANADA_UPDATED="false"
    fi
    
    # Australia -> 5. Standard is 5 (Steve). 
    # Let's check a change. 
    # USA: Standard 3 -> New 4.
    # Canada: Standard 3 -> New 4.
    # Brazil: Standard 3 -> New 4.
    # France: Standard 3 -> New 3 (No change).
    # Checking USA and Canada is the best verification of the update logic.
fi

# 3. Verify Output Report
REPORT_EXISTS="false"
REPORT_VALID="false"
if [ -f "$OUTPUT_REPORT" ]; then
    REPORT_EXISTS="true"
    # Basic content check: should have EmployeeName and CustomerCount headers
    HEADER=$(head -n 1 "$OUTPUT_REPORT" | tr '[:upper:]' '[:lower:]')
    if [[ "$HEADER" == *"employee"* && "$HEADER" == *"count"* ]]; then
        REPORT_VALID="true"
    fi
    # Check modification time
    REPORT_MTIME=$(stat -c %Y "$OUTPUT_REPORT" 2>/dev/null || echo 0)
    REPORT_CREATED_DURING_TASK="false"
    if [ "$REPORT_MTIME" -gt "$TASK_START" ]; then
        REPORT_CREATED_DURING_TASK="true"
    fi
fi

# 4. Verify Script
SCRIPT_EXISTS="false"
if [ -f "$OUTPUT_SCRIPT" ]; then
    SCRIPT_EXISTS="true"
    SCRIPT_MTIME=$(stat -c %Y "$OUTPUT_SCRIPT" 2>/dev/null || echo 0)
    SCRIPT_CREATED_DURING_TASK="false"
    if [ "$SCRIPT_MTIME" -gt "$TASK_START" ]; then
        SCRIPT_CREATED_DURING_TASK="true"
    fi
fi

# 5. Generate JSON Result
cat > /tmp/task_result.json << EOF
{
    "connection_exists": $CONNECTION_EXISTS,
    "table_map_exists": $TABLE_MAP_EXISTS,
    "map_row_count": $MAP_ROW_COUNT,
    "usa_updated_correctly": $USA_UPDATED,
    "canada_updated_correctly": $CANADA_UPDATED,
    "report_exists": $REPORT_EXISTS,
    "report_valid": $REPORT_VALID,
    "report_created_during_task": ${REPORT_CREATED_DURING_TASK:-false},
    "script_exists": $SCRIPT_EXISTS,
    "script_created_during_task": ${SCRIPT_CREATED_DURING_TASK:-false},
    "timestamp": "$(date -Iseconds)"
}
EOF

echo "Result generated at /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="