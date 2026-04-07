#!/bin/bash
echo "=== Setting up record_patient_lab_results task ==="

source /workspace/scripts/task_utils.sh

date +%s > /tmp/task_start_timestamp

# Ensure patient Robert Johnson exists in the database
PATIENT_EXISTS=$(freemed_query "SELECT COUNT(*) FROM patient WHERE ptfname='Robert' AND ptlname='Johnson'" 2>/dev/null || echo "0")
if [ "$PATIENT_EXISTS" -eq "0" ]; then
    echo "Creating patient Robert Johnson..."
    freemed_query "INSERT INTO patient (ptfname, ptlname, ptdob, ptsex) VALUES ('Robert', 'Johnson', '1980-01-01', '1')" 2>/dev/null
fi

PATIENT_ID=$(freemed_query "SELECT id FROM patient WHERE ptfname='Robert' AND ptlname='Johnson' LIMIT 1" 2>/dev/null)
echo "Target patient ID: $PATIENT_ID"
echo "$PATIENT_ID" > /tmp/patient_id.txt

# Remove any existing lipid results for Robert to ensure a clean state
freemed_query "DELETE FROM pnotes WHERE ppatient='$PATIENT_ID' AND (pnotes LIKE '%Lipid%' OR pnotes LIKE '%185%')" 2>/dev/null || true
freemed_query "DELETE FROM testrec WHERE patient='$PATIENT_ID' AND (testdesc LIKE '%Lipid%' OR testresults LIKE '%185%')" 2>/dev/null || true

# Wait a moment for DB to settle
sleep 1

# Dump DB state before task (CRITICAL FOR ANTI-GAMING)
# --skip-extended-insert forces 1 row per INSERT statement, perfect for diffing
echo "Taking pre-task database snapshot..."
mysqldump -u freemed -pfreemed freemed --skip-extended-insert --no-create-info > /tmp/db_before.sql 2>/dev/null

# Make sure Firefox is running and focused
ensure_firefox_running "http://localhost/freemed/"

WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority \
        wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Take initial screenshot for evidence
take_screenshot /tmp/task_start.png

echo ""
echo "=== Setup complete ==="