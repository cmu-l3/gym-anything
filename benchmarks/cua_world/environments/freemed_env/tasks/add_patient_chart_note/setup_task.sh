#!/bin/bash
echo "=== Setting up add_patient_chart_note task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

# 1. Ensure the patient "David Chen" exists in the database
# If not, insert a basic record to ensure the task is achievable
CHEN_EXISTS=$(freemed_query "SELECT COUNT(*) FROM patient WHERE ptfname='David' AND ptlname='Chen'" 2>/dev/null || echo "0")

if [ "$CHEN_EXISTS" -eq "0" ]; then
    echo "Creating patient David Chen..."
    # Generate a random 9-digit patient ID prefix
    freemed_query "INSERT INTO patient (ptfname, ptlname, ptdob, ptsex, ptadd1, ptcity, ptstate, ptzip) VALUES ('David', 'Chen', '1982-08-14', '1', '123 Fake St', 'Boston', 'MA', '02101');" 2>/dev/null || true
else
    echo "Patient David Chen already exists."
fi

# 2. Record initial state: dump DB and check if the target string already exists
# This is a strict anti-gaming measure to ensure the agent actually types/saves the text
mysqldump -u freemed -pfreemed freemed > /tmp/pre_task_db.sql 2>/dev/null
PRE_COUNT=$(grep -c "certified ASL (American Sign Language) interpreter MUST be scheduled" /tmp/pre_task_db.sql 2>/dev/null || echo "0")
echo "$PRE_COUNT" > /tmp/pre_task_string_count.txt
echo "Initial occurrences of target string in DB: $PRE_COUNT"

# 3. Setup Firefox and FreeMED UI
ensure_firefox_running "http://localhost/freemed/"

WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    # Maximize the window
    DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
fi

# 4. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="