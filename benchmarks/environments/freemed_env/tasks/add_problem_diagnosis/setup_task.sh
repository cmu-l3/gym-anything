#!/bin/bash
# Setup task: add_problem_diagnosis
# Patient: Arlie McClure (ID 17) - Synthea-generated patient
# Synthea data: Chronic low back pain (SNOMED:278860009), onset 2014-02-03

echo "=== Setting up add_problem_diagnosis task ==="

source /workspace/scripts/task_utils.sh

date +%s > /tmp/task_start_timestamp

# Verify patient Arlie McClure (ID 17)
PATIENT=$(freemed_query "SELECT id, ptfname, ptlname FROM patient WHERE id=17" 2>/dev/null)
echo "Target patient: $PATIENT"

if [ -z "$PATIENT" ]; then
    echo "ERROR: Patient ID 17 (Arlie McClure) not found!"
    exit 1
fi

# Remove any pre-existing Chronic Low Back Pain entry for clean state
freemed_query "DELETE FROM current_problems WHERE ppatient=17 AND problem LIKE '%back%'" 2>/dev/null || true
freemed_query "DELETE FROM current_problems WHERE ppatient=17 AND problem LIKE '%724.2%'" 2>/dev/null || true

# Record initial problem count
INITIAL=$(freemed_query "SELECT COUNT(*) FROM current_problems WHERE ppatient=17" 2>/dev/null || echo "0")
echo "$INITIAL" > /tmp/initial_problem_count
echo "Initial problem count for Arlie: $INITIAL"

ensure_firefox_running "http://localhost/freemed/"

WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority \
        wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

take_screenshot /tmp/task_problem_start.png

echo ""
echo "=== add_problem_diagnosis task setup complete ==="
echo "Task: Add Chronic Low Back Pain (ICD 724.2, onset 2014-02-03) for Arlie McClure (ID=17)"
echo "Login: admin / admin"
echo ""
