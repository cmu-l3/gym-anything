#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Calculate Carbon Footprint Result ==="

# Take final screenshot
FINAL_SCREENSHOT="/tmp/openlca_final_screenshot.png"
take_screenshot "$FINAL_SCREENSHOT"
echo "Final screenshot saved to $FINAL_SCREENSHOT"

# ============================================================
# METHOD 1: Check for exported result files
# ============================================================

RESULTS_DIR="/home/ga/LCA_Results"
INITIAL_RESULT_COUNT=$(cat /tmp/initial_result_count 2>/dev/null || echo "0")
CURRENT_RESULT_COUNT=$(ls -1 "$RESULTS_DIR"/* 2>/dev/null | wc -l || echo "0")

NEW_RESULT_FILE=""
RESULT_FILE_CONTENT=""
if [ "$CURRENT_RESULT_COUNT" -gt "$INITIAL_RESULT_COUNT" ]; then
    NEW_RESULT_FILE=$(ls -t "$RESULTS_DIR"/* 2>/dev/null | head -1)
    if [ -n "$NEW_RESULT_FILE" ]; then
        RESULT_FILE_CONTENT=$(head -c 1000 "$NEW_RESULT_FILE" 2>/dev/null || echo "")
    fi
fi

# Also check /tmp and Desktop for result files
for check_dir in "/tmp" "/home/ga/Desktop" "/home/ga"; do
    EXTRA_FILES=$(find "$check_dir" -maxdepth 1 \( -name "*.xlsx" -o -name "*.csv" -o -name "*result*" -o -name "*lcia*" -o -name "*impact*" \) -newer /tmp/task_start_screenshot.png 2>/dev/null | head -3)
    if [ -n "$EXTRA_FILES" ]; then
        echo "Found result files in $check_dir: $EXTRA_FILES"
        if [ -z "$NEW_RESULT_FILE" ]; then
            NEW_RESULT_FILE=$(echo "$EXTRA_FILES" | head -1)
        fi
    fi
done

# ============================================================
# METHOD 2: Check window titles for LCIA results (before close)
# ============================================================

WINDOWS_LIST=$(DISPLAY=:1 wmctrl -l 2>/dev/null || echo "")
OPENLCA_RUNNING="false"
RESULTS_VISIBLE="false"
CALCULATION_EVIDENCE="false"

if echo "$WINDOWS_LIST" | grep -qi "openLCA\|openlca"; then
    OPENLCA_RUNNING="true"
fi

if echo "$WINDOWS_LIST" | grep -qi "result\|impact\|LCIA\|assessment\|calculation"; then
    RESULTS_VISIBLE="true"
fi

if echo "$WINDOWS_LIST" | grep -qi "calculat\|progress\|TRACI\|ReCiPe\|CML"; then
    CALCULATION_EVIDENCE="true"
fi

# ============================================================
# METHOD 3: Check OpenLCA log for calculation evidence
# ============================================================

CALC_IN_LOG="false"
IMPACT_METHOD=""
if [ -f "/tmp/openlca_ga.log" ]; then
    if grep -qi "calculat\|LCIA\|impact.*assess\|TRACI\|ReCiPe\|CML\|global.warming" /tmp/openlca_ga.log 2>/dev/null; then
        CALC_IN_LOG="true"
    fi
    IMPACT_METHOD=$(grep -oP "(?:method|Method|LCIA)[: ]*\K[^\n]*" /tmp/openlca_ga.log 2>/dev/null | tail -1 || echo "")
fi

# ============================================================
# METHOD 4: Close OpenLCA and query Derby
# ============================================================

close_openlca
sleep 3

DB_DIR="/home/ga/openLCA-data-1.4/databases"
DB_RECENTLY_MODIFIED="false"
DB_SIZE=0
PS_COUNT=0

ACTIVE_DB=""
for db_path in "$DB_DIR"/*/; do
    db_name=$(basename "$db_path" 2>/dev/null)
    if echo "$db_name" | grep -qi "uslci\|lci\|analysis"; then
        ACTIVE_DB="$db_path"
        break
    fi
done

if [ -z "$ACTIVE_DB" ]; then
    ACTIVE_DB=$(ls -td "$DB_DIR"/*/ 2>/dev/null | head -1)
fi

if [ -n "$ACTIVE_DB" ] && [ -d "$ACTIVE_DB" ]; then
    DB_SIZE=$(du -sm "$ACTIVE_DB" 2>/dev/null | cut -f1)
    DB_SIZE=${DB_SIZE:-0}

    RECENT_MODS=$(find "$ACTIVE_DB" -mmin -30 -type f 2>/dev/null | wc -l || echo "0")
    if [ "$RECENT_MODS" -gt 5 ]; then
        DB_RECENTLY_MODIFIED="true"
    fi

    # Query Derby for product system count (confirms prerequisite met)
    PS_COUNT=$(derby_count "$ACTIVE_DB" "PRODUCT_SYSTEMS")
    echo "  Product systems in DB: $PS_COUNT"

    # Query Derby for LCIA/impact category tables (direct evidence of calculation)
    # OpenLCA stores LCIA category results in TBL_IMPACT_CATEGORIES
    IMPACT_CATEGORY_COUNT=$(derby_count "$ACTIVE_DB" "IMPACT_CATEGORIES")
    echo "  Impact categories in DB: $IMPACT_CATEGORY_COUNT"
fi

IMPACT_CATEGORY_COUNT=${IMPACT_CATEGORY_COUNT:-0}

# ============================================================
# Create result JSON
# ============================================================

TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "openlca_running": $OPENLCA_RUNNING,
    "results_visible": $RESULTS_VISIBLE,
    "calculation_evidence": $CALCULATION_EVIDENCE,
    "new_result_file": "$NEW_RESULT_FILE",
    "initial_result_count": $INITIAL_RESULT_COUNT,
    "current_result_count": $CURRENT_RESULT_COUNT,
    "db_recently_modified": $DB_RECENTLY_MODIFIED,
    "database_size_mb": $DB_SIZE,
    "ps_count": $PS_COUNT,
    "impact_category_count": $IMPACT_CATEGORY_COUNT,
    "calc_in_log": $CALC_IN_LOG,
    "impact_method": "$IMPACT_METHOD",
    "screenshot_path": "$FINAL_SCREENSHOT",
    "windows_list": "$(echo "$WINDOWS_LIST" | tr '\n' '|')",
    "timestamp": "$(date -Iseconds)"
}
EOF

rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "=== Export Result ==="
cat /tmp/task_result.json
echo ""
echo "=== Export Complete ==="
