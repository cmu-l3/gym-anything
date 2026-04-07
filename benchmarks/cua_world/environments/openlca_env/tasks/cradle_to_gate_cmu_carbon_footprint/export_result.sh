#!/bin/bash
# Export script for Cradle-to-Gate CMU Carbon Footprint task
# Collects file existence/size/timestamp/content and Derby DB state into JSON

source /workspace/scripts/task_utils.sh

echo "=== Exporting CMU Carbon Footprint Result ==="

# 1. Capture final screenshot
take_screenshot /tmp/task_end_screenshot.png

# 2. Task timing
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
TASK_END=$(date +%s)
RESULTS_DIR="/home/ga/LCA_Results"
OUTPUT_FILE="$RESULTS_DIR/cmu_footprint.csv"

# 3. Check for result CSV file
FILE_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
FILE_SIZE=0
CONTENT_HAS_GWP="false"
FILE_CONTENT_PREVIEW=""

if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c%s "$OUTPUT_FILE" 2>/dev/null || echo "0")

    FMTIME=$(stat -c%Y "$OUTPUT_FILE" 2>/dev/null || echo "0")
    if [ "$FMTIME" -ge "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi

    if grep -qi "Global Warming\|GWP\|CO2\|climate\|warming" "$OUTPUT_FILE"; then
        CONTENT_HAS_GWP="true"
    fi

    FILE_CONTENT_PREVIEW=$(head -n 10 "$OUTPUT_FILE" 2>/dev/null | base64 -w 0)
fi

# 4. Close OpenLCA to unlock Derby database for querying
close_openlca
sleep 4

# 5. Find the active database (most recently modified)
DB_DIR="/home/ga/openLCA-data-1.4/databases"
ACTIVE_DB=""
LATEST_TIME=0

for db_path in "$DB_DIR"/*/; do
    [ -d "$db_path" ] || continue
    dirname=$(basename "$db_path")
    [[ "$dirname" == .* ]] && continue
    MOD_TIME=$(stat -c %Y "$db_path" 2>/dev/null || echo "0")
    if [ "$MOD_TIME" -gt "$LATEST_TIME" ]; then
        LATEST_TIME="$MOD_TIME"
        ACTIVE_DB="$db_path"
    fi
done

echo "Active database: $ACTIVE_DB"

# 6. Query Derby database for verification data
DB_FOUND="false"
PROCESS_NAMES_DUMP=""
FLOW_NAMES_DUMP=""
PRODUCT_SYSTEM_COUNT=0
PROCESS_COUNT=0
ELEMENTARY_FLOW_FOUND="false"

if [ -n "$ACTIVE_DB" ]; then
    DB_FOUND="true"

    # Query process names matching our expected keywords
    PROC_QUERY="SELECT NAME FROM TBL_PROCESSES WHERE LOWER(NAME) LIKE '%cement%' OR LOWER(NAME) LIKE '%aggregate%' OR LOWER(NAME) LIKE '%concrete%' OR LOWER(NAME) LIKE '%mixing%' OR LOWER(NAME) LIKE '%molding%' OR LOWER(NAME) LIKE '%block%';"
    PROCESS_NAMES_DUMP=$(derby_query "$ACTIVE_DB" "$PROC_QUERY" 2>/dev/null)

    # Total process count
    PROCESS_COUNT=$(derby_count "$ACTIVE_DB" "PROCESSES" 2>/dev/null || echo "0")

    # Query flow names matching our expected keywords
    FLOW_QUERY="SELECT NAME FROM TBL_FLOWS WHERE LOWER(NAME) LIKE '%cement%' OR LOWER(NAME) LIKE '%aggregate%' OR LOWER(NAME) LIKE '%concrete%' OR LOWER(NAME) LIKE '%limestone%' OR LOWER(NAME) LIKE '%coal%' OR LOWER(NAME) LIKE '%gravel%' OR LOWER(NAME) LIKE '%diesel%' OR LOWER(NAME) LIKE '%water%' OR LOWER(NAME) LIKE '%cmu%' OR LOWER(NAME) LIKE '%carbon dioxide%';"
    FLOW_NAMES_DUMP=$(derby_query "$ACTIVE_DB" "$FLOW_QUERY" 2>/dev/null)

    # Check for elementary flow (Carbon Dioxide)
    ELEM_QUERY="SELECT NAME, FLOW_TYPE FROM TBL_FLOWS WHERE LOWER(NAME) LIKE '%carbon dioxide%' AND FLOW_TYPE = 'ELEMENTARY_FLOW';"
    ELEM_RESULT=$(derby_query "$ACTIVE_DB" "$ELEM_QUERY" 2>/dev/null)
    if echo "$ELEM_RESULT" | grep -qi "carbon dioxide"; then
        ELEMENTARY_FLOW_FOUND="true"
    fi

    # Product system count
    PRODUCT_SYSTEM_COUNT=$(derby_count "$ACTIVE_DB" "PRODUCT_SYSTEMS" 2>/dev/null || echo "0")
fi

# 7. Write result JSON using temp file pattern
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "file_exists": $FILE_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "file_size": $FILE_SIZE,
    "content_has_gwp": $CONTENT_HAS_GWP,
    "file_content_b64": "$FILE_CONTENT_PREVIEW",
    "db_found": $DB_FOUND,
    "process_count": ${PROCESS_COUNT:-0},
    "product_system_count": ${PRODUCT_SYSTEM_COUNT:-0},
    "elementary_flow_found": $ELEMENTARY_FLOW_FOUND,
    "process_names_dump": "$(echo "$PROCESS_NAMES_DUMP" | tr '\n' ' ' | sed 's/"/\\"/g')",
    "flow_names_dump": "$(echo "$FLOW_NAMES_DUMP" | tr '\n' ' ' | sed 's/"/\\"/g')"
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="
