#!/bin/bash
set -e
echo "=== Exporting add_farm_equipment results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Get timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)
INITIAL_COUNT=$(cat /tmp/initial_product_count.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Query DB for the specific equipment
# We retrieve name, work_number, created_at, and the associated variant/nature name
echo "Querying database for created equipment..."
DB_RESULT=$(ekylibre_db_query "
    SELECT 
        p.name, 
        p.work_number, 
        EXTRACT(EPOCH FROM p.created_at)::bigint,
        pn.name,
        pn.variety
    FROM products p
    JOIN product_nature_variants pnv ON p.variant_id = pnv.id
    JOIN product_natures pn ON pnv.nature_id = pn.id
    WHERE p.name ILIKE '%Massey Ferguson 7720%'
    ORDER BY p.created_at DESC 
    LIMIT 1;
" 2>/dev/null || true)

# Parse DB Result (Pipe separated by default in some configs, or we use specific delimiter)
# psql -A -t uses '|' as separator by default
# If empty, no record found
RECORD_FOUND="false"
REC_NAME=""
REC_WORK_NUMBER=""
REC_CREATED_AT="0"
REC_NATURE_NAME=""
REC_NATURE_VARIETY=""

if [ -n "$DB_RESULT" ]; then
    RECORD_FOUND="true"
    # Read into variables. IFS=| for psql default output
    IFS='|' read -r REC_NAME REC_WORK_NUMBER REC_CREATED_AT REC_NATURE_NAME REC_NATURE_VARIETY <<< "$DB_RESULT"
fi

# Get final product count
FINAL_COUNT=$(ekylibre_db_query "SELECT count(*) FROM products;" 2>/dev/null || echo "0")
FINAL_COUNT=$(echo "$FINAL_COUNT" | tr -d '[:space:]')

# Check if application (Firefox) is still running
APP_RUNNING="false"
if pgrep -f "firefox" > /dev/null; then
    APP_RUNNING="true"
fi

# Create JSON result
# Use a temp file to avoid permission issues, then move
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)

cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "initial_product_count": $INITIAL_COUNT,
    "final_product_count": $FINAL_COUNT,
    "record_found": $RECORD_FOUND,
    "record": {
        "name": "$(echo $REC_NAME | sed 's/"/\\"/g')",
        "work_number": "$(echo $REC_WORK_NUMBER | sed 's/"/\\"/g')",
        "created_at": $REC_CREATED_AT,
        "nature_name": "$(echo $REC_NATURE_NAME | sed 's/"/\\"/g')",
        "nature_variety": "$(echo $REC_NATURE_VARIETY | sed 's/"/\\"/g')"
    },
    "app_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="