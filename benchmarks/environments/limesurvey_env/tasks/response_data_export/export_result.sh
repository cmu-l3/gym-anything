#!/bin/bash
set -e

echo "=== Exporting Response Data Export Result ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Define expected paths
CSV_PATH="/home/ga/Downloads/q3_customer_experience_responses.csv"
LSS_PATH="/home/ga/Downloads/q3_customer_experience_structure.lss"

# Check CSV
CSV_EXISTS=false
CSV_LINES=0
CSV_SIZE=0
CSV_CREATED_DURING_TASK=false
CSV_HEADER_VALID=false
RESPONSE_COUNT_MATCH=false

if [ -f "$CSV_PATH" ]; then
    CSV_EXISTS=true
    CSV_SIZE=$(stat -c %s "$CSV_PATH")
    CSV_MTIME=$(stat -c %Y "$CSV_PATH")
    
    # Check timestamp
    if [ "$CSV_MTIME" -gt "$TASK_START" ]; then
        CSV_CREATED_DURING_TASK=true
    fi
    
    # Check row count (Header + 25 data = 26 lines)
    # Using python to count non-empty lines accurately handling quoting
    CSV_LINES=$(python3 -c "import csv; print(len(list(csv.reader(open('$CSV_PATH')))))" 2>/dev/null || echo "0")
    
    if [ "$CSV_LINES" -eq 26 ]; then
        RESPONSE_COUNT_MATCH=true
    fi
    
    # Check header for key columns
    HEADER=$(head -n 1 "$CSV_PATH")
    if [[ "$HEADER" == *"Q01"* ]] && [[ "$HEADER" == *"Q02"* ]]; then
        CSV_HEADER_VALID=true
    fi
fi

# Check LSS
LSS_EXISTS=false
LSS_SIZE=0
LSS_CREATED_DURING_TASK=false
LSS_VALID_XML=false

if [ -f "$LSS_PATH" ]; then
    LSS_EXISTS=true
    LSS_SIZE=$(stat -c %s "$LSS_PATH")
    LSS_MTIME=$(stat -c %Y "$LSS_PATH")
    
    if [ "$LSS_MTIME" -gt "$TASK_START" ]; then
        LSS_CREATED_DURING_TASK=true
    fi
    
    # Simple check for XML structure
    if grep -q "<?xml" "$LSS_PATH" && grep -q "<document>" "$LSS_PATH"; then
        LSS_VALID_XML=true
    fi
fi

# Take final screenshot
take_screenshot /tmp/task_final.png

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "csv_exists": $CSV_EXISTS,
    "csv_created_during_task": $CSV_CREATED_DURING_TASK,
    "csv_lines": $CSV_LINES,
    "csv_header_valid": $CSV_HEADER_VALID,
    "response_count_match": $RESPONSE_COUNT_MATCH,
    "lss_exists": $LSS_EXISTS,
    "lss_created_during_task": $LSS_CREATED_DURING_TASK,
    "lss_valid_xml": $LSS_VALID_XML,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Safely move JSON to shared location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="