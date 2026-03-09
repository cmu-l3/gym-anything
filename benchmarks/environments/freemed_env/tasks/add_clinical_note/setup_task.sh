#!/bin/bash
# Setup task: add_clinical_note
# Patient: Horacio Santacruz (ID 20) - Synthea-generated patient
# Synthea data shows he has ischemic heart disease and recent MI

echo "=== Setting up add_clinical_note task ==="

source /workspace/scripts/task_utils.sh

date +%s > /tmp/task_start_timestamp

# Verify patient Horacio Santacruz (ID 20)
PATIENT=$(freemed_query "SELECT id, ptfname, ptlname FROM patient WHERE id=20" 2>/dev/null)
echo "Target patient: $PATIENT"

if [ -z "$PATIENT" ]; then
    echo "ERROR: Patient ID 20 (Horacio Santacruz) not found!"
    exit 1
fi

# Record initial note count
INITIAL=$(freemed_query "SELECT COUNT(*) FROM pnotes WHERE pnotespat=20" 2>/dev/null || echo "0")
echo "$INITIAL" > /tmp/initial_note_count
echo "Initial note count for Horacio Santacruz: $INITIAL"

ensure_firefox_running "http://localhost/freemed/"

WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority \
        wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

take_screenshot /tmp/task_note_start.png

echo ""
echo "=== add_clinical_note task setup complete ==="
echo "Task: Add SOAP note for Horacio Santacruz (ID=20)"
echo "S: Post-MI follow-up, fatigue, shortness of breath with exertion"
echo "O: BP 148/92, HR 78 bpm, heart sounds regular"
echo "A: Ischemic heart disease, post-MI follow-up"
echo "P: Continue aspirin 81mg + statin, cardiac rehab referral, follow up 4 weeks"
echo "Login: admin / admin"
echo ""
