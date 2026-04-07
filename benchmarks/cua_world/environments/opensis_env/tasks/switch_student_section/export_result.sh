#!/bin/bash
echo "=== Exporting switch_student_section results ==="

# Load IDs from setup
if [ ! -f /tmp/task_config.json ]; then
    echo "ERROR: Task config not found"
    exit 1
fi

STUDENT_ID=$(jq -r '.student_id' /tmp/task_config.json)
COURSE_ID=$(jq -r '.course_id' /tmp/task_config.json)
CP_AM_ID=$(jq -r '.cp_am_id' /tmp/task_config.json)
CP_PM_ID=$(jq -r '.cp_pm_id' /tmp/task_config.json)

# Database credentials
DB_USER="opensis_user"
DB_PASS="opensis_password_123"
DB_NAME="opensis"
MYSQL_CMD="mysql -u $DB_USER -p$DB_PASS $DB_NAME -N -B"

# Capture final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Extract Schedule Data for this student and course
# We get: course_period_id, start_date, end_date
# Using JSON format via python helper or manual construction if simple
echo "Querying schedule..."

# We create a temporary CSV/TSV and convert to JSON
QUERY="SELECT course_period_id, start_date, end_date FROM schedule WHERE student_id=$STUDENT_ID AND course_id=$COURSE_ID"
$MYSQL_CMD -e "$QUERY" > /tmp/schedule_raw.tsv

# Convert to JSON using python
python3 -c "
import json
import csv
import sys
import datetime

records = []
try:
    with open('/tmp/schedule_raw.tsv', 'r') as f:
        reader = csv.reader(f, delimiter='\t')
        for row in reader:
            if row:
                records.append({
                    'course_period_id': int(row[0]),
                    'start_date': row[1],
                    'end_date': row[2] if len(row) > 2 and row[2] != 'NULL' and row[2] != '' else None
                })
except Exception as e:
    sys.stderr.write(str(e))

output = {
    'config': {
        'student_id': $STUDENT_ID,
        'cp_am_id': $CP_AM_ID,
        'cp_pm_id': $CP_PM_ID
    },
    'schedule': records,
    'timestamp': '$(date +%Y-%m-%d)',
    'task_end_time': $(date +%s)
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(output, f, indent=2)
"

# Set permissions
chmod 666 /tmp/task_result.json
echo "Export complete. Result saved to /tmp/task_result.json"
cat /tmp/task_result.json