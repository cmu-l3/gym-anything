#!/bin/bash
# Export script for Provider Swap Sensitivity task

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

echo "=== Exporting Provider Swap Sensitivity Result ==="

# 1. Capture Final Screenshot
take_screenshot /tmp/task_end_screenshot.png

# 2. Get Timing Info
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# 3. Check Output CSV
CSV_FILE="/home/ga/LCA_Results/provider_sensitivity.csv"
CSV_EXISTS="false"
CSV_SIZE=0
CSV_CREATED_DURING_TASK="false"
CSV_CONTENT=""

if [ -f "$CSV_FILE" ]; then
    CSV_EXISTS="true"
    CSV_SIZE=$(stat -c %s "$CSV_FILE" 2>/dev/null || echo "0")
    
    # Check modification time
    FMTIME=$(stat -c %Y "$CSV_FILE" 2>/dev/null || echo "0")
    if [ "$((FMTIME))" -gt "$((TASK_START))" ]; then
        CSV_CREATED_DURING_TASK="true"
    fi
    
    # Read content for verification (first 10 lines)
    CSV_CONTENT=$(head -n 10 "$CSV_FILE" | base64 -w 0)
fi

# 4. Check OpenLCA State (Derby DB)
# Close app to ensure DB flush
close_openlca
sleep 4

DB_DIR="/home/ga/openLCA-data-1.4/databases"
ACTIVE_DB=""
MAX_SIZE=0

# Find largest DB (likely the one with imported USLCI)
for db_path in "$DB_DIR"/*/; do
    [ -d "$db_path" ] || continue
    DB_SIZE=$(du -sm "$db_path" 2>/dev/null | cut -f1 || echo "0")
    if [ "${DB_SIZE:-0}" -gt "$MAX_SIZE" ]; then
        MAX_SIZE="${DB_SIZE:-0}"
        ACTIVE_DB="$db_path"
    fi
done

PS_COUNT=0
LINK_COUNT=0
IMPACT_CAT_COUNT=0
DB_FOUND="false"

if [ -n "$ACTIVE_DB" ] && [ "${MAX_SIZE:-0}" -gt 10 ]; then
    DB_FOUND="true"
    echo "Examining DB: $(basename "$ACTIVE_DB")"
    
    # Count Product Systems
    PS_COUNT=$(derby_count "$ACTIVE_DB" "PRODUCT_SYSTEMS" 2>/dev/null || echo "0")
    
    # Count Process Links (Evidence of auto-linking)
    # TBL_PROCESS_LINKS stores connections between processes in a system
    LINK_COUNT=$(derby_count "$ACTIVE_DB" "PROCESS_LINKS" 2>/dev/null || echo "0")
    
    # Count Impact Categories (Evidence of LCIA methods)
    IMPACT_CAT_COUNT=$(derby_count "$ACTIVE_DB" "IMPACT_CATEGORIES" 2>/dev/null || echo "0")
fi

# 5. Generate Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "csv_exists": $CSV_EXISTS,
    "csv_size": $CSV_SIZE,
    "csv_created_during_task": $CSV_CREATED_DURING_TASK,
    "csv_content_base64": "$CSV_CONTENT",
    "db_found": $DB_FOUND,
    "db_size_mb": $MAX_SIZE,
    "product_system_count": ${PS_COUNT:-0},
    "process_link_count": ${LINK_COUNT:-0},
    "impact_category_count": ${IMPACT_CAT_COUNT:-0}
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"