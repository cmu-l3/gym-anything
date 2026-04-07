#!/bin/bash
# Setup task: order_lab_tests
# Ensure patient Marcus Vance exists and capture the initial database state.

echo "=== Setting up order_lab_tests task ==="

source /workspace/scripts/task_utils.sh

# Record task start timestamp for anti-gaming
date +%s > /tmp/task_start_timestamp

# Ensure patient Marcus Vance exists in FreeMED
# We use INSERT IGNORE to be idempotent if he already exists
freemed_query "INSERT IGNORE INTO patient (ptfname, ptlname, ptdob, ptsex) VALUES ('Marcus', 'Vance', '1968-08-14', '1');" 2>/dev/null || true

# Get Patient ID
PATIENT_ID=$(freemed_query "SELECT id FROM patient WHERE ptfname='Marcus' AND ptlname='Vance' LIMIT 1" 2>/dev/null)
echo "$PATIENT_ID" > /tmp/marcus_patient_id.txt
echo "Target Patient: Marcus Vance (ID: $PATIENT_ID)"

if [ -z "$PATIENT_ID" ]; then
    echo "ERROR: Failed to create or locate patient Marcus Vance!"
    exit 1
fi

# Create a baseline MySQL dump to diff against later
# --skip-extended-insert ensures one row per INSERT statement, making it easy to diff
# --order-by-primary ensures deterministic ordering
echo "Capturing baseline database state..."
mysqldump -u freemed -pfreemed --skip-extended-insert --order-by-primary freemed > /tmp/freemed_before.sql

# Launch Firefox and focus the window
ensure_firefox_running "http://localhost/freemed/"

WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority \
        wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Take initial screenshot showing clean starting state
take_screenshot /tmp/task_initial_state.png

echo ""
echo "=== order_lab_tests task setup complete ==="
echo "Task: Order Lipid Panel and Hemoglobin A1c for Marcus Vance"
echo "Login: admin / admin"
echo ""