#!/bin/bash
# Export script for Add Facility task
# Saves verification data to a JSON file for the python verifier

echo "=== Exporting Add Facility Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Get current facility count
CURRENT_COUNT=$(freemed_query "SELECT COUNT(*) FROM facility" 2>/dev/null || echo "0")
INITIAL_COUNT=$(cat /tmp/initial_facility_count 2>/dev/null || echo "0")
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

echo "Facility count: initial=$INITIAL_COUNT, current=$CURRENT_COUNT"

# Look for the newly added facility
# We query the entire row as a tab-separated string to ensure we capture the data regardless of exact column names
RAW_ROW=$(freemed_query "SELECT * FROM facility WHERE facilityname LIKE '%Riverside%' OR name LIKE '%Riverside%' OR facilitystreet LIKE '%River Road%' LIMIT 1" 2>/dev/null)

if [ -n "$RAW_ROW" ]; then
    echo "Found matching facility record in database."
else
    echo "No matching facility record found."
fi

# Use Python to safely construct the JSON export without bash escaping issues
python3 -c "
import json
import sys
import os

data = {
    'task_start': int(sys.argv[1]),
    'task_end': int(sys.argv[2]),
    'initial_count': int(sys.argv[3]),
    'current_count': int(sys.argv[4]),
    'raw_row': sys.argv[5],
    'screenshot_exists': os.path.exists('/tmp/task_end_screenshot.png')
}

with open('/tmp/add_facility_result.json', 'w') as f:
    json.dump(data, f, indent=2)
" "$TASK_START" "$TASK_END" "${INITIAL_COUNT:-0}" "${CURRENT_COUNT:-0}" "$RAW_ROW"

# Fix permissions so the verifier can read it
chmod 666 /tmp/add_facility_result.json 2>/dev/null || sudo chmod 666 /tmp/add_facility_result.json 2>/dev/null || true

echo ""
echo "Result JSON saved to /tmp/add_facility_result.json"
cat /tmp/add_facility_result.json
echo ""
echo "=== Export Complete ==="