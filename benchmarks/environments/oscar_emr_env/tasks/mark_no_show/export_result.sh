#!/bin/bash
set -e
echo "=== Exporting Mark No-Show Result ==="

source /workspace/scripts/task_utils.sh

# Load setup data
APPT_NO=$(cat /tmp/noshow_appt_no.txt 2>/dev/null || echo "0")
DEMO_NO=$(cat /tmp/noshow_demo_no.txt 2>/dev/null || echo "0")
INITIAL_STATUS=$(cat /tmp/noshow_initial_status.txt 2>/dev/null || echo "unknown")
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TODAY=$(date +%Y-%m-%d)

# 1. Get current status of the target appointment
CURRENT_STATUS=$(oscar_query "SELECT status FROM appointment WHERE appointment_no=${APPT_NO}" 2>/dev/null | tr -d '[:space:]')
echo "Current Status: $CURRENT_STATUS"

# 2. Get update timestamp
UPDATED_TS=$(oscar_query "SELECT UNIX_TIMESTAMP(updatedatetime) FROM appointment WHERE appointment_no=${APPT_NO}" 2>/dev/null | tr -d '[:space:]')
echo "Update Timestamp: $UPDATED_TS"

# 3. Check for collateral damage (other appointments for this provider today marked as No Show)
# We exclude our target appointment from this count
COLLATERAL_COUNT=$(oscar_query "SELECT COUNT(*) FROM appointment WHERE appointment_date='$TODAY' AND provider_no='999998' AND status='N' AND appointment_no != ${APPT_NO}" 2>/dev/null | tr -d '[:space:]')
echo "Collateral No-Shows: $COLLATERAL_COUNT"

# 4. Verify patient/date matches on the appointment (integrity check)
APPT_DATA=$(oscar_query "SELECT demographic_no, appointment_date FROM appointment WHERE appointment_no=${APPT_NO}" 2>/dev/null)
APPT_DEMO=$(echo "$APPT_DATA" | awk '{print $1}')
APPT_DATE=$(echo "$APPT_DATA" | awk '{print $2}')

# Capture final screenshot
take_screenshot /tmp/task_final.png

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "appt_no": "${APPT_NO}",
    "demo_no": "${DEMO_NO}",
    "initial_status": "${INITIAL_STATUS}",
    "current_status": "${CURRENT_STATUS}",
    "task_start_time": ${TASK_START},
    "last_update_time": ${UPDATED_TS:-0},
    "collateral_no_shows": ${COLLATERAL_COUNT:-0},
    "appt_demo_match": "$APPT_DEMO",
    "appt_date_match": "$APPT_DATE",
    "today_date": "$TODAY",
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="