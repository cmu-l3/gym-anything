#!/bin/bash
# Export script for Local vs Global Sourcing task

source /workspace/scripts/task_utils.sh

echo "=== Exporting Local vs Global Sourcing Result ==="

# 1. Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# 2. Get task timing
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 3. Check CSV output file
OUTPUT_FILE="/home/ga/LCA_Results/flooring_comparison.csv"
FILE_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
FILE_SIZE=0
FILE_CONTENT_HEAD=""

if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$OUTPUT_FILE" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat -c %Y "$OUTPUT_FILE" 2>/dev/null || echo "0")
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
    
    # Capture first few lines for content verification (keywords)
    FILE_CONTENT_HEAD=$(head -n 5 "$OUTPUT_FILE" | base64 -w 0)
fi

# 4. Query Derby Database to verify the MATH
# This is the primary verification method. We need to check if the agent
# calculated the transport amounts correctly (mass * distance).

# Find active database
DB_DIR="/home/ga/openLCA-data-1.4/databases"
ACTIVE_DB=""
MAX_SIZE=0
for db_path in "$DB_DIR"/*/; do
    [ -d "$db_path" ] || continue
    DB_SIZE=$(du -sm "$db_path" 2>/dev/null | cut -f1 || echo "0")
    if [ "${DB_SIZE:-0}" -gt "$MAX_SIZE" ]; then
        MAX_SIZE="${DB_SIZE:-0}"
        ACTIVE_DB="$db_path"
    fi
done

DB_DATA="[]"
if [ -n "$ACTIVE_DB" ]; then
    echo "Querying database at $ACTIVE_DB for Flooring processes..."
    
    # Close OpenLCA to unlock Derby
    close_openlca
    sleep 3
    
    # We query for processes with "Flooring" in the name, and their exchanges
    # We join Process -> Exchange -> Flow (to get flow names)
    # Note: Derby SQL syntax required
    
    QUERY="
    SELECT 
        p.NAME AS PROCESS_NAME, 
        e.AMOUNT, 
        e.UNIT_FACTOR,
        f.NAME AS FLOW_NAME
    FROM 
        TBL_PROCESSES p 
        JOIN TBL_EXCHANGES e ON p.ID = e.F_OWNER 
        JOIN TBL_FLOWS f ON e.F_FLOW = f.ID 
    WHERE 
        p.NAME LIKE '%Flooring%'
    "
    
    # Run query and capture output
    RAW_DB_OUTPUT=$(derby_query "$ACTIVE_DB" "$QUERY")
    
    # Sanitize output for JSON inclusion (escape quotes, newlines)
    CLEAN_DB_OUTPUT=$(echo "$RAW_DB_OUTPUT" | jq -R -s '.')
fi

# 5. Check if OpenLCA log indicates calculation
CALC_LOG_EVIDENCE="false"
if grep -qi "calculat\|impact\|LCIA" /tmp/openlca_ga.log 2>/dev/null; then
    CALC_LOG_EVIDENCE="true"
fi

# 6. Compile Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_file_exists": $FILE_EXISTS,
    "output_file_created_during_task": $FILE_CREATED_DURING_TASK,
    "output_file_size": $FILE_SIZE,
    "output_file_content_base64": "$FILE_CONTENT_HEAD",
    "db_query_output": $CLEAN_DB_OUTPUT,
    "calc_log_evidence": $CALC_LOG_EVIDENCE,
    "screenshot_path": "/tmp/task_end_screenshot.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Export complete. Result saved to /tmp/task_result.json"