#!/bin/bash
# Export script for Soybean Allocation Configuration task
source /workspace/scripts/task_utils.sh

echo "=== Exporting Soybean Allocation Result ==="

# 1. Capture Final State
take_screenshot /tmp/task_end_screenshot.png
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
RESULTS_DIR="/home/ga/LCA_Results"
OUTPUT_FILE="$RESULTS_DIR/soybean_allocation.csv"

# 2. Check Result File
FILE_EXISTS="false"
FILE_SIZE=0
FILE_CREATED_DURING_TASK="false"
CONTENT_VALID="false"

if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$OUTPUT_FILE" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat -c %Y "$OUTPUT_FILE" 2>/dev/null || echo "0")
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
    
    # Check for content keywords (impact categories or numeric values)
    if grep -qE "Global|Warming|GWP|kg|CO2|[0-9]+\.[0-9]+" "$OUTPUT_FILE"; then
        CONTENT_VALID="true"
    fi
fi

# 3. Check OpenLCA State (Window & Logs)
OPENLCA_RUNNING="false"
if is_openlca_running; then
    OPENLCA_RUNNING="true"
fi

# 4. Database Verification (Derby Queries)
# We need to verify the internal structure of the process created by the agent.
close_openlca
sleep 5

# Find the active database (largest directory in workspace)
DB_DIR="/home/ga/openLCA-data-1.4/databases"
ACTIVE_DB=""
MAX_SIZE=0
for db in "$DB_DIR"/*/; do
    if [ -d "$db" ]; then
        SIZE=$(du -s "$db" | cut -f1)
        if [ "$SIZE" -gt "$MAX_SIZE" ]; then
            MAX_SIZE=$SIZE
            ACTIVE_DB=$db
        fi
    fi
done

# Initialize DB metrics
DB_FOUND="false"
PROCESS_FOUND="false"
ALLOCATION_CONFIGURED="false"
MULTIPLE_OUTPUTS="false"
PRODUCT_SYSTEM_CREATED="false"
PROCESS_ID=""

if [ -n "$ACTIVE_DB" ]; then
    DB_FOUND="true"
    echo "Inspecting database: $ACTIVE_DB"

    # A. Find the Soybean Process
    # Query: Find ID of process with name like 'soybean'
    # Note: TBL_PROCESSES usually has columns ID, NAME, DESCRIPTION, etc.
    QUERY_PROC="SELECT ID, NAME FROM TBL_PROCESSES WHERE LOWER(NAME) LIKE '%soybean%';"
    PROC_RESULT=$(derby_query "$ACTIVE_DB" "$QUERY_PROC")
    
    # Parse ID from result (simple heuristic parsing)
    # Result usually looks like: 
    # ID | NAME
    # ----------------
    # 1234 | Soybean Process
    PROCESS_ID=$(echo "$PROC_RESULT" | grep -i "soybean" | grep -oE "^[0-9]+" | head -1)
    
    if [ -n "$PROCESS_ID" ]; then
        PROCESS_FOUND="true"
        echo "Found Soybean Process ID: $PROCESS_ID"
        
        # B. Check for Multiple Outputs (Flows)
        # TBL_EXCHANGES: F_OWNER=ProcessID. IS_INPUT=0 (Output).
        # We want at least 2 outputs.
        QUERY_OUT="SELECT COUNT(*) FROM TBL_EXCHANGES WHERE F_OWNER=$PROCESS_ID AND IS_INPUT=0;"
        OUT_COUNT_RES=$(derby_query "$ACTIVE_DB" "$QUERY_OUT")
        OUT_COUNT=$(echo "$OUT_COUNT_RES" | grep -oE "[0-9]+" | tail -1)
        
        if [ "$OUT_COUNT" -ge 2 ]; then
            MULTIPLE_OUTPUTS="true"
        fi
        
        # C. Check Allocation Factors
        # TBL_ALLOCATION_FACTORS: F_PROCESS=ProcessID
        QUERY_ALLOC="SELECT COUNT(*) FROM TBL_ALLOCATION_FACTORS WHERE F_PROCESS=$PROCESS_ID;"
        ALLOC_RES=$(derby_query "$ACTIVE_DB" "$QUERY_ALLOC")
        ALLOC_COUNT=$(echo "$ALLOC_RES" | grep -oE "[0-9]+" | tail -1)
        
        if [ "$ALLOC_COUNT" -ge 1 ]; then
            ALLOCATION_CONFIGURED="true"
        fi
    fi
    
    # D. Check Product System
    QUERY_SYS="SELECT COUNT(*) FROM TBL_PRODUCT_SYSTEMS;"
    SYS_RES=$(derby_query "$ACTIVE_DB" "$QUERY_SYS")
    SYS_COUNT=$(echo "$SYS_RES" | grep -oE "[0-9]+" | tail -1)
    if [ "$SYS_COUNT" -gt 0 ]; then
        PRODUCT_SYSTEM_CREATED="true"
    fi
fi

# 5. Create JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "file_exists": $FILE_EXISTS,
    "file_size": $FILE_SIZE,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "content_valid": $CONTENT_VALID,
    "openlca_running": $OPENLCA_RUNNING,
    "db_found": $DB_FOUND,
    "process_found": $PROCESS_FOUND,
    "multiple_outputs": $MULTIPLE_OUTPUTS,
    "allocation_configured": $ALLOCATION_CONFIGURED,
    "product_system_created": $PRODUCT_SYSTEM_CREATED,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to standard location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json