#!/bin/bash
# Export script for Sankey Supply Chain Viz task

source /workspace/scripts/task_utils.sh

# Fallback definitions
if ! type take_screenshot &>/dev/null; then
    take_screenshot() { DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true; }
fi
if ! type close_openlca &>/dev/null; then
    close_openlca() { pkill -f "openLCA\|openlca" 2>/dev/null || true; sleep 3; }
fi
if ! type derby_count &>/dev/null; then
    derby_count() { echo "0"; }
fi

echo "=== Exporting Sankey Viz Result ==="

# 1. Capture final state
take_screenshot /tmp/task_end_screenshot.png
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# 2. Check for Sankey Image
SANKEY_IMAGE="/home/ga/LCA_Results/sankey_hdpe.png"
SANKEY_EXISTS="false"
SANKEY_SIZE=0
SANKEY_CREATED_DURING="false"

# Check primary path and some variations
for path in "$SANKEY_IMAGE" "/home/ga/LCA_Results/sankey.png" "/home/ga/Desktop/sankey_hdpe.png"; do
    if [ -f "$path" ]; then
        SANKEY_IMAGE="$path" # update if found elsewhere
        SANKEY_EXISTS="true"
        SANKEY_SIZE=$(stat -c %s "$path" 2>/dev/null || echo "0")
        FMTIME=$(stat -c %Y "$path" 2>/dev/null || echo "0")
        if [ "$((FMTIME))" -gt "$((TASK_START))" ]; then
            SANKEY_CREATED_DURING="true"
        fi
        break
    fi
done

# 3. Check for Report
REPORT_FILE="/home/ga/LCA_Results/hdpe_supply_chain_report.txt"
REPORT_EXISTS="false"
REPORT_SIZE=0
REPORT_CONTENT_KEYWORDS=0
REPORT_CREATED_DURING="false"

# Check primary path and variations
for path in "$REPORT_FILE" "/home/ga/LCA_Results/report.txt" "/home/ga/Desktop/report.txt"; do
    if [ -f "$path" ]; then
        REPORT_FILE="$path"
        REPORT_EXISTS="true"
        REPORT_SIZE=$(stat -c %s "$path" 2>/dev/null || echo "0")
        FMTIME=$(stat -c %Y "$path" 2>/dev/null || echo "0")
        if [ "$((FMTIME))" -gt "$((TASK_START))" ]; then
            REPORT_CREATED_DURING="true"
        fi
        
        # Check content
        KEYWORDS_FOUND=0
        grep -qi "GWP\|Global.Warming\|CO2" "$path" && ((KEYWORDS_FOUND++))
        grep -qi "total\|score\|result" "$path" && ((KEYWORDS_FOUND++))
        grep -qi "%\|percent" "$path" && ((KEYWORDS_FOUND++))
        grep -qi "polyethylene\|HDPE\|resin" "$path" && ((KEYWORDS_FOUND++))
        REPORT_CONTENT_KEYWORDS=$KEYWORDS_FOUND
        break
    fi
done

# 4. Check OpenLCA Internal State (Derby)
# We need to close OpenLCA to query Derby safely
close_openlca
sleep 5

DB_DIR="/home/ga/openLCA-data-1.4/databases"
DB_FOUND="false"
DB_SIZE_MB=0
PS_COUNT=0
IMPACT_METHODS_COUNT=0
PROCESS_COUNT=0

# Find the most likely active database (largest or newest)
ACTIVE_DB=""
MAX_SIZE=0
for db_path in "$DB_DIR"/*/; do
    [ -d "$db_path" ] || continue
    CURRENT_SIZE=$(du -sm "$db_path" 2>/dev/null | cut -f1 || echo "0")
    if [ "${CURRENT_SIZE:-0}" -gt "$MAX_SIZE" ]; then
        MAX_SIZE="${CURRENT_SIZE:-0}"
        ACTIVE_DB="$db_path"
    fi
done

if [ -n "$ACTIVE_DB" ] && [ "${MAX_SIZE:-0}" -gt 5 ]; then
    DB_FOUND="true"
    DB_SIZE_MB="$MAX_SIZE"
    echo "Checking database at $ACTIVE_DB ($DB_SIZE_MB MB)"
    
    # Query tables
    PROCESS_COUNT=$(derby_count "$ACTIVE_DB" "PROCESSES" 2>/dev/null || echo "0")
    PS_COUNT=$(derby_count "$ACTIVE_DB" "PRODUCT_SYSTEMS" 2>/dev/null || echo "0")
    IMPACT_METHODS_COUNT=$(derby_count "$ACTIVE_DB" "IMPACT_METHODS" 2>/dev/null || echo "0")
else
    echo "No significant database found."
fi

# 5. Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "sankey_exists": $SANKEY_EXISTS,
    "sankey_size": $SANKEY_SIZE,
    "sankey_created_during": $SANKEY_CREATED_DURING,
    "report_exists": $REPORT_EXISTS,
    "report_size": $REPORT_SIZE,
    "report_created_during": $REPORT_CREATED_DURING,
    "report_keywords_found": $REPORT_CONTENT_KEYWORDS,
    "db_found": $DB_FOUND,
    "db_size_mb": ${DB_SIZE_MB:-0},
    "process_count": ${PROCESS_COUNT:-0},
    "ps_count": ${PS_COUNT:-0},
    "impact_methods_count": ${IMPACT_METHODS_COUNT:-0},
    "task_start": $TASK_START,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result JSON saved to /tmp/task_result.json"
cat /tmp/task_result.json