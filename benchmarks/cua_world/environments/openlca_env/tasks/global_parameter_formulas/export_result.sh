#!/bin/bash
# Export script for Global Parameter Formulas task
# Post-task hook: runs AFTER the agent finishes

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

echo "=== Exporting Global Parameter Formulas Result ==="

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png
echo "Final screenshot saved"

TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
RESULTS_DIR="/home/ga/LCA_Results"
CSV_PATH="$RESULTS_DIR/parameter_summary.csv"

# ============================================================
# CHECK 1: CSV File Analysis
# ============================================================
CSV_EXISTS="false"
CSV_CREATED_DURING_TASK="false"
CSV_SIZE=0
CSV_CONTENT_PREVIEW=""

if [ -f "$CSV_PATH" ]; then
    CSV_EXISTS="true"
    CSV_SIZE=$(stat -c %s "$CSV_PATH" 2>/dev/null || echo "0")
    
    # Check timestamp
    FILE_TIME=$(stat -c %Y "$CSV_PATH" 2>/dev/null || echo "0")
    if [ "$FILE_TIME" -gt "$TASK_START" ]; then
        CSV_CREATED_DURING_TASK="true"
    fi
    
    # Get content preview (first 10 lines)
    CSV_CONTENT_PREVIEW=$(head -n 10 "$CSV_PATH" | base64 -w 0)
fi

# ============================================================
# CHECK 2: Derby Database Query (The Source of Truth)
# ============================================================
close_openlca
sleep 4

DB_DIR="/home/ga/openLCA-data-1.4/databases"
DB_PARAMS_JSON="[]"
DB_NAME=""

# Find the active database (largest/most recently modified)
ACTIVE_DB=""
MAX_SIZE=0
for db_path in "$DB_DIR"/*/; do
    [ -d "$db_path" ] || continue
    CURRENT_SIZE=$(du -sm "$db_path" 2>/dev/null | cut -f1 || echo "0")
    if [ "${CURRENT_SIZE:-0}" -ge "$MAX_SIZE" ]; then
        MAX_SIZE="${CURRENT_SIZE:-0}"
        ACTIVE_DB="$db_path"
    fi
done

if [ -n "$ACTIVE_DB" ]; then
    DB_NAME=$(basename "$ACTIVE_DB")
    echo "Querying database: $DB_NAME"
    
    # Query TBL_PARAMETERS
    # We want Name, Value, Formula, and input status
    # Note: Schema might vary slightly, but these are standard
    QUERY="SELECT NAME, VALUE, FORMULA, IS_INPUT_PARAM FROM TBL_PARAMETERS WHERE SCOPE = 'GLOBAL_SCOPE' OR F_OWNER IS NULL"
    
    RAW_RESULT=$(derby_query "$ACTIVE_DB" "$QUERY" 2>/dev/null)
    
    # Simple parsing of Derby output to JSON-like structure (python helper would be better but doing bash for simplicity in export)
    # We will just dump the raw result into the JSON and let python verifier parse it
    # Encode raw result to base64 to avoid JSON escaping issues
    DB_PARAMS_RAW=$(echo "$RAW_RESULT" | base64 -w 0)
else
    echo "No database found to query"
    DB_PARAMS_RAW=""
fi

# ============================================================
# Write result JSON
# ============================================================
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "csv_exists": $CSV_EXISTS,
    "csv_created_during_task": $CSV_CREATED_DURING_TASK,
    "csv_size": $CSV_SIZE,
    "csv_content_b64": "$CSV_CONTENT_PREVIEW",
    "db_name": "$DB_NAME",
    "db_params_raw_b64": "$DB_PARAMS_RAW",
    "screenshot_path": "/tmp/task_end_screenshot.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"