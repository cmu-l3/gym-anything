#!/bin/bash
echo "=== Exporting create_shift_schedule result ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# 1. Get Task Timing Info
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_COUNT=$(cat /tmp/initial_shift_count.txt 2>/dev/null || echo "0")

# 2. Check if the specific shift exists
SHIFT_ID="WKDAY9TO5"
SHIFT_EXISTS="false"

# Query MySQL for the specific row
# We use -B (batch) and -N (skip headers) to get raw tab-separated values
SHIFT_DATA=$(docker exec vicidial mysql -ucron -p1234 -D asterisk -B -N -e \
  "SELECT shift_name, shift_start_time, shift_length, shift_weekdays 
   FROM vicidial_shifts 
   WHERE shift_id='$SHIFT_ID';" 2>/dev/null || echo "")

SHIFT_NAME=""
SHIFT_START=""
SHIFT_LENGTH=""
SHIFT_WEEKDAYS=""

if [ -n "$SHIFT_DATA" ]; then
    SHIFT_EXISTS="true"
    # Parse tab-separated values
    SHIFT_NAME=$(echo "$SHIFT_DATA" | cut -f1)
    SHIFT_START=$(echo "$SHIFT_DATA" | cut -f2)
    SHIFT_LENGTH=$(echo "$SHIFT_DATA" | cut -f3)
    SHIFT_WEEKDAYS=$(echo "$SHIFT_DATA" | cut -f4)
fi

# 3. Get final total count
FINAL_COUNT=$(docker exec vicidial mysql -ucron -p1234 -D asterisk -N -e \
  "SELECT COUNT(*) FROM vicidial_shifts;" 2>/dev/null || echo "0")

# 4. JSON construction
# Using python for safe JSON encoding to handle potential special chars in name
python3 -c "
import json
import sys

result = {
    'task_start': $TASK_START,
    'initial_count': int('$INITIAL_COUNT'),
    'final_count': int('$FINAL_COUNT'),
    'shift_exists': $SHIFT_EXISTS,
    'shift_data': {
        'id': '$SHIFT_ID',
        'name': '''$SHIFT_NAME''',
        'start_time': '''$SHIFT_START''',
        'length': '''$SHIFT_LENGTH''',
        'weekdays': '''$SHIFT_WEEKDAYS'''
    },
    'screenshot_path': '/tmp/task_final.png'
}
print(json.dumps(result, indent=2))
" > /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="