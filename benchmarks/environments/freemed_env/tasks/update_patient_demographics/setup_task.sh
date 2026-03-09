#!/bin/bash
# Setup task: update_patient_demographics
# Patient: Luann Sanford (ID 19) - Synthea-generated patient
# Task: Update phone, email, and address

echo "=== Setting up update_patient_demographics task ==="

source /workspace/scripts/task_utils.sh

date +%s > /tmp/task_start_timestamp

# Verify patient Luann Sanford (ID 19)
PATIENT=$(freemed_query "SELECT id, ptfname, ptlname FROM patient WHERE id=19" 2>/dev/null)
echo "Target patient: $PATIENT"

if [ -z "$PATIENT" ]; then
    echo "ERROR: Patient ID 19 (Luann Sanford) not found!"
    exit 1
fi

# Reset demographics to original Synthea values (deterministic start state)
echo "Resetting Luann Sanford's demographics to original Synthea values..."
freemed_query "UPDATE patient SET
    pthphone='617-555-7470',
    ptemail='luann.sanford@synthea.test',
    ptaddr1='843 Hettinger Bay',
    ptcity='Worcester',
    ptstate='MA',
    ptzip='01607'
    WHERE id=19" 2>/dev/null || true

# Verify the reset
CURRENT=$(freemed_query "SELECT pthphone, ptemail, ptaddr1 FROM patient WHERE id=19" 2>/dev/null)
echo "Current demographics: $CURRENT"

ensure_firefox_running "http://localhost/freemed/"

WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority \
        wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

take_screenshot /tmp/task_demographics_start.png

echo ""
echo "=== update_patient_demographics task setup complete ==="
echo "Task: Update phone, email, address for Luann Sanford (ID=19)"
echo "New phone: 617-555-9283"
echo "New email: luann.s.updated@healthmail.test"
echo "New address: 127 Franklin Street, Springfield, MA 01103"
echo "Login: admin / admin"
echo ""
