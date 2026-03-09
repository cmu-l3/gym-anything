#!/bin/bash
# Export script for Add Public Holiday task

echo "=== Exporting Task Results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Target details
TARGET_DATE="2026-05-18"
TARGET_NAME_PART="Victoria"

# 1. Query the database for the specific holiday record
echo "Checking database for holiday record..."
# We select name, date_holiday. Note: table schema might vary slightly by version, 
# but 'public_holiday' is standard in OSCAR.
RECORD=$(oscar_query "SELECT name, date_holiday FROM public_holiday WHERE date_holiday='$TARGET_DATE'" 2>/dev/null)

RECORD_FOUND="false"
FOUND_NAME=""
FOUND_DATE=""

if [ -n "$RECORD" ]; then
    RECORD_FOUND="true"
    FOUND_NAME=$(echo "$RECORD" | cut -f1)
    FOUND_DATE=$(echo "$RECORD" | cut -f2)
    echo "Found record: Name='$FOUND_NAME', Date='$FOUND_DATE'"
else
    echo "No record found for date $TARGET_DATE"
    # Fallback check: look for name in 2026 just in case user got date wrong
    FALLBACK=$(oscar_query "SELECT name, date_holiday FROM public_holiday WHERE name LIKE '%$TARGET_NAME_PART%' AND date_holiday LIKE '2026%'" 2>/dev/null)
    if [ -n "$FALLBACK" ]; then
        echo "Found potential mismatch record: $FALLBACK"
    fi
fi

# 2. Check total count of holidays (sanity check)
TOTAL_COUNT=$(oscar_query "SELECT COUNT(*) FROM public_holiday" || echo "0")

# 3. Capture final screenshot
take_screenshot /tmp/task_final.png

# 4. Create JSON result
TEMP_JSON=$(mktemp /tmp/holiday_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "record_found": $RECORD_FOUND,
    "found_name": "$(echo "$FOUND_NAME" | sed 's/"/\\"/g')",
    "found_date": "$FOUND_DATE",
    "target_date": "$TARGET_DATE",
    "total_holidays": $TOTAL_COUNT,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location with permissions
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="