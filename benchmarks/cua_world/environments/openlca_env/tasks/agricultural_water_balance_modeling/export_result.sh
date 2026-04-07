#!/bin/bash
source /workspace/scripts/task_utils.sh

echo "=== Exporting Agricultural Water Balance results ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot
take_screenshot /tmp/task_final.png

# 1. Check CSV Export
CSV_PATH="/home/ga/LCA_Results/wheat_water_balance.csv"
CSV_EXISTS="false"
CSV_CREATED_DURING="false"
CSV_CONTENT=""

if [ -f "$CSV_PATH" ]; then
    CSV_EXISTS="true"
    FILE_TIME=$(stat -c %Y "$CSV_PATH" 2>/dev/null || echo "0")
    if [ "$FILE_TIME" -gt "$TASK_START" ]; then
        CSV_CREATED_DURING="true"
    fi
    # Read first few lines for debug/verification
    CSV_CONTENT=$(head -n 20 "$CSV_PATH" | base64 -w 0)
fi

# 2. Query Derby Database for the Process and Exchanges
# We need to find the process ID first, then get its exchanges
DB_DIR="/home/ga/openLCA-data-1.4/databases"
# Find the active database (most recently modified or largest)
ACTIVE_DB=$(ls -td "$DB_DIR"/*/ 2>/dev/null | head -1)

PROCESS_DATA=""
EXCHANGE_DATA=""

if [ -n "$ACTIVE_DB" ]; then
    echo "Querying database at: $ACTIVE_DB"
    
    # Close OpenLCA to unlock DB for querying
    close_openlca
    sleep 3
    
    # Query for the process
    # TBL_PROCESSES: ID, NAME, DESCRIPTION
    PROC_QUERY="SELECT ID, NAME, F_QUANTITATIVE_REFERENCE FROM TBL_PROCESSES WHERE LOWER(NAME) LIKE '%wheat%cultivation%';"
    PROCESS_DATA=$(derby_query "$ACTIVE_DB" "$PROC_QUERY")
    
    # Extract Process ID (assuming first match is correct)
    # Derby output format is usually header lines, then data. We grab the ID.
    PROC_ID=$(echo "$PROCESS_DATA" | grep -i "Wheat" | awk '{print $1}' | head -1)
    
    if [ -n "$PROC_ID" ] && [ "$PROC_ID" != "ID" ]; then
        echo "Found Process ID: $PROC_ID"
        
        # Query for exchanges linked to this process
        # TBL_EXCHANGES: F_OWNER, IS_INPUT, AMOUNT, F_FLOW
        # TBL_FLOWS: ID, NAME
        # We join to get flow names.
        # Note: Derby SQL join syntax
        EXCH_QUERY="SELECT e.IS_INPUT, e.AMOUNT, f.NAME FROM TBL_EXCHANGES e JOIN TBL_FLOWS f ON e.F_FLOW = f.ID WHERE e.F_OWNER = $PROC_ID;"
        EXCHANGE_DATA=$(derby_query "$ACTIVE_DB" "$EXCH_QUERY")
    fi
else
    echo "No active database found."
fi

# Create JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "csv_exists": $CSV_EXISTS,
    "csv_created_during_task": $CSV_CREATED_DURING,
    "csv_content_base64": "$CSV_CONTENT",
    "process_found": $([ -n "$PROC_ID" ] && echo "true" || echo "false"),
    "process_query_output": "$(echo "$PROCESS_DATA" | sed 's/"/\\"/g' | tr '\n' ' ')",
    "exchange_query_output": "$(echo "$EXCHANGE_DATA" | sed 's/"/\\"/g' | tr '\n' ' ')",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

export_json_result "/tmp/task_result.json" < "$TEMP_JSON"
rm -f "$TEMP_JSON"

echo "=== Export complete ==="