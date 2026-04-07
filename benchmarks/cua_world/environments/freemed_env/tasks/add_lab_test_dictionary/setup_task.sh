#!/bin/bash
echo "=== Setting up add_lab_test_dictionary task ==="

source /workspace/scripts/task_utils.sh

# Record task start timestamp for anti-gaming checks
date +%s > /tmp/task_start_timestamp

# Ensure a clean database state and record initial counts to prevent gaming
echo "Recording initial database baseline..."
mysqldump -u freemed -pfreemed freemed --no-create-info --skip-extended-insert 2>/dev/null | grep -i "Helicobacter pylori" | wc -l | tr -d ' ' > /tmp/initial_name_count
mysqldump -u freemed -pfreemed freemed --no-create-info --skip-extended-insert 2>/dev/null | grep -i "UBT-HP" | wc -l | tr -d ' ' > /tmp/initial_code_count

echo "Initial Name Count: $(cat /tmp/initial_name_count)"
echo "Initial Code Count: $(cat /tmp/initial_code_count)"

# Ensure Firefox is running and navigated to the FreeMED dashboard
ensure_firefox_running "http://localhost/freemed/"

WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Take an initial screenshot proving the task started in the correct baseline state
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="