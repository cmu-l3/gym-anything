#!/bin/bash
# Export script for Cancel Provider Schedule task

echo "=== Exporting Task Results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Query the database for the status of appointments for Dr. Chen (999998) today
# We expect 3 appointments, all with status 'C'

echo "Querying appointment status..."

# Get counts
TOTAL_APPTS=$(oscar_query "SELECT COUNT(*) FROM appointment WHERE provider_no='999998' AND appointment_date=CURDATE()")
CANCELLED_APPTS=$(oscar_query "SELECT COUNT(*) FROM appointment WHERE provider_no='999998' AND appointment_date=CURDATE() AND status='C'")
ACTIVE_APPTS=$(oscar_query "SELECT COUNT(*) FROM appointment WHERE provider_no='999998' AND appointment_date=CURDATE() AND status NOT IN ('C', 'N', 'M')") 
# N=No Show, M=Missed, but we strictly want C for Cancelled usually. 't' is the default active.

# Get details of appointments (for debugging/verification)
APPT_DETAILS=$(oscar_query "SELECT start_time, status, reason FROM appointment WHERE provider_no='999998' AND appointment_date=CURDATE() ORDER BY start_time")

# Check anti-gaming: Ensure the update happened after task start
# 'last_updated' column exists in oscar appointment table usually? 
# If not, we rely on the state change from 't' (setup) to 'C' (now).
# The setup script definitely set them to 't'.

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "total_appointments": ${TOTAL_APPTS:-0},
    "cancelled_appointments": ${CANCELLED_APPTS:-0},
    "active_appointments": ${ACTIVE_APPTS:-0},
    "appointment_details": "$(echo $APPT_DETAILS | sed 's/"/\\"/g')",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="