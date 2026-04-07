#!/bin/bash
echo "=== Setting up record_appointment_noshow task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time

TODAY=$(date +%Y-%m-%d)

# 1. Ensure patient Marcus Vance exists
echo "Seeding patient Marcus Vance..."
PAT_EXISTS=$(freemed_query "SELECT COUNT(*) FROM patient WHERE ptfname='Marcus' AND ptlname='Vance'" 2>/dev/null || echo "0")
if [ "$PAT_EXISTS" -eq "0" ]; then
    freemed_query "INSERT INTO patient (ptfname, ptlname, ptdob) VALUES ('Marcus', 'Vance', '1982-10-14')" 2>/dev/null || true
fi

PAT_ID=$(freemed_query "SELECT id FROM patient WHERE ptfname='Marcus' AND ptlname='Vance' LIMIT 1" 2>/dev/null)
echo "Patient ID: $PAT_ID"

if [ -z "$PAT_ID" ]; then
    echo "ERROR: Failed to create/find target patient."
    # We will continue but the task might be uncompletable
fi

# 2. Clear any existing appointments for this patient today
echo "Clearing existing appointments for today..."
freemed_query "DELETE FROM scheduler WHERE calpatient='$PAT_ID' AND caldateof='$TODAY'" 2>/dev/null || true

# 3. Create today's appointment (Status 1 usually = Scheduled/Pending)
echo "Creating 09:00 AM appointment..."
freemed_query "INSERT INTO scheduler (caldateof, caltimeof, calpatient, caluser, calfacility, calstatus, caltype) VALUES ('$TODAY', '09:00:00', '$PAT_ID', 1, 1, 1, 1)" 2>/dev/null || true

# 4. Record initial state of the newly created appointment
APP_ID=$(freemed_query "SELECT id FROM scheduler WHERE calpatient='$PAT_ID' AND caldateof='$TODAY' LIMIT 1" 2>/dev/null)
INIT_STATUS=$(freemed_query "SELECT calstatus FROM scheduler WHERE id='$APP_ID'" 2>/dev/null)

echo "Created Appointment ID: $APP_ID with Status ID: $INIT_STATUS"

cat > /tmp/initial_state.json << EOF
{
    "appointment_id": "$APP_ID",
    "patient_id": "$PAT_ID",
    "initial_status": "$INIT_STATUS"
}
EOF

# 5. Launch and focus FreeMED in Firefox
ensure_firefox_running "http://localhost/freemed/"

WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
fi

# Take initial screenshot
take_screenshot /tmp/task_setup_initial.png

echo "=== Task setup complete ==="