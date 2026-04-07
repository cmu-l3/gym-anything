#!/bin/bash
echo "=== Exporting add_employer result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final_state.png

# Load stored state
EMPLOYER_TABLE=$(cat /tmp/employer_table_name.txt 2>/dev/null || echo "")
INITIAL_COUNT=$(cat /tmp/initial_employer_count.txt 2>/dev/null || echo "0")

CURRENT_COUNT="0"
RECORD_FOUND="false"
RECORD_DATA=""

if [ -n "$EMPLOYER_TABLE" ]; then
    # Get current employer count
    CURRENT_COUNT=$(mysql -u freemed -pfreemed freemed -N -e "SELECT COUNT(*) FROM $EMPLOYER_TABLE" 2>/dev/null || echo "0")
    
    # Dump entire table and search for 'meridian' (immune to column name variations)
    RECORD_DATA=$(mysql -u freemed -pfreemed freemed -N -e "SELECT * FROM $EMPLOYER_TABLE" 2>/dev/null | grep -i "meridian" | head -1)
    
    if [ -n "$RECORD_DATA" ]; then
        RECORD_FOUND="true"
    fi
fi

# Escape quotes and tabs for JSON output
if [ -n "$RECORD_DATA" ]; then
    RECORD_DATA_ESCAPED=$(echo "$RECORD_DATA" | sed 's/\\/\\\\/g' | sed 's/"/\\"/g' | sed 's/\t/ \\t /g' | tr -d '\n' | tr -d '\r')
else
    RECORD_DATA_ESCAPED=""
fi

# Create JSON result
TEMP_JSON=$(mktemp /tmp/add_employer_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "table_name": "$EMPLOYER_TABLE",
    "initial_count": ${INITIAL_COUNT:-0},
    "current_count": ${CURRENT_COUNT:-0},
    "record_found": $RECORD_FOUND,
    "record_data": "$RECORD_DATA_ESCAPED",
    "export_timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location securely
rm -f /tmp/add_employer_result.json 2>/dev/null || sudo rm -f /tmp/add_employer_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/add_employer_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/add_employer_result.json
chmod 666 /tmp/add_employer_result.json 2>/dev/null || sudo chmod 666 /tmp/add_employer_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result JSON saved to /tmp/add_employer_result.json"
cat /tmp/add_employer_result.json

echo "=== Export complete ==="