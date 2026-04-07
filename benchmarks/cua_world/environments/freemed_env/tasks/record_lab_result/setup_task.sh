#!/bin/bash
echo "=== Setting up record_lab_result task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# Ensure the target patient Maria Santos exists in FreeMED
echo "Verifying target patient exists..."
PATIENT_COUNT=$(freemed_query "SELECT COUNT(*) FROM patient WHERE ptfname='Maria' AND ptlname='Santos'" 2>/dev/null || echo "0")

if [ "$PATIENT_COUNT" -eq 0 ]; then
    echo "Patient Maria Santos not found. Inserting default patient record..."
    freemed_query "INSERT INTO patient (ptfname, ptlname, ptdob, ptsex) VALUES ('Maria', 'Santos', '1980-05-14', '2')" 2>/dev/null
fi

# Clean any existing "6.8" lab results for this patient to ensure a clean state
# Schema-agnostic cleanup is risky, but we can delete from obvious tables if needed
freemed_query "DELETE FROM pnotes WHERE pnotesdesc LIKE '%6.8%'" 2>/dev/null || true
freemed_query "DELETE FROM annotations WHERE annotation LIKE '%6.8%'" 2>/dev/null || true

# CRITICAL: Create a baseline database dump for schema-agnostic diffing
# --compact strips out comments and table structure, leaving only raw INSERTs
echo "Generating pre-task database snapshot..."
mysqldump -u freemed -pfreemed freemed --skip-extended-insert --compact --no-create-info > /tmp/freemed_initial.sql 2>/dev/null

# Ensure Firefox is running and at the correct URL
ensure_firefox_running "http://localhost/freemed/"

# Maximize and focus the browser window
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority \
        wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Take initial screenshot for evidence
sleep 2
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="
echo "Task: Record HbA1c result of 6.8% for Maria Santos"
echo "Login: admin / admin"