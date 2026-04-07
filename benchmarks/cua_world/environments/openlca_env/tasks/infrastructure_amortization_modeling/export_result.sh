#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Infrastructure Amortization Result ==="

# Record end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# 1. Check Output File
OUTPUT_PATH="/home/ga/LCA_Results/turbine_inventory.csv"
OUTPUT_EXISTS="false"
OUTPUT_SIZE="0"
FILE_CREATED_DURING_TASK="false"

if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c %s "$OUTPUT_PATH" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# 2. Query Derby Database for Process Existence and Amortization Factor
# We need to find the active database first
DB_DIR="/home/ga/openLCA-data-1.4/databases"
ACTIVE_DB=""
MAX_SIZE=0

for db_path in "$DB_DIR"/*/; do
    [ -d "$db_path" ] || continue
    CURRENT_SIZE=$(du -sm "$db_path" 2>/dev/null | cut -f1 || echo "0")
    if [ "${CURRENT_SIZE:-0}" -gt "$MAX_SIZE" ]; then
        MAX_SIZE="${CURRENT_SIZE:-0}"
        ACTIVE_DB="$db_path"
    fi
done

PROCESS_CONSTRUCTION_FOUND="false"
PROCESS_GENERATION_FOUND="false"
AMORTIZATION_FACTOR_FOUND="false"
AMORTIZATION_VALUE_MATCH="0"

if [ -n "$ACTIVE_DB" ]; then
    echo "Querying active database: $ACTIVE_DB"
    
    # Close OpenLCA to unlock Derby DB
    close_openlca
    sleep 3

    # Check for Construction Process
    # Using case-insensitive search logic in SQL if possible, or broad LIKE
    QUERY_CONST="SELECT COUNT(*) FROM TBL_PROCESSES WHERE UPPER(NAME) LIKE '%WIND%TURBINE%CONSTRUCTION%'"
    CONST_COUNT=$(derby_query "$ACTIVE_DB" "$QUERY_CONST" | grep -oP '^\s*\K\d+' | head -1 || echo "0")
    if [ "$CONST_COUNT" -gt 0 ]; then
        PROCESS_CONSTRUCTION_FOUND="true"
    fi

    # Check for Generation Process
    QUERY_GEN="SELECT COUNT(*) FROM TBL_PROCESSES WHERE UPPER(NAME) LIKE '%WIND%ELECTRICITY%'"
    GEN_COUNT=$(derby_query "$ACTIVE_DB" "$QUERY_GEN" | grep -oP '^\s*\K\d+' | head -1 || echo "0")
    if [ "$GEN_COUNT" -gt 0 ]; then
        PROCESS_GENERATION_FOUND="true"
    fi

    # Check for Amortization Factor (Target: ~1.25e-8)
    # Derby doesn't support scientific notation literals easily in all versions, 
    # so we check range: 0.0000000124 < val < 0.0000000126
    # Note: 1.25e-8 = 0.0000000125
    QUERY_FACTOR="SELECT COUNT(*) FROM TBL_EXCHANGES WHERE AMOUNT > 0.0000000124 AND AMOUNT < 0.0000000126"
    FACTOR_COUNT=$(derby_query "$ACTIVE_DB" "$QUERY_FACTOR" | grep -oP '^\s*\K\d+' | head -1 || echo "0")
    
    if [ "$FACTOR_COUNT" -gt 0 ]; then
        AMORTIZATION_FACTOR_FOUND="true"
        AMORTIZATION_VALUE_MATCH="$FACTOR_COUNT"
    fi
    
    echo "DB Check: Const=$PROCESS_CONSTRUCTION_FOUND, Gen=$PROCESS_GENERATION_FOUND, Factor=$AMORTIZATION_FACTOR_FOUND ($FACTOR_COUNT)"
fi

# 3. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "output_exists": $OUTPUT_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "output_size_bytes": $OUTPUT_SIZE,
    "process_construction_found": $PROCESS_CONSTRUCTION_FOUND,
    "process_generation_found": $PROCESS_GENERATION_FOUND,
    "amortization_factor_found": $AMORTIZATION_FACTOR_FOUND,
    "amortization_match_count": $AMORTIZATION_VALUE_MATCH,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "=== Export complete ==="
cat /tmp/task_result.json