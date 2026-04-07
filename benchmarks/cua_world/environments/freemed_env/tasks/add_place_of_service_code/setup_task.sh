#!/bin/bash
# Setup task: add_place_of_service_code

echo "=== Setting up add_place_of_service_code task ==="

source /workspace/scripts/task_utils.sh

# Record task start timestamp for anti-gaming
date +%s > /tmp/task_start_timestamp

# Find the exact Place of Service table (typically 'pos' in FreeMED)
TABLE_NAME=$(mysql -u freemed -pfreemed freemed -N -e "SHOW TABLES LIKE 'pos';" 2>/dev/null)
if [ -z "$TABLE_NAME" ]; then
    TABLE_NAME=$(mysql -u freemed -pfreemed freemed -N -e "SHOW TABLES LIKE '%place%service%';" 2>/dev/null | head -1)
fi

echo "Identified POS table: ${TABLE_NAME:-None}"

if [ -n "$TABLE_NAME" ]; then
    # Delete the target code if it exists to ensure a clean starting state
    mysql -u freemed -pfreemed freemed -e "DELETE FROM \`$TABLE_NAME\` WHERE poscode='03' OR poscode='3'" 2>/dev/null || true
    
    # Record initial record count
    INITIAL_COUNT=$(mysql -u freemed -pfreemed freemed -N -e "SELECT COUNT(*) FROM \`$TABLE_NAME\`" 2>/dev/null || echo "0")
else
    INITIAL_COUNT="0"
fi

echo "$INITIAL_COUNT" > /tmp/initial_pos_count
echo "Initial POS count: $INITIAL_COUNT"

# Ensure FreeMED is accessible
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost/freemed/ 2>/dev/null)
echo "FreeMED HTTP status: $HTTP_CODE"

# Launch and focus Firefox
ensure_firefox_running "http://localhost/freemed/"

WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority \
        wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Take initial proof screenshot
take_screenshot /tmp/task_pos_start.png

echo ""
echo "=== add_place_of_service_code task setup complete ==="
echo "Task: Add POS Code '03' (School)"
echo "FreeMED URL: http://localhost/freemed/"
echo "Login: admin / admin"
echo ""