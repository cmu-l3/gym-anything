#!/bin/bash
# Export script for Scenario Electricity Comparison task

source /workspace/scripts/task_utils.sh

if ! type take_screenshot &>/dev/null; then
    take_screenshot() { DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true; }
fi
if ! type derby_count &>/dev/null; then
    derby_count() { echo "0"; }
fi
if ! type close_openlca &>/dev/null; then
    close_openlca() { pkill -f "openLCA\|openlca" 2>/dev/null || true; sleep 3; }
fi

echo "=== Exporting Scenario Electricity Comparison Result ==="

take_screenshot /tmp/task_end_screenshot.png

INITIAL_RESULT_COUNT=$(cat /tmp/initial_result_count 2>/dev/null || echo "0")
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
RESULTS_DIR="/home/ga/LCA_Results"
CURRENT_RESULT_COUNT=$(ls -1 "$RESULTS_DIR"/ 2>/dev/null | wc -l)

# ── Search for scenario comparison file ──────────────────────────────────────
SCENARIO_FILE=""
SCENARIO_FILE_SIZE=0
HAS_COAL_KEYWORD=0
HAS_GAS_KEYWORD=0
HAS_GWP_KEYWORD=0
HAS_ACIDIFICATION_KEYWORD=0
HAS_PERCENT_KEYWORD=0
SCENARIO_ROW_COUNT=0

for search_dir in "$RESULTS_DIR" "/home/ga/Desktop" "/home/ga" "/tmp"; do
    for candidate in "$search_dir"/*.csv "$search_dir"/*.xlsx "$search_dir"/*.xls "$search_dir"/*.txt; do
        [ -f "$candidate" ] || continue
        FMTIME=$(stat -c %Y "$candidate" 2>/dev/null || echo "0")
        if [ "$((FMTIME))" -gt "$((TASK_START))" ]; then
            SCENARIO_FILE="$candidate"
            SCENARIO_FILE_SIZE=$(stat -c %s "$candidate" 2>/dev/null || echo "0")
            break 2
        fi
    done
done

if [ -n "$SCENARIO_FILE" ] && [ -f "$SCENARIO_FILE" ]; then
    echo "Found scenario file: $SCENARIO_FILE (${SCENARIO_FILE_SIZE} bytes)"
    grep -qi "coal\|bituminous\|hard.coal\|brown.coal\|lignite" "$SCENARIO_FILE" 2>/dev/null && HAS_COAL_KEYWORD=1
    grep -qi "natural.gas\|gas\|NGCC\|combined.cycle\|methane\|turbine" "$SCENARIO_FILE" 2>/dev/null && HAS_GAS_KEYWORD=1
    grep -qi "global.warm\|GWP\|CO2\|climate\|greenhouse\|carbon" "$SCENARIO_FILE" 2>/dev/null && HAS_GWP_KEYWORD=1
    grep -qi "acidif\|SO2\|sulph\|sulfur\|NOx" "$SCENARIO_FILE" 2>/dev/null && HAS_ACIDIFICATION_KEYWORD=1
    grep -qE "[0-9]+\.?[0-9]*\s*%|percent|reduction|decrease|change" "$SCENARIO_FILE" 2>/dev/null && HAS_PERCENT_KEYWORD=1
    SCENARIO_ROW_COUNT=$(grep -c "[0-9]" "$SCENARIO_FILE" 2>/dev/null)
    [ -z "$SCENARIO_ROW_COUNT" ] && SCENARIO_ROW_COUNT=0
    echo "  Coal: $HAS_COAL_KEYWORD | Gas: $HAS_GAS_KEYWORD | GWP: $HAS_GWP_KEYWORD"
    echo "  Acidification: $HAS_ACIDIFICATION_KEYWORD | Percent: $HAS_PERCENT_KEYWORD"
    echo "  Data rows: $SCENARIO_ROW_COUNT"
fi

# ── Window state ──────────────────────────────────────────────────────────────
WINDOWS_LIST=$(DISPLAY=:1 wmctrl -l 2>/dev/null || echo "")
OPENLCA_RUNNING="false"
RESULTS_VISIBLE="false"
if echo "$WINDOWS_LIST" | grep -qi "openLCA\|openlca"; then OPENLCA_RUNNING="true"; fi
if echo "$WINDOWS_LIST" | grep -qi "result\|impact\|LCIA\|coal\|electricity"; then RESULTS_VISIBLE="true"; fi

# ── Close and query Derby ─────────────────────────────────────────────────────
close_openlca
sleep 4

DB_DIR="/home/ga/openLCA-data-1.4/databases"
PS_COUNT=0
IMPACT_CAT_COUNT=0
DB_SIZE_MB=0
DB_FOUND="false"

ACTIVE_DB=""
MAX_SIZE=0
for db_path in "$DB_DIR"/*/; do
    [ -d "$db_path" ] || continue
    DB_SIZE=$(du -sm "$db_path" 2>/dev/null | cut -f1 || echo "0")
    if [ "${DB_SIZE:-0}" -gt "$MAX_SIZE" ]; then MAX_SIZE="${DB_SIZE:-0}"; ACTIVE_DB="$db_path"; fi
done

if [ -n "$ACTIVE_DB" ] && [ "${MAX_SIZE:-0}" -gt 5 ]; then
    DB_FOUND="true"
    DB_SIZE_MB="$MAX_SIZE"
    PS_COUNT=$(derby_count "$ACTIVE_DB" "PRODUCT_SYSTEMS" 2>/dev/null || echo "0")
    IMPACT_CAT_COUNT=$(derby_count "$ACTIVE_DB" "IMPACT_CATEGORIES" 2>/dev/null || echo "0")
    echo "DB: $(basename "$ACTIVE_DB") | PS: ${PS_COUNT:-0} | Impact cats: ${IMPACT_CAT_COUNT:-0}"
fi

TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task": "scenario_electricity_comparison",
    "openlca_running": $OPENLCA_RUNNING,
    "results_visible": $RESULTS_VISIBLE,
    "db_found": $DB_FOUND,
    "db_size_mb": ${DB_SIZE_MB:-0},
    "ps_count": ${PS_COUNT:-0},
    "impact_cat_count": ${IMPACT_CAT_COUNT:-0},
    "initial_result_count": ${INITIAL_RESULT_COUNT:-0},
    "current_result_count": ${CURRENT_RESULT_COUNT:-0},
    "scenario_file": "$SCENARIO_FILE",
    "scenario_file_size": ${SCENARIO_FILE_SIZE:-0},
    "has_coal_keyword": $HAS_COAL_KEYWORD,
    "has_gas_keyword": $HAS_GAS_KEYWORD,
    "has_gwp_keyword": $HAS_GWP_KEYWORD,
    "has_acidification_keyword": $HAS_ACIDIFICATION_KEYWORD,
    "has_percent_keyword": $HAS_PERCENT_KEYWORD,
    "scenario_row_count": ${SCENARIO_ROW_COUNT:-0},
    "task_start": ${TASK_START:-0},
    "export_timestamp": "$(date -Iseconds)"
}
EOF

rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "=== Export Result ==="
cat /tmp/task_result.json
echo ""
echo "=== Export Complete ==="
