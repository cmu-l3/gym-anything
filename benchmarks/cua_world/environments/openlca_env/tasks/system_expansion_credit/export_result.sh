#!/bin/bash
# Export script for System Expansion Credit task

source /workspace/scripts/task_utils.sh

# Fallback definitions
if ! type take_screenshot &>/dev/null; then
    take_screenshot() { DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true; }
fi
if ! type derby_query &>/dev/null; then
    derby_query() { echo ""; }
fi
if ! type close_openlca &>/dev/null; then
    close_openlca() { pkill -f "openLCA\|openlca" 2>/dev/null || true; sleep 3; }
fi

echo "=== Exporting System Expansion Result ==="

# 1. Capture final screenshot
take_screenshot /tmp/task_end_screenshot.png

# 2. Check CSV Output
CSV_FILE="/home/ga/LCA_Results/substitution_benefit.csv"
CSV_EXISTS="false"
CSV_SIZE=0
CSV_CONTENT_VALID="false"

if [ -f "$CSV_FILE" ]; then
    CSV_EXISTS="true"
    CSV_SIZE=$(stat -c %s "$CSV_FILE" 2>/dev/null || echo "0")
    
    # Check for negative values (indication of credit) or numeric data
    if grep -qE "\-|[0-9]+\.[0-9]+" "$CSV_FILE"; then
        CSV_CONTENT_VALID="true"
    fi
fi

# 3. Close OpenLCA to query Derby DB
close_openlca
sleep 5

# 4. Inspect Database for Process, Parameter, and Negative Input
DB_DIR="/home/ga/openLCA-data-1.4/databases"
ACTIVE_DB=""
MAX_SIZE=0

# Find largest DB (active one)
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
NEGATIVE_INPUT_FOUND="false"
SUBSTITUTION_COUNT=0

if [ -n "$ACTIVE_DB" ] && [ "${MAX_SIZE:-0}" -gt 5 ]; then
    echo "Querying database: $ACTIVE_DB"
    
    # Check for Process Name
    PROC_QUERY="SELECT COUNT(*) FROM TBL_PROCESSES WHERE UPPER(NAME) LIKE '%RECYCLING%' AND UPPER(NAME) LIKE '%SUBSTITUTION%';"
    PROC_RES=$(derby_query "$ACTIVE_DB" "$PROC_QUERY")
    # Clean output (remove headers/ij prompt)
    PROC_COUNT=$(echo "$PROC_RES" | grep -oP '^\s*\K\d+' | head -1 || echo "0")
    if [ "$PROC_COUNT" -gt 0 ]; then
        PROCESS_FOUND="true"
    fi
    
    # Check for Parameter 'substitution_ratio'
    PARAM_QUERY="SELECT COUNT(*) FROM TBL_PARAMETERS WHERE UPPER(NAME) = 'SUBSTITUTION_RATIO';"
    PARAM_RES=$(derby_query "$ACTIVE_DB" "$PARAM_QUERY")
    PARAM_COUNT=$(echo "$PARAM_RES" | grep -oP '^\s*\K\d+' | head -1 || echo "0")
    if [ "$PARAM_COUNT" -gt 0 ]; then
        PARAMETER_FOUND="true"
    fi
    
    # Check for Negative Input (System Expansion)
    # TBL_EXCHANGES: is_input=1, amount < 0
    # Note: derby stores booleans as 0/1 often, or smallint. IS_INPUT is usually SMALLINT/BOOLEAN.
    SUB_QUERY="SELECT COUNT(*) FROM TBL_EXCHANGES WHERE IS_INPUT = 1 AND AMOUNT < 0;"
    SUB_RES=$(derby_query "$ACTIVE_DB" "$SUB_QUERY")
    SUBSTITUTION_COUNT=$(echo "$SUB_RES" | grep -oP '^\s*\K\d+' | head -1 || echo "0")
    
    if [ "$SUBSTITUTION_COUNT" -gt 0 ]; then
        NEGATIVE_INPUT_FOUND="true"
    fi
fi

# 5. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "csv_exists": $CSV_EXISTS,
    "csv_size": $CSV_SIZE,
    "csv_content_valid": $CSV_CONTENT_VALID,
    "db_found": $([ -n "$ACTIVE_DB" ] && echo "true" || echo "false"),
    "process_found": $PROCESS_FOUND,
    "parameter_found": $PARAMETER_FOUND,
    "negative_input_found": $NEGATIVE_INPUT_FOUND,
    "substitution_count": $SUBSTITUTION_COUNT
}
EOF

# Safe copy with permissions
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result Export Complete."
cat /tmp/task_result.json