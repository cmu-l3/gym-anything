#!/bin/bash
# Export script for Composite Material LCA Modeling task
set -e

echo "=== Exporting Composite Material LCA Results ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Collect Task Metadata
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)
RESULTS_DIR="/home/ga/LCA_Results"
OUTPUT_FILE="$RESULTS_DIR/biobrick_impact.csv"

# 3. Verify Output File
FILE_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
FILE_SIZE=0
FILE_CONTENT_PREVIEW=""

if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c%s "$OUTPUT_FILE")
    FILE_MTIME=$(stat -c%Y "$OUTPUT_FILE")
    
    if [ "$FILE_MTIME" -ge "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
    
    # Grab first few lines to check for CSV content
    FILE_CONTENT_PREVIEW=$(head -n 5 "$OUTPUT_FILE" | base64 -w 0)
fi

# 4. Database Verification (Derby Queries)
# We need to find the active database (the one the agent created/imported)
DB_DIR="/home/ga/openLCA-data-1.4/databases"
ACTIVE_DB=""
MAX_SIZE=0

# Find largest DB (likely the one with USLCI imported)
for db_path in "$DB_DIR"/*/; do
    [ -d "$db_path" ] || continue
    # Skip if directory name starts with dot
    dirname=$(basename "$db_path")
    if [[ "$dirname" == .* ]]; then continue; fi
    
    curr_size=$(du -sm "$db_path" | cut -f1)
    if [ "$curr_size" -gt "$MAX_SIZE" ]; then
        MAX_SIZE="$curr_size"
        ACTIVE_DB="$db_path"
    fi
done

echo "Detected active database: $ACTIVE_DB (Size: ${MAX_SIZE}MB)"

# Initialize verification variables
DB_FOUND="false"
PROCESS_FOUND="false"
FLOW_FOUND="false"
EXCHANGE_DATA=""

if [ -n "$ACTIVE_DB" ] && [ "$MAX_SIZE" -gt 10 ]; then
    DB_FOUND="true"
    
    # Close OpenLCA to unlock Derby DB for querying
    close_openlca
    sleep 2
    
    # Query 1: Check if "Bio-brick Production" process exists
    # Note: TBL_PROCESSES stores names. We look for case-insensitive match.
    PROCESS_QUERY="SELECT ID, NAME FROM TBL_PROCESSES WHERE UPPER(NAME) LIKE '%BIO-BRICK%'"
    PROCESS_RESULT=$(derby_query "$ACTIVE_DB" "$PROCESS_QUERY")
    
    if echo "$PROCESS_RESULT" | grep -qi "Bio-brick"; then
        PROCESS_FOUND="true"
        # Extract Process ID for checking exchanges
        # Derby output format is messy, we'll try to grep the numeric ID
        # Assuming ID is the first column
        PROC_ID=$(echo "$PROCESS_RESULT" | grep -i "Bio-brick" | awk '{print $1}' | tr -d '|')
    fi
    
    # Query 2: Check if "Rice Husks" flow exists
    FLOW_QUERY="SELECT ID FROM TBL_FLOWS WHERE UPPER(NAME) LIKE '%RICE%HUSK%'"
    FLOW_RESULT=$(derby_query "$ACTIVE_DB" "$FLOW_QUERY")
    if echo "$FLOW_RESULT" | grep -q "[0-9]"; then
        FLOW_FOUND="true"
    fi
    
    # Query 3: Check Exchanges (Inputs) for the Bio-brick process
    if [ -n "$PROC_ID" ]; then
        # Join Exchanges with Flows to get names and amounts
        # TBL_EXCHANGES: F_OWNER (process), F_FLOW (flow), RESULT_AMOUNT
        EXCHANGE_QUERY="SELECT f.NAME, e.RESULT_AMOUNT FROM TBL_EXCHANGES e JOIN TBL_FLOWS f ON e.F_FLOW = f.ID WHERE e.F_OWNER = $PROC_ID"
        EXCHANGE_DATA_RAW=$(derby_query "$ACTIVE_DB" "$EXCHANGE_QUERY")
        # Encode for JSON safety
        EXCHANGE_DATA=$(echo "$EXCHANGE_DATA_RAW" | base64 -w 0)
    fi
fi

# 5. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "file_exists": $FILE_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "file_size": $FILE_SIZE,
    "file_content_b64": "$FILE_CONTENT_PREVIEW",
    "db_found": $DB_FOUND,
    "db_size_mb": $MAX_SIZE,
    "process_found": $PROCESS_FOUND,
    "flow_found": $FLOW_FOUND,
    "exchange_data_b64": "$EXCHANGE_DATA",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"