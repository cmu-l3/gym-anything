#!/bin/bash
echo "=== Setting up Record Family History Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Ensure patient Maria Santos exists in the database
echo "Verifying patient Maria Santos exists..."
EXISTS=$(freemed_query "SELECT COUNT(*) FROM patient WHERE ptfname='Maria' AND ptlname='Santos'" 2>/dev/null || echo "0")
if [ "$EXISTS" -eq "0" ]; then
    echo "Inserting patient Maria Santos..."
    freemed_query "INSERT INTO patient (ptfname, ptlname, ptsex, ptdob) VALUES ('Maria', 'Santos', '2', '1980-01-01')" 2>/dev/null || true
fi

# 2. Schema-Agnostic Dump: Create initial database dump (one row per INSERT)
# We use --skip-extended-insert to ensure each row gets its own INSERT INTO line
echo "Creating initial database dump..."
mysqldump -u freemed -pfreemed freemed --skip-extended-insert --no-create-info --compact > /tmp/freemed_before.sql 2>/dev/null || true

# 3. Launch UI
echo "Starting FreeMED UI..."
ensure_firefox_running "http://localhost/freemed/"

# Focus and Maximize Firefox
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Let UI settle
sleep 2

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="