#!/bin/bash
source /workspace/scripts/task_utils.sh

echo "=== Exporting BOM Task Results ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
RESULTS_DIR="/home/ga/LCA_Results"
OUTPUT_FILE="$RESULTS_DIR/kettle_impact.csv"

# 1. Check Output File
OUTPUT_EXISTS="false"
OUTPUT_SIZE="0"
OUTPUT_NEW="false"
if [ -f "$OUTPUT_FILE" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c %s "$OUTPUT_FILE")
    FILE_TIME=$(stat -c %Y "$OUTPUT_FILE")
    if [ "$FILE_TIME" -gt "$TASK_START" ]; then
        OUTPUT_NEW="true"
    fi
fi

# 2. Query Derby Database to verify Process Structure
# This is critical: we check if the agent actually built the model in the DB
DB_DIR="/home/ga/openLCA-data-1.4/databases"
ACTIVE_DB=""
# Find the largest DB (assuming it's the imported one)
MAX_SIZE=0
for db in "$DB_DIR"/*/; do
    if [ -d "$db" ]; then
        SIZE=$(du -s "$db" | cut -f1)
        if [ "$SIZE" -gt "$MAX_SIZE" ]; then
            MAX_SIZE=$SIZE
            ACTIVE_DB="$db"
        fi
    fi
done

PROCESS_FOUND="false"
EXCHANGE_COUNT="0"
LINKED_PROVIDER_COUNT="0"
PROCESS_NAME=""
RAW_EXCHANGES=""

if [ -n "$ACTIVE_DB" ]; then
    echo "Inspecting Database: $ACTIVE_DB"
    
    # Check for the specific process
    # Note: TBL_PROCESSES usually has a NAME column.
    PROCESS_QUERY="SELECT ID, NAME FROM TBL_PROCESSES WHERE NAME LIKE '%Electric Kettle Manufacturing%'"
    PROCESS_RES=$(derby_query "$ACTIVE_DB" "$PROCESS_QUERY")
    
    # Parse ID from result (Assuming standard Derby output formatting)
    # Result looks like: "ID | NAME \n ---------------- \n 12345 | Electric Kettle..."
    PROC_ID=$(echo "$PROCESS_RES" | grep "Electric Kettle" | head -1 | awk '{print $1}')
    
    if [ -n "$PROC_ID" ] && [[ "$PROC_ID" =~ ^[0-9]+$ ]]; then
        PROCESS_FOUND="true"
        PROCESS_NAME="Electric Kettle Manufacturing"
        
        # Count Exchanges for this process
        # F_OWNER_ID links exchange to process
        # F_PROVIDER_ID links exchange to a provider process (not null means linked)
        # AMOUNT is the quantity
        EXCHANGE_QUERY="SELECT AMOUNT, F_PROVIDER_ID FROM TBL_EXCHANGES WHERE F_OWNER_ID = $PROC_ID"
        RAW_EXCHANGES=$(derby_query "$ACTIVE_DB" "$EXCHANGE_QUERY")
        
        # Filter raw output to count rows
        # Exclude headers (ID, ---) and empty lines
        CLEAN_ROWS=$(echo "$RAW_EXCHANGES" | grep -E "^[[:space:]]*[0-9.]+" || true)
        EXCHANGE_COUNT=$(echo "$CLEAN_ROWS" | wc -l)
        
        # Count linked providers (lines where second column is a number, not NULL)
        # Derby NULL usually shows as NULL or empty depending on formatter, but standard ij shows NULL.
        # We look for numeric IDs in the second column position
        LINKED_PROVIDER_COUNT=$(echo "$CLEAN_ROWS" | awk '{print $2}' | grep -E "^[0-9]+$" | wc -l || echo "0")
    fi
fi

# 3. Final Screenshot
take_screenshot /tmp/task_final.png

# 4. Generate JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "output_file_exists": $OUTPUT_EXISTS,
    "output_file_new": $OUTPUT_NEW,
    "output_file_size": $OUTPUT_SIZE,
    "db_process_found": $PROCESS_FOUND,
    "process_name": "$PROCESS_NAME",
    "exchange_count": $EXCHANGE_COUNT,
    "linked_provider_count": $LINKED_PROVIDER_COUNT,
    "screenshot_path": "/tmp/task_final.png",
    "task_start_time": $TASK_START,
    "raw_db_path": "$ACTIVE_DB"
}
EOF

# Move to standard location
rm -f /tmp/task_result.json 2>/dev/null || true
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Export complete. Result:"
cat /tmp/task_result.json