#!/bin/bash
echo "=== Setting up record_social_history task ==="

source /workspace/scripts/task_utils.sh

# Record start time for anti-gaming measures
date +%s > /tmp/task_start_timestamp

# Ensure patient "James Wilson" exists in the database
echo "Verifying/pre-loading patient James Wilson..."
freemed_query "INSERT INTO patient (ptfname, ptlname, ptdob, ptsex) SELECT 'James', 'Wilson', '1980-05-15', '1' FROM DUAL WHERE NOT EXISTS (SELECT 1 FROM patient WHERE ptfname='James' AND ptlname='Wilson');" 2>/dev/null || true

# Get the generated/existing patient ID
PATIENT_ID=$(freemed_query "SELECT id FROM patient WHERE ptfname='James' AND ptlname='Wilson' LIMIT 1" 2>/dev/null)
echo "Patient James Wilson ID: $PATIENT_ID"
echo "$PATIENT_ID" > /tmp/james_wilson_id

# Create initial DB dump for robust delta diffing (using skip-extended-insert for line-by-line comparison)
echo "Creating initial database state snapshot..."
mysqldump -u freemed -pfreemed --skip-extended-insert --no-create-info freemed > /tmp/initial_db.sql
sort /tmp/initial_db.sql > /tmp/initial_sorted.sql

# Ensure FreeMED is running in Firefox and logged in
ensure_firefox_running "http://localhost/freemed/"

# Maximize the FreeMED window
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority \
        wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Take initial screenshot for evidence
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="