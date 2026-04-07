#!/bin/bash
# Export results for add_application_log_source task

source /workspace/scripts/task_utils.sh 2>/dev/null || { echo "Failed to source task_utils"; exit 1; }

echo "=== Exporting task results ==="

TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_COUNT=$(cat /tmp/initial_device_count.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# =====================================================
# Verification: Check Database for New Source
# =====================================================

# 1. Check if the specific source 'webserver-01' exists
# We query the DeviceTable for the display name
SOURCE_FOUND="false"
SOURCE_DETAILS=""

# Query for the specific host/display name
DB_RESULT=$(ela_db_query "SELECT device_id, displayname, type FROM devicetable WHERE displayname ILIKE '%webserver-01%'" 2>/dev/null)

if [ -n "$DB_RESULT" ]; then
    SOURCE_FOUND="true"
    SOURCE_DETAILS="$DB_RESULT"
    echo "Found source in DB: $DB_RESULT"
fi

# 2. Check for the specific file path in file monitoring tables (if accessible)
# Or infer from the device count increase if exact match fails
CURRENT_COUNT=$(ela_db_query "SELECT COUNT(*) FROM devicetable" 2>/dev/null || echo "0")
COUNT_DIFF=$((CURRENT_COUNT - INITIAL_COUNT))

# 3. Double check via API (if DB query is restricted or complex schema)
# This is a backup check
API_RESULT_JSON=$(ela_api_call "/event/api/v1/devices" "GET" 2>/dev/null)

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "initial_device_count": $INITIAL_COUNT,
    "current_device_count": $CURRENT_COUNT,
    "count_increase": $COUNT_DIFF,
    "source_found_in_db": $SOURCE_FOUND,
    "source_details": "$SOURCE_DETAILS",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="