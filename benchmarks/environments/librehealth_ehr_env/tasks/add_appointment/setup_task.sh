#!/bin/bash
echo "=== Setting up Add Appointment Task ==="

source /workspace/scripts/task_utils.sh

# Ensure LibreHealth EHR is running
wait_for_librehealth 60

# Target patient: Clifford Taylor (pid=8471)
TARGET_PID=8471
TARGET_NAME="Clifford Taylor"

# Record initial appointment count (anti-gaming)
INITIAL_COUNT=$(librehealth_query "SELECT COUNT(*) FROM openemr_postcalendar_events" 2>/dev/null || echo "0")
echo "$INITIAL_COUNT" > /tmp/lh_initial_appt_count
echo "Initial appointment count: $INITIAL_COUNT"

TASK_START=$(date +%s)
echo "$TASK_START" > /tmp/lh_task_start
echo "$TARGET_PID" > /tmp/lh_target_pid
echo "Task start timestamp: $TASK_START"
echo "Target patient: ${TARGET_NAME} (pid=${TARGET_PID})"

# Open Firefox at the LibreHealth EHR calendar/appointment page
restart_firefox "http://localhost:8000/interface/main/calendar/index.php?module=PostCalendar&func=view"

take_screenshot /tmp/task_start_screenshot.png

echo ""
echo "=== Add Appointment Task Ready ==="
echo ""
echo "TASK: Schedule a new appointment for patient '${TARGET_NAME}':"
echo "  - The calendar view is open"
echo "  - Click a time slot (e.g., tomorrow at 10:00 AM) to open the new appointment dialog"
echo "  - Patient: Clifford Taylor (search last name 'Taylor')"
echo "  - Appointment Type: Office Visit"
echo "  - Time: 10:00 AM"
echo "  - Provider: admin"
echo ""
echo "Login: admin / password"
