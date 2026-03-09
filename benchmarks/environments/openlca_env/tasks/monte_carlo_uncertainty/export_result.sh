#!/bin/bash
# Export script for Monte Carlo Uncertainty Quantification task

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

echo "=== Exporting Monte Carlo Uncertainty Result ==="

take_screenshot /tmp/task_end_screenshot.png

INITIAL_RESULT_COUNT=$(cat /tmp/initial_result_count 2>/dev/null || echo "0")
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
RESULTS_DIR="/home/ga/LCA_Results"
CURRENT_RESULT_COUNT=$(ls -1 "$RESULTS_DIR"/ 2>/dev/null | wc -l)

# ── Search for Monte Carlo result file ───────────────────────────────────────
MC_FILE=""
MC_FILE_SIZE=0
HAS_MEAN_KEYWORD=0
HAS_STD_KEYWORD=0
HAS_CONFIDENCE_KEYWORD=0
HAS_GWP_KEYWORD=0
MC_DATA_ROWS=0

for search_dir in "$RESULTS_DIR" "/home/ga/Desktop" "/home/ga" "/tmp"; do
    for candidate in "$search_dir"/*.csv "$search_dir"/*.xlsx "$search_dir"/*.xls "$search_dir"/*.txt; do
        [ -f "$candidate" ] || continue
        FMTIME=$(stat -c %Y "$candidate" 2>/dev/null || echo "0")
        if [ "$((FMTIME))" -gt "$((TASK_START))" ]; then
            MC_FILE="$candidate"
            MC_FILE_SIZE=$(stat -c %s "$candidate" 2>/dev/null || echo "0")
            break 2
        fi
    done
done

if [ -n "$MC_FILE" ] && [ -f "$MC_FILE" ]; then
    echo "Found result file: $MC_FILE (${MC_FILE_SIZE} bytes)"
    grep -qi "mean\|average\|mittelwert" "$MC_FILE" 2>/dev/null && HAS_MEAN_KEYWORD=1
    grep -qi "std\|standard.dev\|deviation\|sigma" "$MC_FILE" 2>/dev/null && HAS_STD_KEYWORD=1
    grep -qi "confidence\|interval\|percentile\|95%\|2.5%\|97.5%" "$MC_FILE" 2>/dev/null && HAS_CONFIDENCE_KEYWORD=1
    grep -qi "global.warm\|GWP\|CO2\|climate\|greenhouse\|warming" "$MC_FILE" 2>/dev/null && HAS_GWP_KEYWORD=1
    MC_DATA_ROWS=$(grep -c "[0-9]\." "$MC_FILE" 2>/dev/null)
    [ -z "$MC_DATA_ROWS" ] && MC_DATA_ROWS=0

    echo "  Mean keyword: $HAS_MEAN_KEYWORD"
    echo "  Std dev keyword: $HAS_STD_KEYWORD"
    echo "  Confidence interval keyword: $HAS_CONFIDENCE_KEYWORD"
    echo "  GWP keyword: $HAS_GWP_KEYWORD"
    echo "  Data rows: $MC_DATA_ROWS"
else
    echo "No Monte Carlo result file found"
fi

# ── Check window for Monte Carlo evidence ────────────────────────────────────
WINDOWS_LIST=$(DISPLAY=:1 wmctrl -l 2>/dev/null || echo "")
OPENLCA_RUNNING="false"
MC_WINDOW_VISIBLE="false"

if echo "$WINDOWS_LIST" | grep -qi "openLCA\|openlca"; then
    OPENLCA_RUNNING="true"
fi
if echo "$WINDOWS_LIST" | grep -qi "Monte.Carlo\|Simulation\|Uncertainty\|Statistics"; then
    MC_WINDOW_VISIBLE="true"
fi

# Check log for Monte Carlo evidence
MC_IN_LOG="false"
if [ -f "/tmp/openlca_ga.log" ]; then
    grep -qi "Monte.Carlo\|simulation\|iteration\|uncertainty" /tmp/openlca_ga.log 2>/dev/null && MC_IN_LOG="true"
fi

# ── Close OpenLCA and query Derby ────────────────────────────────────────────
close_openlca
sleep 4

DB_DIR="/home/ga/openLCA-data-1.4/databases"
PS_COUNT=0
IMPACT_CAT_COUNT=0
PARAM_COUNT=0
DB_SIZE_MB=0
DB_FOUND="false"

ACTIVE_DB=""
MAX_SIZE=0
for db_path in "$DB_DIR"/*/; do
    [ -d "$db_path" ] || continue
    DB_SIZE=$(du -sm "$db_path" 2>/dev/null | cut -f1 || echo "0")
    if [ "${DB_SIZE:-0}" -gt "$MAX_SIZE" ]; then
        MAX_SIZE="${DB_SIZE:-0}"
        ACTIVE_DB="$db_path"
    fi
done

if [ -n "$ACTIVE_DB" ] && [ "${MAX_SIZE:-0}" -gt 5 ]; then
    DB_FOUND="true"
    DB_SIZE_MB="$MAX_SIZE"
    echo "Active database: $(basename "$ACTIVE_DB") (${DB_SIZE_MB}MB)"

    PS_COUNT=$(derby_count "$ACTIVE_DB" "PRODUCT_SYSTEMS" 2>/dev/null || echo "0")
    IMPACT_CAT_COUNT=$(derby_count "$ACTIVE_DB" "IMPACT_CATEGORIES" 2>/dev/null || echo "0")
    PARAM_COUNT=$(derby_count "$ACTIVE_DB" "PARAMETERS" 2>/dev/null || echo "0")

    echo "  Product systems: ${PS_COUNT:-0}"
    echo "  Impact categories: ${IMPACT_CAT_COUNT:-0}"
    echo "  Parameters defined: ${PARAM_COUNT:-0}"
fi

# ── Write result JSON ─────────────────────────────────────────────────────────
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task": "monte_carlo_uncertainty",
    "openlca_running": $OPENLCA_RUNNING,
    "mc_window_visible": $MC_WINDOW_VISIBLE,
    "mc_in_log": $MC_IN_LOG,
    "db_found": $DB_FOUND,
    "db_size_mb": ${DB_SIZE_MB:-0},
    "ps_count": ${PS_COUNT:-0},
    "impact_cat_count": ${IMPACT_CAT_COUNT:-0},
    "param_count": ${PARAM_COUNT:-0},
    "initial_result_count": ${INITIAL_RESULT_COUNT:-0},
    "current_result_count": ${CURRENT_RESULT_COUNT:-0},
    "mc_file": "$MC_FILE",
    "mc_file_size": ${MC_FILE_SIZE:-0},
    "has_mean_keyword": $HAS_MEAN_KEYWORD,
    "has_std_keyword": $HAS_STD_KEYWORD,
    "has_confidence_keyword": $HAS_CONFIDENCE_KEYWORD,
    "has_gwp_keyword": $HAS_GWP_KEYWORD,
    "mc_data_rows": ${MC_DATA_ROWS:-0},
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
