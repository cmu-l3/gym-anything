#!/bin/bash
echo "=== Exporting Record Patient Allergies Result ==="

source /workspace/scripts/task_utils.sh

# Record End Time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Retrieve Target PID
TARGET_PID=$(cat /tmp/target_pid.txt 2>/dev/null)

if [ -z "$TARGET_PID" ]; then
    echo "ERROR: Target PID not found. Setup may have failed."
    TARGET_PID="0"
fi

# ------------------------------------------------------------------
# 1. Query Database for Allergies
# ------------------------------------------------------------------
# We retrieve key fields: id, title (drug), reaction, severity, begdate (onset), date (entry timestamp)
# We filter by PID and type='allergy'

SQL_QUERY="SELECT title, reaction, severity_al, begdate, date FROM lists WHERE pid='$TARGET_PID' AND type='allergy'"

# Get raw data (tab separated)
RAW_DATA=$(librehealth_query "$SQL_QUERY" 2>/dev/null)

# Convert to JSON using python for reliability
# We handle the CSV/Tab parsing in Python to generate clean JSON
python3 -c "
import sys
import json
import csv

raw_data = '''$RAW_DATA'''
rows = []
if raw_data.strip():
    reader = csv.reader(raw_data.strip().split('\n'), delimiter='\t')
    for line in reader:
        if len(line) >= 5:
            rows.append({
                'title': line[0],
                'reaction': line[1],
                'severity': line[2],
                'begdate': line[3],
                'entry_date': line[4]
            })

result = {
    'task_start': $TASK_START,
    'task_end': $TASK_END,
    'target_pid': '$TARGET_PID',
    'allergies': rows,
    'count': len(rows)
}
print(json.dumps(result, indent=2))
" > /tmp/db_result.json

# ------------------------------------------------------------------
# 2. Capture Application State
# ------------------------------------------------------------------
# Take final screenshot
take_screenshot /tmp/task_final.png

# Check if Firefox is still running
APP_RUNNING=$(pgrep -f "firefox" > /dev/null && echo "true" || echo "false")

# ------------------------------------------------------------------
# 3. Merge and Save Final Result
# ------------------------------------------------------------------
# We merge the DB result with environment metadata

jq -s '.[0] + {app_running: .[1].app_running, screenshot_path: "/tmp/task_final.png"}' \
    /tmp/db_result.json \
    <(echo "{\"app_running\": $APP_RUNNING}") \
    > /tmp/task_result.json

# Cleanup
rm -f /tmp/db_result.json

echo "Export complete. Result:"
cat /tmp/task_result.json