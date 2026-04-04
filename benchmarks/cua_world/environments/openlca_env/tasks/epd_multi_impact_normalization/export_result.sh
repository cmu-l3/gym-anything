#!/bin/bash
# Export script for EPD Multi-Impact Analysis task

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

echo "=== Exporting EPD Multi-Impact Result ==="

take_screenshot /tmp/task_end_screenshot.png

INITIAL_RESULT_COUNT=$(cat /tmp/initial_result_count 2>/dev/null || echo "0")
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
RESULTS_DIR="/home/ga/LCA_Results"
CURRENT_RESULT_COUNT=$(ls -1 "$RESULTS_DIR"/ 2>/dev/null | wc -l)

# ── Search for EPD result file ────────────────────────────────────────────────
EPD_FILE=""
EPD_FILE_SIZE=0
HAS_GWP_KEYWORD=0
HAS_ACIDIFICATION_KEYWORD=0
HAS_EUTROPHICATION_KEYWORD=0
HAS_OZONE_KEYWORD=0
HAS_ADDITIONAL_CATEGORY=0
CATEGORY_COUNT=0
EPD_ROW_COUNT=0
HAS_TRANSPORT_OR_AG=0

for search_dir in "$RESULTS_DIR" "/home/ga/Desktop" "/home/ga" "/tmp"; do
    for candidate in "$search_dir"/*.csv "$search_dir"/*.xlsx "$search_dir"/*.xls "$search_dir"/*.txt; do
        [ -f "$candidate" ] || continue
        FMTIME=$(stat -c %Y "$candidate" 2>/dev/null || echo "0")
        if [ "$((FMTIME))" -gt "$((TASK_START))" ]; then
            EPD_FILE="$candidate"
            EPD_FILE_SIZE=$(stat -c %s "$candidate" 2>/dev/null || echo "0")
            break 2
        fi
    done
done

if [ -n "$EPD_FILE" ] && [ -f "$EPD_FILE" ]; then
    echo "Found EPD file: $EPD_FILE (${EPD_FILE_SIZE} bytes)"

    # Check for required EPD impact categories
    grep -qi "global.warm\|GWP\|CO2.eq\|climate\|greenhouse\|carbon" "$EPD_FILE" 2>/dev/null && HAS_GWP_KEYWORD=1
    grep -qi "acidif\|SO2\|H\+\|mol.*H\|sulfur\|nitrogen.oxide\|acid" "$EPD_FILE" 2>/dev/null && HAS_ACIDIFICATION_KEYWORD=1
    grep -qi "eutroph\|nitrogen\|phosphor\|N.eq\|P.eq\|nutrient" "$EPD_FILE" 2>/dev/null && HAS_EUTROPHICATION_KEYWORD=1
    grep -qi "ozone.dep\|CFC\|ODP\|stratospheric\|halogen" "$EPD_FILE" 2>/dev/null && HAS_OZONE_KEYWORD=1

    # Check for at least one additional category beyond the 4 required
    grep -qi "smog\|photochem\|VOC\|carcinogen\|non.*carcinogen\|ecotox\|human.health\|particulate\|fossil.fuel\|land.use\|water" "$EPD_FILE" 2>/dev/null && HAS_ADDITIONAL_CATEGORY=1

    # Check for transport or agricultural domain keywords
    grep -qi "transport\|truck\|lorry\|freight\|rail\|barge\|pipeline\|corn\|soybean\|wheat\|crop\|farm\|agri\|livestock" "$EPD_FILE" 2>/dev/null && HAS_TRANSPORT_OR_AG=1

    # Count distinct impact category mentions (rough proxy for coverage)
    CATEGORY_COUNT=$((HAS_GWP_KEYWORD + HAS_ACIDIFICATION_KEYWORD + HAS_EUTROPHICATION_KEYWORD + HAS_OZONE_KEYWORD + HAS_ADDITIONAL_CATEGORY))
    EPD_ROW_COUNT=$(grep -c "[0-9]" "$EPD_FILE" 2>/dev/null)
    [ -z "$EPD_ROW_COUNT" ] && EPD_ROW_COUNT=0

    echo "  GWP: $HAS_GWP_KEYWORD | Acid: $HAS_ACIDIFICATION_KEYWORD | Eutroph: $HAS_EUTROPHICATION_KEYWORD"
    echo "  Ozone: $HAS_OZONE_KEYWORD | Additional: $HAS_ADDITIONAL_CATEGORY"
    echo "  Transport/Ag domain: $HAS_TRANSPORT_OR_AG"
    echo "  Category coverage: $CATEGORY_COUNT/5"
    echo "  Data rows: $EPD_ROW_COUNT"
fi

# ── Window state ──────────────────────────────────────────────────────────────
WINDOWS_LIST=$(DISPLAY=:1 wmctrl -l 2>/dev/null || echo "")
OPENLCA_RUNNING="false"
MULTI_IMPACT_VISIBLE="false"
if echo "$WINDOWS_LIST" | grep -qi "openLCA\|openlca"; then OPENLCA_RUNNING="true"; fi
if echo "$WINDOWS_LIST" | grep -qi "result\|impact\|LCIA\|assessment\|TRACI\|ReCiPe"; then MULTI_IMPACT_VISIBLE="true"; fi

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
    "task": "epd_multi_impact_normalization",
    "openlca_running": $OPENLCA_RUNNING,
    "multi_impact_visible": $MULTI_IMPACT_VISIBLE,
    "db_found": $DB_FOUND,
    "db_size_mb": ${DB_SIZE_MB:-0},
    "ps_count": ${PS_COUNT:-0},
    "impact_cat_count": ${IMPACT_CAT_COUNT:-0},
    "initial_result_count": ${INITIAL_RESULT_COUNT:-0},
    "current_result_count": ${CURRENT_RESULT_COUNT:-0},
    "epd_file": "$EPD_FILE",
    "epd_file_size": ${EPD_FILE_SIZE:-0},
    "has_gwp_keyword": $HAS_GWP_KEYWORD,
    "has_acidification_keyword": $HAS_ACIDIFICATION_KEYWORD,
    "has_eutrophication_keyword": $HAS_EUTROPHICATION_KEYWORD,
    "has_ozone_keyword": $HAS_OZONE_KEYWORD,
    "has_additional_category": $HAS_ADDITIONAL_CATEGORY,
    "has_transport_or_ag": $HAS_TRANSPORT_OR_AG,
    "category_count": ${CATEGORY_COUNT:-0},
    "epd_row_count": ${EPD_ROW_COUNT:-0},
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
