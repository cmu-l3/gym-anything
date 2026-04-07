#!/bin/bash
# Export script for fulfill_appointment_request
# Checks status of the request and existence of the appointment

set -e
echo "=== Exporting results ==="
source /workspace/scripts/task_utils.sh

# Get UUIDs from setup
REQ_UUID=$(cat /tmp/target_request_uuid.txt 2>/dev/null || echo "")
PATIENT_UUID=$(cat /tmp/target_patient_uuid.txt 2>/dev/null || echo "")
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. CHECK REQUEST STATUS
# Should be FULFILLED
REQ_STATUS=""
if [ -n "$REQ_UUID" ]; then
    REQ_JSON=$(omrs_get "/appointmentscheduling/appointmentrequest/$REQ_UUID?v=default")
    REQ_STATUS=$(echo "$REQ_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin).get('status','UNKNOWN'))" 2>/dev/null || echo "ERROR")
fi
echo "Final Request Status: $REQ_STATUS"

# 2. CHECK CREATED APPOINTMENT
# Find appointments for this patient created AFTER task start
# We fetch all appointments and filter by dateCreated in Python for precision, or just check count and content
APPT_JSON=$(omrs_get "/appointmentscheduling/appointment?patient=$PATIENT_UUID&v=full")
# We'll verify this in python verifier using the raw json, 
# but let's grab the most recent one here for quick debug
LATEST_APPT_STATUS=$(echo "$APPT_JSON" | python3 -c "
import sys,json
r=json.load(sys.stdin)
res=r.get('results',[])
if res:
    # Sort by dateCreated desc
    res.sort(key=lambda x: x.get('auditInfo',{}).get('dateCreated',''), reverse=True)
    print(res[0].get('status',''))
else:
    print('NONE')
" 2>/dev/null)
echo "Latest Appointment Status: $LATEST_APPT_STATUS"

# 3. SCREENSHOT
take_screenshot /tmp/task_final.png

# 4. EXPORT JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "request_uuid": "$REQ_UUID",
    "patient_uuid": "$PATIENT_UUID",
    "final_request_status": "$REQ_STATUS",
    "task_start_timestamp": $TASK_START,
    "appointments_json": $APPT_JSON,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Export complete."