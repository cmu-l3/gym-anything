#!/bin/bash
set -e
echo "=== Exporting Reschedule Appointment Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Capture final screenshot
take_screenshot /tmp/task_final_state.png

# Get timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# ============================================================
# 1. Check Old Appointment Status (July 15)
# ============================================================
# We check if there are any ACTIVE appointments left on the old date.
# Status 'C' (Cancelled), 'D' (Deleted), 'N' (No Show), 'CS' (Cancelled) are considered removed.
OLD_DATE="2025-07-15"
OLD_TIME="10:00:00"

ACTIVE_OLD_COUNT=$(oscar_query "SELECT COUNT(*) FROM appointment 
    WHERE demographic_no=2 
    AND appointment_date='$OLD_DATE' 
    AND start_time='$OLD_TIME' 
    AND status NOT IN ('C', 'D', 'N', 'CS');" || echo "1")

# ============================================================
# 2. Check New Appointment Status (July 17)
# ============================================================
NEW_DATE="2025-07-17"

# Find the most recently updated appointment for this patient on the target date
NEW_APPT_JSON=$(oscar_query "SELECT CONCAT(
    '{',
    '\"exists\": true,',
    '\"appointment_no\": \"', appointment_no, '\",',
    '\"start_time\": \"', start_time, '\",',
    '\"reason\": \"', REPLACE(reason, '\"', '\\\"'), '\",',
    '\"status\": \"', status, '\"',
    '}') 
    FROM appointment 
    WHERE demographic_no=2 
    AND appointment_date='$NEW_DATE' 
    AND status NOT IN ('C', 'D', 'CS')
    ORDER BY lastUpdateDate DESC LIMIT 1;" || echo "")

if [ -z "$NEW_APPT_JSON" ]; then
    NEW_APPT_JSON='{"exists": false}'
fi

# ============================================================
# 3. Compile Result JSON
# ============================================================
TEMP_JSON=$(mktemp /tmp/reschedule_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_timestamp": $TASK_START,
    "task_end_timestamp": $TASK_END,
    "old_appointment_active_count": ${ACTIVE_OLD_COUNT:-1},
    "new_appointment": $NEW_APPT_JSON,
    "screenshot_path": "/tmp/task_final_state.png"
}
EOF

# Move to standard location with permissive permissions
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Export complete. JSON content:"
cat /tmp/task_result.json