#!/bin/bash
# Export script for Supply Chain Dependency Mapping task

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

echo "=== Exporting Supply Chain Dependency Result ==="

# 1. Take final screenshot
take_screenshot /tmp/task_end_screenshot.png
echo "Final screenshot saved"

# 2. Gather file evidence
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
OUTPUT_FILE="/home/ga/LCA_Results/natural_gas_dependency.csv"
FILE_EXISTS="false"
FILE_SIZE=0
FILE_CREATED_DURING_TASK="false"
ROW_COUNT=0

if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$OUTPUT_FILE" 2>/dev/null || echo "0")
    
    # Check timestamp
    FILE_MTIME=$(stat -c %Y "$OUTPUT_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi

    # Count rows (excluding header roughly)
    ROW_COUNT=$(grep -c . "$OUTPUT_FILE" || echo "0")
fi

# 3. Check OpenLCA state (Database Import)
# We need to close OpenLCA to safely query the Derby DB
WINDOWS_LIST=$(DISPLAY=:1 wmctrl -l 2>/dev/null || echo "")
OPENLCA_RUNNING="false"
if echo "$WINDOWS_LIST" | grep -qi "openLCA\|openlca"; then
    OPENLCA_RUNNING="true"
fi

echo "Closing OpenLCA for DB verification..."
close_openlca
sleep 3

# Find active database
DB_DIR="/home/ga/openLCA-data-1.4/databases"
PROCESS_COUNT=0
FLOW_COUNT=0
DB_NAME=""

# Find the largest/most recent database
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

if [ -n "$ACTIVE_DB" ]; then
    DB_NAME=$(basename "$ACTIVE_DB")
    # Verify it has content (processes/flows)
    PROCESS_COUNT=$(derby_count "$ACTIVE_DB" "PROCESSES" 2>/dev/null || echo "0")
    FLOW_COUNT=$(derby_count "$ACTIVE_DB" "FLOWS" 2>/dev/null || echo "0")
fi

# 4. Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_time": $TASK_START,
    "file_exists": $FILE_EXISTS,
    "file_path": "$OUTPUT_FILE",
    "file_size": $FILE_SIZE,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "csv_row_count": $ROW_COUNT,
    "openlca_was_running": $OPENLCA_RUNNING,
    "db_process_count": ${PROCESS_COUNT:-0},
    "db_flow_count": ${FLOW_COUNT:-0},
    "db_name": "$DB_NAME",
    "screenshot_path": "/tmp/task_end_screenshot.png"
}
EOF

# Safe move
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="