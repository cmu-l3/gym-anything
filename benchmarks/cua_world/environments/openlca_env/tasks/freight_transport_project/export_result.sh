#!/bin/bash
# Export script for Freight Transport Project task

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

echo "=== Exporting Freight Transport Project Result ==="

# 1. Capture Final Screenshot
take_screenshot /tmp/task_end_screenshot.png

# 2. Get Timestamps
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# 3. Locate Exported CSV
EXPECTED_PATH="/home/ga/LCA_Results/transport_project_comparison.csv"
FILE_FOUND="false"
FILE_PATH=""
FILE_SIZE=0
FILE_MTIME=0

# Check specific path first, then search generically
if [ -f "$EXPECTED_PATH" ]; then
    FILE_PATH="$EXPECTED_PATH"
else
    # Search for any recently created CSV in Results or Desktop
    FILE_PATH=$(find /home/ga/LCA_Results /home/ga/Desktop -name "*.csv" -newermt "@$TASK_START" 2>/dev/null | head -1)
fi

CONTENT_CHECK_PASSED="false"
KEYWORDS_FOUND=""

if [ -n "$FILE_PATH" ] && [ -f "$FILE_PATH" ]; then
    FILE_FOUND="true"
    FILE_SIZE=$(stat -c %s "$FILE_PATH")
    FILE_MTIME=$(stat -c %Y "$FILE_PATH")
    
    # Check content for keywords (Truck, Rail, Impact Categories)
    # Using lowercase for loose matching
    CONTENT_LOWER=$(tr '[:upper:]' '[:lower:]' < "$FILE_PATH")
    
    HAS_TRUCK=0
    echo "$CONTENT_LOWER" | grep -qE "truck|lorry|road" && HAS_TRUCK=1
    
    HAS_RAIL=0
    echo "$CONTENT_LOWER" | grep -qE "rail|train|locomotive" && HAS_RAIL=1
    
    HAS_GWP=0
    echo "$CONTENT_LOWER" | grep -qE "global warming|gwp|climate|co2" && HAS_GWP=1
    
    HAS_NUMBERS=0
    grep -qE "[0-9]+\.[0-9]+" "$FILE_PATH" && HAS_NUMBERS=1
    
    KEYWORDS_FOUND="truck:$HAS_TRUCK,rail:$HAS_RAIL,gwp:$HAS_GWP,numbers:$HAS_NUMBERS"
fi

# 4. Check OpenLCA Internal State (Derby DB)
# We need to verify that a "Project" entity was actually created
close_openlca
sleep 4

DB_DIR="/home/ga/openLCA-data-1.4/databases"
ACTIVE_DB=""
MAX_SIZE=0

# Find largest DB (likely the imported one)
for db_path in "$DB_DIR"/*/; do
    [ -d "$db_path" ] || continue
    current_size=$(du -sm "$db_path" 2>/dev/null | cut -f1 || echo "0")
    if [ "${current_size:-0}" -gt "$MAX_SIZE" ]; then
        MAX_SIZE="${current_size:-0}"
        ACTIVE_DB="$db_path"
    fi
done

DB_IMPORTED="false"
PROJECT_COUNT=0
PRODUCT_SYSTEM_COUNT=0
PROCESS_COUNT=0

if [ -n "$ACTIVE_DB" ] && [ "$MAX_SIZE" -gt 10 ]; then
    DB_IMPORTED="true"
    
    # Check for Project entity (TBL_PROJECTS)
    # Note: Table names in OpenLCA Derby are usually uppercase. 
    # Projects are stored in TBL_PROJECTS.
    PROJECT_COUNT=$(derby_count "$ACTIVE_DB" "PROJECTS" 2>/dev/null || echo "0")
    PRODUCT_SYSTEM_COUNT=$(derby_count "$ACTIVE_DB" "PRODUCT_SYSTEMS" 2>/dev/null || echo "0")
    PROCESS_COUNT=$(derby_count "$ACTIVE_DB" "PROCESSES" 2>/dev/null || echo "0")
fi

# 5. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_time": $TASK_START,
    "file_found": $FILE_FOUND,
    "file_path": "$FILE_PATH",
    "file_size": ${FILE_SIZE:-0},
    "file_mtime": ${FILE_MTIME:-0},
    "keywords_found": "$KEYWORDS_FOUND",
    "db_imported": $DB_IMPORTED,
    "project_count": ${PROJECT_COUNT:-0},
    "product_system_count": ${PRODUCT_SYSTEM_COUNT:-0},
    "process_count": ${PROCESS_COUNT:-0},
    "screenshot_path": "/tmp/task_end_screenshot.png"
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="