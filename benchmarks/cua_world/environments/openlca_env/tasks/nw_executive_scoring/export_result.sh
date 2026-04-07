#!/bin/bash
# Export script for Normalization and Weighting Executive Reporting task

source /workspace/scripts/task_utils.sh

# Fallback definitions
if ! type take_screenshot &>/dev/null; then
    take_screenshot() { DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true; }
fi
if ! type derby_count &>/dev/null; then
    derby_count() { echo "0"; }
fi
if ! type derby_query &>/dev/null; then
    derby_query() { echo ""; }
fi
if ! type close_openlca &>/dev/null; then
    close_openlca() { pkill -f "openLCA\|openlca" 2>/dev/null || true; sleep 3; }
fi

echo "=== Exporting NW Executive Scoring Result ==="

# Capture final state visual
take_screenshot /tmp/task_end_screenshot.png

TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
RESULT_FILE="/home/ga/LCA_Results/normalized_weighted_results.csv"

# ── CHECK 1: Output File Analysis ─────────────────────────────────────────────
FILE_EXISTS="false"
FILE_SIZE=0
FILE_CREATED_DURING_TASK="false"
HAS_NUMERIC_DATA="false"
HAS_CATEGORY_KEYWORDS="false"

if [ -f "$RESULT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$RESULT_FILE" 2>/dev/null || echo "0")
    
    # Check modification time
    FMTIME=$(stat -c %Y "$RESULT_FILE" 2>/dev/null || echo "0")
    if [ "$((FMTIME))" -gt "$((TASK_START))" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi

    # Check content
    if grep -qE "[0-9]+\.[0-9]+" "$RESULT_FILE"; then
        HAS_NUMERIC_DATA="true"
    fi
    
    # Check for keywords related to the task
    if grep -qiE "global|warming|acidification|eutrophication|ozone|smog|weighted|result" "$RESULT_FILE"; then
        HAS_CATEGORY_KEYWORDS="true"
    fi
fi

# ── CHECK 2: OpenLCA Application State ────────────────────────────────────────
WINDOWS_LIST=$(DISPLAY=:1 wmctrl -l 2>/dev/null || echo "")
OPENLCA_RUNNING="false"
if echo "$WINDOWS_LIST" | grep -qi "openLCA\|openlca"; then
    OPENLCA_RUNNING="true"
fi

# ── CHECK 3: Database & Derby Query ───────────────────────────────────────────
close_openlca
sleep 5

DB_DIR="/home/ga/openLCA-data-1.4/databases"
ACTIVE_DB=""
MAX_SIZE=0

# Find the active database (largest one likely)
for db_path in "$DB_DIR"/*/; do
    [ -d "$db_path" ] || continue
    current_size=$(du -sm "$db_path" 2>/dev/null | cut -f1 || echo "0")
    if [ "${current_size:-0}" -gt "$MAX_SIZE" ]; then
        MAX_SIZE="${current_size:-0}"
        ACTIVE_DB="$db_path"
    fi
done

PROCESS_COUNT=0
PRODUCT_SYSTEM_COUNT=0
NW_SET_COUNT=0
NW_FACTORS_COUNT=0
USLCI_IMPORTED="false"
NW_SET_NAME_MATCH="false"

if [ -n "$ACTIVE_DB" ] && [ "${MAX_SIZE:-0}" -gt 5 ]; then
    echo "Querying database: $(basename "$ACTIVE_DB")"
    
    # Check structural counts
    PROCESS_COUNT=$(derby_count "$ACTIVE_DB" "PROCESSES")
    PRODUCT_SYSTEM_COUNT=$(derby_count "$ACTIVE_DB" "PRODUCT_SYSTEMS")
    
    # Check if USLCI seems imported (heuristic: many processes)
    if [ "${PROCESS_COUNT:-0}" -gt 100 ]; then
        USLCI_IMPORTED="true"
    fi

    # Query for NW Sets
    # Note: Table names in openLCA Derby DB are typically TBL_NW_SETS or similar
    # We'll use the generic query helper to be safe, but specific table name is TBL_NW_SETS
    NW_SET_COUNT=$(derby_count "$ACTIVE_DB" "NW_SETS")
    
    # Query for specific NW Set name
    NW_SET_NAMES=$(derby_query "$ACTIVE_DB" "SELECT NAME FROM TBL_NW_SETS;" 2>/dev/null || echo "")
    if echo "$NW_SET_NAMES" | grep -qi "US.*Person.*Year.*2023"; then
        NW_SET_NAME_MATCH="true"
    fi

    # Query for Factors
    # TBL_NW_FACTORS usually links NW Sets to Impact Categories
    # We check if there are any factors defined with non-zero values
    NW_FACTORS_RESULT=$(derby_query "$ACTIVE_DB" "SELECT COUNT(*) FROM TBL_NW_FACTORS WHERE NORMALISATION_FACTOR != 0 OR WEIGHTING_FACTOR != 0;" 2>/dev/null)
    NW_FACTORS_COUNT=$(echo "$NW_FACTORS_RESULT" | grep -oP '^\s*\K\d+' | head -1 || echo "0")
fi

# ── EXPORT JSON ───────────────────────────────────────────────────────────────
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "file_exists": $FILE_EXISTS,
    "file_size": $FILE_SIZE,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "has_numeric_data": $HAS_NUMERIC_DATA,
    "has_category_keywords": $HAS_CATEGORY_KEYWORDS,
    "openlca_running_at_end": $OPENLCA_RUNNING,
    "db_found": $([ -n "$ACTIVE_DB" ] && echo "true" || echo "false"),
    "process_count": ${PROCESS_COUNT:-0},
    "product_system_count": ${PRODUCT_SYSTEM_COUNT:-0},
    "uslci_imported": $USLCI_IMPORTED,
    "nw_set_count": ${NW_SET_COUNT:-0},
    "nw_set_name_match": $NW_SET_NAME_MATCH,
    "nw_factors_count": ${NW_FACTORS_COUNT:-0}
}
EOF

export_json_result "/tmp/task_result.json" < "$TEMP_JSON"
rm -f "$TEMP_JSON"

echo "=== Export Complete ==="
cat /tmp/task_result.json