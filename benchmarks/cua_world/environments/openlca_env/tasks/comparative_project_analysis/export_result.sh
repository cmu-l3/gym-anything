#!/bin/bash
# Export script for Comparative Project Analysis task
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

echo "=== Exporting Comparative Project Analysis Result ==="

# 1. Take final screenshot
take_screenshot /tmp/task_end_screenshot.png
echo "Final screenshot captured"

# 2. Check for exported result file
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
RESULTS_DIR="/home/ga/LCA_Results"
REPORT_FILE=""
REPORT_SIZE=0
REPORT_CREATED_DURING_TASK="false"

# Look for Excel or HTML report
for candidate in "$RESULTS_DIR"/*.xlsx "$RESULTS_DIR"/*.html "$RESULTS_DIR"/*.csv; do
    [ -f "$candidate" ] || continue
    FMTIME=$(stat -c %Y "$candidate" 2>/dev/null || echo "0")
    if [ "$((FMTIME))" -gt "$((TASK_START))" ]; then
        REPORT_FILE="$candidate"
        REPORT_SIZE=$(stat -c %s "$candidate" 2>/dev/null || echo "0")
        REPORT_CREATED_DURING_TASK="true"
        echo "Found report file: $candidate"
        break
    fi
done

# 3. Close OpenLCA to query Derby database safely
close_openlca
sleep 5

# 4. Query Derby Database
DB_DIR="/home/ga/openLCA-data-1.4/databases"
ACTIVE_DB=""
MAX_SIZE=0

# Find the largest database (most likely the one used)
for db_path in "$DB_DIR"/*/; do
    [ -d "$db_path" ] || continue
    DB_SIZE=$(du -sm "$db_path" 2>/dev/null | cut -f1 || echo "0")
    if [ "${DB_SIZE:-0}" -gt "$MAX_SIZE" ]; then
        MAX_SIZE="${DB_SIZE:-0}"
        ACTIVE_DB="$db_path"
    fi
done

PROJECT_FOUND="false"
VARIANT_COUNT=0
PARAM_FOUND="false"
PARAM_USAGE_COUNT=0
VARIANTS_CORRECT="false"

if [ -n "$ACTIVE_DB" ] && [ "${MAX_SIZE:-0}" -gt 5 ]; then
    echo "Querying database: $(basename "$ACTIVE_DB")"
    
    # Check for Project existence
    PROJECT_RES=$(derby_query "$ACTIVE_DB" "SELECT NAME FROM TBL_PROJECTS WHERE NAME LIKE '%Sand_Sourcing%';" 2>/dev/null)
    if echo "$PROJECT_RES" | grep -qi "Sand_Sourcing"; then
        PROJECT_FOUND="true"
    fi

    # Check for Project Variants count
    # TBL_PROJECT_VARIANTS links to TBL_PROJECTS via F_PROJECT
    VARIANT_RES=$(derby_query "$ACTIVE_DB" "SELECT COUNT(*) FROM TBL_PROJECT_VARIANTS;" 2>/dev/null)
    VARIANT_COUNT=$(echo "$VARIANT_RES" | grep -oP '^\s*\K\d+' | head -1 || echo "0")

    # Check for Global Parameter
    PARAM_RES=$(derby_query "$ACTIVE_DB" "SELECT NAME FROM TBL_PARAMETERS WHERE NAME = 'transport_tkm';" 2>/dev/null)
    if echo "$PARAM_RES" | grep -qi "transport_tkm"; then
        PARAM_FOUND="true"
    fi

    # Check if Parameter is used in any exchange formula
    # TBL_EXCHANGES has a column F_FORMULA or confusingly just stores the value. 
    # Usually parameters are linked via TBL_PARAMETER_REDEFS or checked by exact name match in formula string if simpler.
    # We will check if any exchange *formula* contains the parameter name.
    # Note: Derby handling of CLOB/Text for formulas can be tricky via CLI, checking simplified approach.
    # OpenLCA 1.x/2.x: TBL_EXCHANGES might have 'FORMULA' column.
    FORMULA_RES=$(derby_query "$ACTIVE_DB" "SELECT COUNT(*) FROM TBL_EXCHANGES WHERE FORMULA LIKE '%transport_tkm%';" 2>/dev/null)
    PARAM_USAGE_COUNT=$(echo "$FORMULA_RES" | grep -oP '^\s*\K\d+' | head -1 || echo "0")

    # Check Variant Redefinitions (TBL_PARAMETER_REDEFS)
    # Ideally we want to see 3 redefinitions for the parameter.
    REDEF_RES=$(derby_query "$ACTIVE_DB" "SELECT VALUE FROM TBL_PARAMETER_REDEFS;" 2>/dev/null)
    # Grep for our specific target values
    if echo "$REDEF_RES" | grep -q "20.0" && echo "$REDEF_RES" | grep -q "200.0" && echo "$REDEF_RES" | grep -q "800.0"; then
        VARIANTS_CORRECT="true"
    fi
fi

# 5. Write result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "report_file": "$REPORT_FILE",
    "report_size": $REPORT_SIZE,
    "report_created_during_task": $REPORT_CREATED_DURING_TASK,
    "project_found": $PROJECT_FOUND,
    "variant_count": ${VARIANT_COUNT:-0},
    "parameter_found": $PARAM_FOUND,
    "parameter_usage_count": ${PARAM_USAGE_COUNT:-0},
    "variants_values_verified": $VARIANTS_CORRECT,
    "screenshot_path": "/tmp/task_end_screenshot.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="