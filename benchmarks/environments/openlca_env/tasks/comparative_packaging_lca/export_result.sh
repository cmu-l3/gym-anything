#!/bin/bash
# Export script for Comparative Packaging LCA task
# Post-task hook: runs AFTER the agent finishes

source /workspace/scripts/task_utils.sh

# Fallback definitions
if ! type take_screenshot &>/dev/null; then
    take_screenshot() { DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true; }
fi
if ! type derby_count &>/dev/null; then
    derby_count() { echo "0"; }
fi
if ! type close_openlca &>/dev/null; then
    close_openlca() { pkill -f "openLCA\|openlca" 2>/dev/null || true; sleep 3; }
fi

echo "=== Exporting Comparative Packaging LCA Result ==="

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png
echo "Final screenshot saved"

# Read baseline state
INITIAL_RESULT_COUNT=$(cat /tmp/initial_result_count 2>/dev/null || echo "0")
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# ============================================================
# CHECK 1: Look for result files in LCA_Results and Desktop
# ============================================================
RESULTS_DIR="/home/ga/LCA_Results"
CURRENT_RESULT_COUNT=$(ls -1 "$RESULTS_DIR"/ 2>/dev/null | wc -l)

# Search for packaging comparison files (flexible name matching)
COMPARISON_FILE=""
COMPARISON_FILE_SIZE=0
HAS_GLASS_KEYWORD=0
HAS_ALUMINUM_KEYWORD=0
HAS_GWP_KEYWORD=0
COMPARISON_ROW_COUNT=0

# Search LCA_Results and Desktop for CSV/Excel files
for search_dir in "$RESULTS_DIR" "/home/ga/Desktop" "/home/ga" "/tmp"; do
    for candidate in "$search_dir"/*.csv "$search_dir"/*.xlsx "$search_dir"/*.xls "$search_dir"/*.txt; do
        [ -f "$candidate" ] || continue
        # Check if it's a new file (modified after task start)
        FMTIME=$(stat -c %Y "$candidate" 2>/dev/null || echo "0")
        if [ "$((FMTIME))" -gt "$((TASK_START))" ]; then
            COMPARISON_FILE="$candidate"
            COMPARISON_FILE_SIZE=$(stat -c %s "$candidate" 2>/dev/null || echo "0")
            break 2
        fi
    done
done

# If we found a file, check its content
if [ -n "$COMPARISON_FILE" ] && [ -f "$COMPARISON_FILE" ]; then
    echo "Found result file: $COMPARISON_FILE (${COMPARISON_FILE_SIZE} bytes)"

    # Check for packaging keywords (case-insensitive)
    grep -qi "glass\|quartz\|silica.*container\|container.*glass" "$COMPARISON_FILE" 2>/dev/null && HAS_GLASS_KEYWORD=1
    grep -qi "aluminum\|aluminium\|alum\|can\|tinplate\|metal.*container" "$COMPARISON_FILE" 2>/dev/null && HAS_ALUMINUM_KEYWORD=1
    grep -qi "global.warm\|GWP\|CO2\|climate\|greenhouse" "$COMPARISON_FILE" 2>/dev/null && HAS_GWP_KEYWORD=1

    # Count non-empty rows (proxy for data completeness)
    COMPARISON_ROW_COUNT=$(grep -c "[0-9]" "$COMPARISON_FILE" 2>/dev/null)
    [ -z "$COMPARISON_ROW_COUNT" ] && COMPARISON_ROW_COUNT=0
    echo "  Glass keyword: $HAS_GLASS_KEYWORD"
    echo "  Aluminum keyword: $HAS_ALUMINUM_KEYWORD"
    echo "  GWP keyword: $HAS_GWP_KEYWORD"
    echo "  Data rows: $COMPARISON_ROW_COUNT"
else
    echo "No comparison result file found"
    COMPARISON_FILE=""
fi

# ============================================================
# CHECK 2: Window state before closing
# ============================================================
WINDOWS_LIST=$(DISPLAY=:1 wmctrl -l 2>/dev/null || echo "")
OPENLCA_RUNNING="false"
LCIA_RESULTS_VISIBLE="false"

if echo "$WINDOWS_LIST" | grep -qi "openLCA\|openlca"; then
    OPENLCA_RUNNING="true"
fi
if echo "$WINDOWS_LIST" | grep -qi "result\|impact\|LCIA\|assessment"; then
    LCIA_RESULTS_VISIBLE="true"
fi

# ============================================================
# CHECK 3: Close OpenLCA and query Derby database
# ============================================================
close_openlca
sleep 4

DB_DIR="/home/ga/openLCA-data-1.4/databases"
PS_COUNT=0
IMPACT_CAT_COUNT=0
DB_SIZE_MB=0
DB_FOUND="false"

# Find the active database (largest, most likely the USLCI import)
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

if [ -n "$ACTIVE_DB" ] && [ -d "$ACTIVE_DB" ] && [ "${MAX_SIZE:-0}" -gt 5 ]; then
    DB_FOUND="true"
    DB_SIZE_MB="$MAX_SIZE"
    echo "Active database: $(basename "$ACTIVE_DB") (${DB_SIZE_MB}MB)"

    # Query Derby for product system count
    PS_COUNT=$(derby_count "$ACTIVE_DB" "PRODUCT_SYSTEMS" 2>/dev/null || echo "0")
    PS_COUNT="${PS_COUNT:-0}"
    echo "  Product systems: $PS_COUNT"

    # Query Derby for impact categories (LCIA methods imported)
    IMPACT_CAT_COUNT=$(derby_count "$ACTIVE_DB" "IMPACT_CATEGORIES" 2>/dev/null || echo "0")
    IMPACT_CAT_COUNT="${IMPACT_CAT_COUNT:-0}"
    echo "  Impact categories: $IMPACT_CAT_COUNT"
else
    echo "No substantial database found"
fi

# ============================================================
# Write result JSON
# ============================================================
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task": "comparative_packaging_lca",
    "openlca_running": $OPENLCA_RUNNING,
    "lcia_results_visible": $LCIA_RESULTS_VISIBLE,
    "db_found": $DB_FOUND,
    "db_size_mb": ${DB_SIZE_MB:-0},
    "ps_count": ${PS_COUNT:-0},
    "impact_cat_count": ${IMPACT_CAT_COUNT:-0},
    "initial_result_count": ${INITIAL_RESULT_COUNT:-0},
    "current_result_count": ${CURRENT_RESULT_COUNT:-0},
    "comparison_file": "$COMPARISON_FILE",
    "comparison_file_size": ${COMPARISON_FILE_SIZE:-0},
    "has_glass_keyword": $HAS_GLASS_KEYWORD,
    "has_aluminum_keyword": $HAS_ALUMINUM_KEYWORD,
    "has_gwp_keyword": $HAS_GWP_KEYWORD,
    "comparison_row_count": ${COMPARISON_ROW_COUNT:-0},
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
