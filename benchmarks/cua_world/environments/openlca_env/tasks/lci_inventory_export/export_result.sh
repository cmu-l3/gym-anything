#!/bin/bash
# Export script for LCI Inventory Export task

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

echo "=== Exporting LCI Inventory Export Result ==="

# 1. Capture Final State
take_screenshot /tmp/task_end_screenshot.png
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
INITIAL_DB_COUNT=$(cat /tmp/initial_db_count 2>/dev/null || echo "0")

# 2. Check LCI CSV File
CSV_PATH="/home/ga/LCA_Results/electricity_lci_inventory.csv"
CSV_EXISTS="false"
CSV_SIZE="0"
CSV_ROWS="0"
CSV_HAS_CO2="false"
CSV_HAS_COMPARTMENT="false"
CSV_CREATED_DURING_TASK="false"

if [ -f "$CSV_PATH" ]; then
    CSV_EXISTS="true"
    CSV_SIZE=$(stat -c %s "$CSV_PATH" 2>/dev/null || echo "0")
    
    # Check creation time
    FMTIME=$(stat -c %Y "$CSV_PATH" 2>/dev/null || echo "0")
    if [ "$((FMTIME))" -gt "$((TASK_START))" ]; then
        CSV_CREATED_DURING_TASK="true"
    fi

    # Check content (heuristic)
    CSV_ROWS=$(wc -l < "$CSV_PATH" 2>/dev/null || echo "0")
    
    if grep -qi "Carbon dioxide\|CO2" "$CSV_PATH"; then
        CSV_HAS_CO2="true"
    fi
    
    # Check for compartment keywords (air, water, soil)
    if grep -qi "air\|water\|soil\|resource" "$CSV_PATH"; then
        CSV_HAS_COMPARTMENT="true"
    fi
fi

# 3. Check Summary Report
REPORT_PATH="/home/ga/LCA_Results/lci_summary_report.txt"
REPORT_EXISTS="false"
REPORT_SIZE="0"
REPORT_CREATED_DURING_TASK="false"
REPORT_CONTENT_PREVIEW=""

if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    REPORT_SIZE=$(stat -c %s "$REPORT_PATH" 2>/dev/null || echo "0")
    
    FMTIME=$(stat -c %Y "$REPORT_PATH" 2>/dev/null || echo "0")
    if [ "$((FMTIME))" -gt "$((TASK_START))" ]; then
        REPORT_CREATED_DURING_TASK="true"
    fi
    
    # Read first 1kb for verifier to check
    REPORT_CONTENT_PREVIEW=$(head -c 1024 "$REPORT_PATH" | base64 -w 0)
fi

# 4. Check OpenLCA Application State (Database & Product Systems)
# Close app to unlock Derby DB
close_openlca
sleep 3

DB_DIR="/home/ga/openLCA-data-1.4/databases"
CURRENT_DB_COUNT=$(ls -1d "$DB_DIR"/*/ 2>/dev/null | wc -l || echo "0")
DB_IMPORTED="false"
if [ "$CURRENT_DB_COUNT" -gt "$INITIAL_DB_COUNT" ]; then
    DB_IMPORTED="true"
fi

# Find the active database (largest one likely USLCI)
ACTIVE_DB=""
MAX_SIZE=0
for db_path in "$DB_DIR"/*/; do
    [ -d "$db_path" ] || continue
    S=$(du -sm "$db_path" 2>/dev/null | cut -f1 || echo "0")
    if [ "${S:-0}" -gt "$MAX_SIZE" ]; then
        MAX_SIZE="${S:-0}"
        ACTIVE_DB="$db_path"
    fi
done

PS_COUNT=0
PROCESS_COUNT=0
if [ -n "$ACTIVE_DB" ]; then
    PS_COUNT=$(derby_count "$ACTIVE_DB" "PRODUCT_SYSTEMS" 2>/dev/null || echo "0")
    PROCESS_COUNT=$(derby_count "$ACTIVE_DB" "PROCESSES" 2>/dev/null || echo "0")
fi

# 5. Generate JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "csv_exists": $CSV_EXISTS,
    "csv_size": $CSV_SIZE,
    "csv_rows": $CSV_ROWS,
    "csv_has_co2": $CSV_HAS_CO2,
    "csv_has_compartment": $CSV_HAS_COMPARTMENT,
    "csv_created_during_task": $CSV_CREATED_DURING_TASK,
    "report_exists": $REPORT_EXISTS,
    "report_size": $REPORT_SIZE,
    "report_created_during_task": $REPORT_CREATED_DURING_TASK,
    "report_content_b64": "$REPORT_CONTENT_PREVIEW",
    "db_imported": $DB_IMPORTED,
    "process_count": ${PROCESS_COUNT:-0},
    "ps_count": ${PS_COUNT:-0},
    "screenshot_path": "/tmp/task_end_screenshot.png"
}
EOF

# Move to standard location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"