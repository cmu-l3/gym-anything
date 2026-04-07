#!/bin/bash
# Export script for Parametric Yield Modeling task

source /workspace/scripts/task_utils.sh

if ! type take_screenshot &>/dev/null; then
    take_screenshot() { DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true; }
fi
if ! type derby_query &>/dev/null; then
    # Fallback if task_utils not fully loaded
    derby_query() { echo ""; }
fi
if ! type close_openlca &>/dev/null; then
    close_openlca() { pkill -f "openLCA\|openlca" 2>/dev/null || true; sleep 3; }
fi

echo "=== Exporting Parametric Yield Modeling Result ==="

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# 1. Check Result Files
FILE_20="/home/ga/LCA_Results/yield_result_20.csv"
FILE_10="/home/ga/LCA_Results/yield_result_10.csv"
FILE_20_EXISTS="false"
FILE_10_EXISTS="false"
FILE_20_SIZE=0
FILE_10_SIZE=0

if [ -f "$FILE_20" ]; then
    MTIME=$(stat -c %Y "$FILE_20")
    if [ "$MTIME" -gt "$TASK_START" ]; then
        FILE_20_EXISTS="true"
        FILE_20_SIZE=$(stat -c %s "$FILE_20")
    fi
fi

if [ -f "$FILE_10" ]; then
    MTIME=$(stat -c %Y "$FILE_10")
    if [ "$MTIME" -gt "$TASK_START" ]; then
        FILE_10_EXISTS="true"
        FILE_10_SIZE=$(stat -c %s "$FILE_10")
    fi
fi

# 2. Query Derby Database for Process, Parameters, and Formulas
# We need to find the active database first
close_openlca
sleep 4

DB_DIR="/home/ga/openLCA-data-1.4/databases"
ACTIVE_DB=""
MAX_SIZE=0
# Find largest DB (assuming it's the imported USLCI)
for db_path in "$DB_DIR"/*/; do
    [ -d "$db_path" ] || continue
    DB_SIZE=$(du -sm "$db_path" 2>/dev/null | cut -f1 || echo "0")
    if [ "${DB_SIZE:-0}" -gt "$MAX_SIZE" ]; then
        MAX_SIZE="${DB_SIZE:-0}"
        ACTIVE_DB="$db_path"
    fi
done

PROCESS_FOUND="false"
PARAMETER_FOUND="false"
FORMULA_FOUND="false"
FORMULA_TEXT=""

if [ -n "$ACTIVE_DB" ] && [ "${MAX_SIZE:-0}" -gt 5 ]; then
    echo "Querying database: $ACTIVE_DB"
    
    # Check if process exists
    # Note: TBL_PROCESSES usually has NAME column
    PROC_QUERY="SELECT COUNT(*) FROM TBL_PROCESSES WHERE LOWER(NAME) LIKE '%dynamic metal%';"
    PROC_COUNT=$(derby_query "$ACTIVE_DB" "$PROC_QUERY" 2>/dev/null | grep -oP '^\s*\K\d+' | head -1 || echo "0")
    
    if [ "$PROC_COUNT" -gt 0 ]; then
        PROCESS_FOUND="true"
    fi

    # Check if parameter exists
    # TBL_PARAMETERS usually has NAME column
    PARAM_QUERY="SELECT COUNT(*) FROM TBL_PARAMETERS WHERE NAME = 'scrap_rate';"
    PARAM_COUNT=$(derby_query "$ACTIVE_DB" "$PARAM_QUERY" 2>/dev/null | grep -oP '^\s*\K\d+' | head -1 || echo "0")
    
    if [ "$PARAM_COUNT" -gt 0 ]; then
        PARAMETER_FOUND="true"
    fi

    # Check if formulas are used in exchanges
    # TBL_EXCHANGES usually has columns: F_FORMULA or FORMULA
    # We check for the string 'scrap_rate' in the formula field
    FORMULA_QUERY="SELECT COUNT(*) FROM TBL_EXCHANGES WHERE FORMULA LIKE '%scrap_rate%';"
    FORMULA_COUNT=$(derby_query "$ACTIVE_DB" "$FORMULA_QUERY" 2>/dev/null | grep -oP '^\s*\K\d+' | head -1 || echo "0")
    
    if [ "$FORMULA_COUNT" -gt 0 ]; then
        FORMULA_FOUND="true"
    fi
fi

# 3. Create JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "file_20_exists": $FILE_20_EXISTS,
    "file_10_exists": $FILE_10_EXISTS,
    "file_20_size": $FILE_20_SIZE,
    "file_10_size": $FILE_10_SIZE,
    "process_found": $PROCESS_FOUND,
    "parameter_found": $PARAMETER_FOUND,
    "formula_found": $FORMULA_FOUND,
    "active_db_path": "$ACTIVE_DB",
    "timestamp": "$(date -Iseconds)"
}
EOF

# Safe copy to output
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Export complete. Result:"
cat /tmp/task_result.json