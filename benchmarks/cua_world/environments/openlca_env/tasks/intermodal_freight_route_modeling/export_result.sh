#!/bin/bash
# Export script for Intermodal Freight Route Modeling task

source /workspace/scripts/task_utils.sh

echo "=== Exporting Results ==="

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
OUTPUT_FILE="/home/ga/LCA_Results/route_gwp.csv"

# 1. Check Output File
FILE_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
FILE_SIZE=0
HAS_GWP_CONTENT="false"

if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$OUTPUT_FILE")
    FILE_MTIME=$(stat -c %Y "$OUTPUT_FILE")
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
    
    # Check for content keywords
    if grep -qi "Global Warming\|GWP\|CO2\|kg CO2" "$OUTPUT_FILE"; then
        HAS_GWP_CONTENT="true"
    fi
fi

# 2. Query Derby Database for Process Details
# We need to find the process 'freight_route_chicago_wi' and check its inputs
DB_DIR="/home/ga/openLCA-data-1.4/databases"
ACTIVE_DB=""
MAX_SIZE=0

# Find largest database (likely the one with USLCI imported)
for db_path in "$DB_DIR"/*/; do
    [ -d "$db_path" ] || continue
    current_size=$(du -sm "$db_path" 2>/dev/null | cut -f1 || echo "0")
    if [ "${current_size:-0}" -gt "$MAX_SIZE" ]; then
        MAX_SIZE="${current_size:-0}"
        ACTIVE_DB="$db_path"
    fi
done

PROCESS_FOUND="false"
PROCESS_ID=""
EXCHANGES_JSON="[]"

if [ -n "$ACTIVE_DB" ]; then
    echo "Querying database: $ACTIVE_DB"
    
    # Query to find the process ID
    # Note: TBL_PROCESSES has column NAME
    PROC_QUERY="SELECT ID FROM TBL_PROCESSES WHERE LOWER(NAME) LIKE '%freight_route%chicago%';"
    PROCESS_ID_RAW=$(derby_query "$ACTIVE_DB" "$PROC_QUERY")
    
    # Extract ID (remove header/footer from ij output)
    PROCESS_ID=$(echo "$PROCESS_ID_RAW" | grep -oE '[0-9]+' | head -1)
    
    if [ -n "$PROCESS_ID" ]; then
        PROCESS_FOUND="true"
        echo "Found Process ID: $PROCESS_ID"
        
        # Query exchanges for this process (Input exchanges)
        # We assume INPUT=1 or similar, but generally checking all exchanges 
        # TBL_EXCHANGES columns: RESULT_AMOUNT, F_OWNER, F_FLOW, F_DEFAULT_PROVIDER
        EXCHANGE_QUERY="SELECT RESULT_AMOUNT FROM TBL_EXCHANGES WHERE F_OWNER = $PROCESS_ID;"
        EXCHANGES_RAW=$(derby_query "$ACTIVE_DB" "$EXCHANGE_QUERY")
        
        # Parse amounts into a simple JSON list
        AMOUNTS=$(echo "$EXCHANGES_RAW" | grep -oE '[0-9]+\.?[0-9]*' | grep -v "^$" | tr '\n' ',' | sed 's/,$//')
        EXCHANGES_JSON="[$AMOUNTS]"
    fi
fi

# 3. Check App State
OPENLCA_RUNNING="false"
if pgrep -f "openLCA\|openlca" > /dev/null; then
    OPENLCA_RUNNING="true"
fi

# 4. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "file_exists": $FILE_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "file_size": $FILE_SIZE,
    "has_gwp_content": $HAS_GWP_CONTENT,
    "process_found": $PROCESS_FOUND,
    "process_id": "$PROCESS_ID",
    "exchange_amounts": $EXCHANGES_JSON,
    "openlca_running": $OPENLCA_RUNNING,
    "active_db_path": "$ACTIVE_DB"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result JSON generated at /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="