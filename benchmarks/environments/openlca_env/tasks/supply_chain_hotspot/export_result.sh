#!/bin/bash
# Export script for Supply Chain Hotspot Analysis task

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

echo "=== Exporting Supply Chain Hotspot Result ==="

take_screenshot /tmp/task_end_screenshot.png

INITIAL_RESULT_COUNT=$(cat /tmp/initial_result_count 2>/dev/null || echo "0")
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
RESULTS_DIR="/home/ga/LCA_Results"
CURRENT_RESULT_COUNT=$(ls -1 "$RESULTS_DIR"/ 2>/dev/null | wc -l)

# ── Search for hotspot analysis file ─────────────────────────────────────────
HOTSPOT_FILE=""
HOTSPOT_FILE_SIZE=0
HAS_CEMENT_KEYWORD=0
HAS_PERCENT_KEYWORD=0
HAS_PROCESS_KEYWORD=0
HAS_GWP_KEYWORD=0
HOTSPOT_ROW_COUNT=0

for search_dir in "$RESULTS_DIR" "/home/ga/Desktop" "/home/ga" "/tmp"; do
    for candidate in "$search_dir"/*.csv "$search_dir"/*.xlsx "$search_dir"/*.xls "$search_dir"/*.txt; do
        [ -f "$candidate" ] || continue
        FMTIME=$(stat -c %Y "$candidate" 2>/dev/null || echo "0")
        if [ "$((FMTIME))" -gt "$((TASK_START))" ]; then
            HOTSPOT_FILE="$candidate"
            HOTSPOT_FILE_SIZE=$(stat -c %s "$candidate" 2>/dev/null || echo "0")
            break 2
        fi
    done
done

if [ -n "$HOTSPOT_FILE" ] && [ -f "$HOTSPOT_FILE" ]; then
    echo "Found hotspot file: $HOTSPOT_FILE (${HOTSPOT_FILE_SIZE} bytes)"
    # Check for cement/concrete domain keywords
    grep -qi "cement\|concrete\|clinker\|limestone\|aggregate\|kiln\|fly.ash\|mortar\|masonry\|portland" "$HOTSPOT_FILE" 2>/dev/null && HAS_CEMENT_KEYWORD=1
    # Check for percentage/contribution data
    grep -qE "[0-9]+\.?[0-9]*\s*%" "$HOTSPOT_FILE" 2>/dev/null && HAS_PERCENT_KEYWORD=1
    # Check for process/supply chain terminology
    grep -qi "process\|contribution\|supply.chain\|upstream\|hotspot\|share" "$HOTSPOT_FILE" 2>/dev/null && HAS_PROCESS_KEYWORD=1
    # Check for GWP keywords
    grep -qi "global.warm\|GWP\|CO2\|climate\|greenhouse\|carbon" "$HOTSPOT_FILE" 2>/dev/null && HAS_GWP_KEYWORD=1
    # Count data rows
    HOTSPOT_ROW_COUNT=$(grep -c "[0-9]" "$HOTSPOT_FILE" 2>/dev/null)
    [ -z "$HOTSPOT_ROW_COUNT" ] && HOTSPOT_ROW_COUNT=0
    echo "  Cement keyword: $HAS_CEMENT_KEYWORD"
    echo "  Percentage data: $HAS_PERCENT_KEYWORD"
    echo "  Process keyword: $HAS_PROCESS_KEYWORD"
    echo "  GWP keyword: $HAS_GWP_KEYWORD"
    echo "  Data rows: $HOTSPOT_ROW_COUNT"
fi

# ── Window state ──────────────────────────────────────────────────────────────
WINDOWS_LIST=$(DISPLAY=:1 wmctrl -l 2>/dev/null || echo "")
OPENLCA_RUNNING="false"
CONTRIBUTION_VISIBLE="false"
if echo "$WINDOWS_LIST" | grep -qi "openLCA\|openlca"; then OPENLCA_RUNNING="true"; fi
if echo "$WINDOWS_LIST" | grep -qi "contribution\|sankey\|upstream\|tree\|result"; then CONTRIBUTION_VISIBLE="true"; fi

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
    "task": "supply_chain_hotspot",
    "openlca_running": $OPENLCA_RUNNING,
    "contribution_visible": $CONTRIBUTION_VISIBLE,
    "db_found": $DB_FOUND,
    "db_size_mb": ${DB_SIZE_MB:-0},
    "ps_count": ${PS_COUNT:-0},
    "impact_cat_count": ${IMPACT_CAT_COUNT:-0},
    "initial_result_count": ${INITIAL_RESULT_COUNT:-0},
    "current_result_count": ${CURRENT_RESULT_COUNT:-0},
    "hotspot_file": "$HOTSPOT_FILE",
    "hotspot_file_size": ${HOTSPOT_FILE_SIZE:-0},
    "has_cement_keyword": $HAS_CEMENT_KEYWORD,
    "has_percent_keyword": $HAS_PERCENT_KEYWORD,
    "has_process_keyword": $HAS_PROCESS_KEYWORD,
    "has_gwp_keyword": $HAS_GWP_KEYWORD,
    "hotspot_row_count": ${HOTSPOT_ROW_COUNT:-0},
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
