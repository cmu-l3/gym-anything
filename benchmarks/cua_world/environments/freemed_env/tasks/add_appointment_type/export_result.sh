#!/bin/bash
# Export script for Configure Appointment Type task

echo "=== Exporting Configure Appointment Type Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Retrieve initial row count
INITIAL_TOTAL_ROWS=$(cat /tmp/initial_db_rows.txt 2>/dev/null || echo "0")

# ================================================================
# EVALUATE FINAL DATABASE STATE
# ================================================================
echo "Querying database for task artifacts..."
DUMP_FILE="/tmp/freemed_final_dump.sql"
mysqldump -u freemed -pfreemed freemed --skip-extended-insert > "$DUMP_FILE" 2>/dev/null

# Calculate final DB row count
FINAL_TOTAL_ROWS=$(grep -c "^INSERT INTO" "$DUMP_FILE" || echo "0")

# Search for the newly created appointment type
# Using case-insensitive search to locate the full line where the string was inserted
MATCHING_LINE=$(grep -i "Weight Management Consult" "$DUMP_FILE" | head -1)

RECORD_FOUND="false"
DURATION_FOUND="false"
TABLE_NAME="none"

if [ -n "$MATCHING_LINE" ]; then
    RECORD_FOUND="true"
    
    # Check if the number 45 exists on the same insertion row surrounded by non-alphanumerics
    # (handles mysqldump output safely: '..., 45, ...' or '...,45,...')
    if echo "$MATCHING_LINE" | grep -qE "[^0-9a-zA-Z]45[^0-9a-zA-Z]"; then
        DURATION_FOUND="true"
    fi
    
    # Extract the table it was inserted into for verbosity/auditing
    TABLE_NAME=$(echo "$MATCHING_LINE" | grep -oP 'INSERT INTO `\K[^`]+' || echo "unknown")
    
    echo "SUCCESS: Found target string inside table '$TABLE_NAME'."
    echo "Duration correctness: $DURATION_FOUND"
else
    echo "FAILURE: Target string 'Weight Management Consult' not found in database."
fi

# ================================================================
# COMPILE EXPORT JSON
# ================================================================
TEMP_JSON=$(mktemp /tmp/add_appt_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "record_found": $RECORD_FOUND,
    "duration_found": $DURATION_FOUND,
    "table_name": "$TABLE_NAME",
    "initial_db_rows": $INITIAL_TOTAL_ROWS,
    "final_db_rows": $FINAL_TOTAL_ROWS,
    "export_timestamp": "$(date -Iseconds)"
}
EOF

# Safely copy to standard path and adjust permissions
rm -f /tmp/appt_task_result.json 2>/dev/null || sudo rm -f /tmp/appt_task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/appt_task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/appt_task_result.json
chmod 666 /tmp/appt_task_result.json 2>/dev/null || sudo chmod 666 /tmp/appt_task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Result JSON saved to /tmp/appt_task_result.json"
cat /tmp/appt_task_result.json
echo ""
echo "=== Export Complete ==="