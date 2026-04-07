#!/bin/bash
echo "=== Exporting add_insurance_company Result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Get current counts
CURRENT_COUNT=$(freemed_query "SELECT COUNT(*) FROM insco;" 2>/dev/null || echo "0")
INITIAL_COUNT=$(cat /tmp/initial_insco_count.txt 2>/dev/null || echo "0")
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

echo "Insurance company count: initial=$INITIAL_COUNT, current=$CURRENT_COUNT"

# Find the record using a delimiter to prevent tab/newline issues
RECORD_DATA=$(freemed_query "SELECT CONCAT_WS('|', id, IFNULL(insconame,''), IFNULL(inscoaddr1,''), IFNULL(inscocity,''), IFNULL(inscostate,''), IFNULL(inscozip,''), IFNULL(inscophone,'')) FROM insco WHERE insconame LIKE '%Blue Cross%' ORDER BY id DESC LIMIT 1" 2>/dev/null)

RECORD_FOUND="false"
INSCO_ID=""
INSCO_NAME=""
INSCO_ADDR1=""
INSCO_CITY=""
INSCO_STATE=""
INSCO_ZIP=""
INSCO_PHONE=""

if [ -n "$RECORD_DATA" ]; then
    RECORD_FOUND="true"
    INSCO_ID=$(echo "$RECORD_DATA" | cut -d'|' -f1)
    INSCO_NAME=$(echo "$RECORD_DATA" | cut -d'|' -f2)
    INSCO_ADDR1=$(echo "$RECORD_DATA" | cut -d'|' -f3)
    INSCO_CITY=$(echo "$RECORD_DATA" | cut -d'|' -f4)
    INSCO_STATE=$(echo "$RECORD_DATA" | cut -d'|' -f5)
    INSCO_ZIP=$(echo "$RECORD_DATA" | cut -d'|' -f6)
    INSCO_PHONE=$(echo "$RECORD_DATA" | cut -d'|' -f7)
    echo "Found record: ID=$INSCO_ID, Name='$INSCO_NAME', City='$INSCO_CITY'"
else
    echo "No matching record found in insco table"
fi

# Escape quotes
INSCO_NAME_ESC=$(echo "$INSCO_NAME" | sed 's/"/\\"/g')
INSCO_ADDR1_ESC=$(echo "$INSCO_ADDR1" | sed 's/"/\\"/g')
INSCO_CITY_ESC=$(echo "$INSCO_CITY" | sed 's/"/\\"/g')
INSCO_STATE_ESC=$(echo "$INSCO_STATE" | sed 's/"/\\"/g')
INSCO_ZIP_ESC=$(echo "$INSCO_ZIP" | sed 's/"/\\"/g')
INSCO_PHONE_ESC=$(echo "$INSCO_PHONE" | sed 's/"/\\"/g')

TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "initial_count": ${INITIAL_COUNT:-0},
    "current_count": ${CURRENT_COUNT:-0},
    "record_found": $RECORD_FOUND,
    "record": {
        "id": "$INSCO_ID",
        "name": "$INSCO_NAME_ESC",
        "addr1": "$INSCO_ADDR1_ESC",
        "city": "$INSCO_CITY_ESC",
        "state": "$INSCO_STATE_ESC",
        "zip": "$INSCO_ZIP_ESC",
        "phone": "$INSCO_PHONE_ESC"
    }
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null
chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="