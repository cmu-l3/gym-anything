#!/bin/bash
# Export script for Add ICD Code task

echo "=== Exporting Add ICD Code Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_icd_end.png

# Get current ICD code count
CURRENT_COUNT=$(freemed_query "SELECT COUNT(*) FROM icdcodes" 2>/dev/null || echo "0")
INITIAL_COUNT=$(cat /tmp/initial_icd_count 2>/dev/null || echo "0")

echo "ICD Code count: initial=$INITIAL_COUNT, current=$CURRENT_COUNT"

# Check if the target code was added
echo "Checking for ICD code 'G47.33'..."
ICD_DATA=$(freemed_query "SELECT icdcode, icddescrip FROM icdcodes WHERE TRIM(icdcode)='G47.33' LIMIT 1" 2>/dev/null)

CODE_FOUND="false"
STORED_CODE=""
STORED_DESCRIP=""

if [ -n "$ICD_DATA" ]; then
    CODE_FOUND="true"
    STORED_CODE=$(echo "$ICD_DATA" | cut -f1)
    STORED_DESCRIP=$(echo "$ICD_DATA" | cut -f2)
    echo "ICD Code found: Code='$STORED_CODE', Description='$STORED_DESCRIP'"
else
    # Try a broader search just in case they typed it slightly wrong but we can capture what they did
    echo "Exact code 'G47.33' not found. Searching for similar entries..."
    ICD_DATA_SIMILAR=$(freemed_query "SELECT icdcode, icddescrip FROM icdcodes WHERE icddescrip LIKE '%sleep apnea%' ORDER BY id DESC LIMIT 1" 2>/dev/null)
    if [ -n "$ICD_DATA_SIMILAR" ]; then
        CODE_FOUND="true"
        STORED_CODE=$(echo "$ICD_DATA_SIMILAR" | cut -f1)
        STORED_DESCRIP=$(echo "$ICD_DATA_SIMILAR" | cut -f2)
        echo "Found related code instead: Code='$STORED_CODE', Description='$STORED_DESCRIP'"
    else
        echo "No matching ICD code or description found in database."
    fi
fi

# Escape special characters for JSON
STORED_CODE_ESC=$(echo "$STORED_CODE" | sed 's/"/\\"/g' | sed 's/\\/\\\\/g')
STORED_DESCRIP_ESC=$(echo "$STORED_DESCRIP" | sed 's/"/\\"/g' | sed 's/\\/\\\\/g')

# Write JSON result securely
TEMP_JSON=$(mktemp /tmp/add_icd_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "initial_count": ${INITIAL_COUNT:-0},
    "current_count": ${CURRENT_COUNT:-0},
    "code_found": $CODE_FOUND,
    "entry": {
        "code": "$STORED_CODE_ESC",
        "description": "$STORED_DESCRIP_ESC"
    },
    "export_timestamp": "$(date -Iseconds)"
}
EOF

rm -f /tmp/add_icd_result.json 2>/dev/null || sudo rm -f /tmp/add_icd_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/add_icd_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/add_icd_result.json
chmod 666 /tmp/add_icd_result.json 2>/dev/null || sudo chmod 666 /tmp/add_icd_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Result JSON saved to /tmp/add_icd_result.json"
cat /tmp/add_icd_result.json

echo ""
echo "=== Export Complete ==="