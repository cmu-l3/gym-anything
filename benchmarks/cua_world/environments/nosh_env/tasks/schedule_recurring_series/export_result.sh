#!/bin/bash
# Export script for schedule_recurring_series task

echo "=== Exporting Task Results ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TARGET_PID=$(cat /tmp/target_pid.txt 2>/dev/null || echo "0")

# Capture final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Query the schedule table for appointments in April 2026 for this patient
# We need: date, time, reason
echo "Querying database for appointments..."

# Create a temporary SQL file to run the query and output JSON-like structure
# Note: MariaDB in container might not support JSON_OBJECT directly depending on version,
# so we'll output raw tab-separated values and parse in python or bash.
# Let's try TSV.

docker exec nosh-db mysql -uroot -prootpassword nosh -N -e "
SELECT start_date, start_time, reason, visit_type 
FROM schedule 
WHERE pid='$TARGET_PID' 
  AND start_date >= '2026-04-01' 
  AND start_date <= '2026-04-30'
ORDER BY start_date ASC;
" > /tmp/appointments_tsv.txt

# Convert TSV to JSON
# Python is available in the environment
python3 -c "
import json
import sys

appointments = []
try:
    with open('/tmp/appointments_tsv.txt', 'r') as f:
        for line in f:
            parts = line.strip().split('\t')
            if len(parts) >= 2:
                appt = {
                    'date': parts[0],
                    'time': parts[1],
                    'reason': parts[2] if len(parts) > 2 else '',
                    'type': parts[3] if len(parts) > 3 else ''
                }
                appointments.append(appt)
except Exception as e:
    print(f'Error parsing TSV: {e}', file=sys.stderr)

result = {
    'pid': '$TARGET_PID',
    'appointments': appointments,
    'task_start': $TASK_START,
    'screenshot_path': '/tmp/task_final.png'
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
"

# Handle permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Export complete. Result:"
cat /tmp/task_result.json