#!/bin/bash
# Export script for add_place_of_service_code task

echo "=== Exporting add_place_of_service_code Result ==="

source /workspace/scripts/task_utils.sh

# Take final proof screenshot
take_screenshot /tmp/task_end_screenshot.png

# Identify the Place of Service table
TABLE_NAME=$(mysql -u freemed -pfreemed freemed -N -e "SHOW TABLES LIKE 'pos';" 2>/dev/null)
if [ -z "$TABLE_NAME" ]; then
    TABLE_NAME=$(mysql -u freemed -pfreemed freemed -N -e "SHOW TABLES LIKE '%place%service%';" 2>/dev/null | head -1)
fi

CURRENT_COUNT="0"
if [ -n "$TABLE_NAME" ]; then
    CURRENT_COUNT=$(mysql -u freemed -pfreemed freemed -N -e "SELECT COUNT(*) FROM \`$TABLE_NAME\`" 2>/dev/null || echo "0")
    
    # Dump the entire POS table to a TSV file for flexible python parsing
    # This avoids hardcoding column names which might vary slightly across FreeMED versions
    mysql -u freemed -pfreemed freemed -e "SELECT * FROM \`$TABLE_NAME\`" -B > /tmp/pos_dump.tsv 2>/dev/null || touch /tmp/pos_dump.tsv
else
    echo "Warning: POS table could not be identified."
    touch /tmp/pos_dump.tsv
fi

INITIAL_COUNT=$(cat /tmp/initial_pos_count 2>/dev/null || echo "0")
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

echo "POS count: initial=$INITIAL_COUNT, current=$CURRENT_COUNT"

# Create JSON metadata result (temp file avoids permission issues during transfer)
TEMP_JSON=$(mktemp /tmp/pos_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "initial_count": ${INITIAL_COUNT:-0},
    "current_count": ${CURRENT_COUNT:-0},
    "table_name": "${TABLE_NAME:-unknown}",
    "task_start": ${TASK_START:-0},
    "export_timestamp": $(date +%s)
}
EOF

# Make files accessible for verifier copy_from_env
rm -f /tmp/pos_result.json 2>/dev/null || sudo rm -f /tmp/pos_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/pos_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/pos_result.json
chmod 666 /tmp/pos_result.json /tmp/pos_dump.tsv 2>/dev/null || sudo chmod 666 /tmp/pos_result.json /tmp/pos_dump.tsv 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Results dumped successfully."
echo "=== Export Complete ==="