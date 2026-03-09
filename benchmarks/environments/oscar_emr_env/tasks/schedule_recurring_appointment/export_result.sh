#!/bin/bash
# Export script for Schedule Recurring Appointment task

echo "=== Exporting Task Results ==="

source /workspace/scripts/task_utils.sh

# 1. Get Task Metadata (saved during setup)
PATIENT_ID=$(cat /tmp/task_patient_id 2>/dev/null || echo "")
TARGET_DATE=$(cat /tmp/task_target_date 2>/dev/null || echo "")
TASK_START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

echo "Checking appointments for Patient ID: $PATIENT_ID starting around $TARGET_DATE"

# 2. Query Appointments
# We fetch appointments for this patient created AFTER the task started
# We look for active appointments (status != 'C'ancelled)
# Fields: appointment_no, appointment_date, start_time, end_time, reason, status
QUERY="SELECT appointment_no, appointment_date, start_time, end_time, reason, status 
       FROM appointment 
       WHERE demographic_no='$PATIENT_ID' 
       AND status != 'C' 
       ORDER BY appointment_date ASC"

# Execute query and format as tab-separated values
APPT_DATA=$(oscar_query "$QUERY")

# 3. Parse SQL output into JSON structure
# We'll use python to construct a robust JSON object
python3 -c "
import sys
import json
import datetime

patient_id = '$PATIENT_ID'
target_date = '$TARGET_DATE'
raw_data = '''$APPT_DATA'''

appointments = []
if raw_data.strip():
    for line in raw_data.strip().split('\n'):
        parts = line.split('\t')
        if len(parts) >= 6:
            appointments.append({
                'id': parts[0],
                'date': parts[1],
                'start_time': parts[2],
                'end_time': parts[3],
                'reason': parts[4],
                'status': parts[5]
            })

result = {
    'patient_id': patient_id,
    'target_start_date': target_date,
    'appointments': appointments,
    'total_count': len(appointments),
    'task_start_ts': $TASK_START_TIME
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
"

# 4. Take final screenshot
take_screenshot /tmp/task_final.png

# 5. Ensure permissions for copy_from_env
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Export completed. JSON content:"
cat /tmp/task_result.json