#!/bin/bash
# Setup script for Add ICD Code task

echo "=== Setting up Add ICD Code Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start timestamp for anti-gaming
date +%s > /tmp/task_start_timestamp

# Ensure clean state: delete G47.33 if it somehow exists
echo "Cleaning up any pre-existing G47.33 code entries..."
freemed_query "DELETE FROM icdcodes WHERE icdcode='G47.33'" 2>/dev/null || true

# Record initial ICD codes count
echo "Recording initial ICD code count..."
INITIAL_COUNT=$(freemed_query "SELECT COUNT(*) FROM icdcodes" 2>/dev/null || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_icd_count
echo "Initial ICD code count: $INITIAL_COUNT"

# Ensure Firefox is running and focused on FreeMED
echo "Ensuring Firefox is running..."
ensure_firefox_running "http://localhost/freemed/"

# Focus and maximize Firefox window
echo "Focusing Firefox window..."
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority \
        wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
fi

# Take initial screenshot
take_screenshot /tmp/task_icd_start.png

echo "=== Add ICD Code Task Setup Complete ==="
echo ""
echo "Task Instructions:"
echo "  1. Log in to FreeMED (Username: admin, Password: admin)"
echo "  2. Navigate to the Support Data / Admin section for ICD Codes"
echo "  3. Add a new ICD code:"
echo "     - Code: G47.33"
echo "     - Description: Obstructive sleep apnea (adult)(pediatric)"
echo "  4. Save the entry"
echo ""