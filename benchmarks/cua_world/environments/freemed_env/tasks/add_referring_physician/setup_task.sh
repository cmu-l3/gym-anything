#!/bin/bash
echo "=== Setting up add_referring_physician task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

# Ensure clean state: delete any existing physician with this name
echo "Cleaning up any pre-existing records for 'Pendelton'..."
mysql -u freemed -pfreemed freemed -e "DELETE FROM physician WHERE phylname='Pendelton';" 2>/dev/null || true
mysql -u freemed -pfreemed freemed -e "DELETE FROM addressbook WHERE abname LIKE '%Pendelton%';" 2>/dev/null || true

# Record initial physician count
INITIAL_COUNT=$(mysql -u freemed -pfreemed freemed -N -e "SELECT COUNT(*) FROM physician;" 2>/dev/null || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_phys_count.txt
echo "Initial physician count: $INITIAL_COUNT"

# Ensure Firefox is running and at the FreeMED URL
ensure_firefox_running "http://localhost/freemed/"

# Maximize and focus the browser window
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority \
        wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="