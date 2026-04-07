#!/bin/bash
echo "=== Setting up add_system_user_group task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Clean any existing group with this name to ensure clean state
mysql -u freemed -pfreemed freemed -N -e "DELETE FROM usergroups WHERE usergroup_name='Medical Records Specialist' OR usergroup_desc LIKE '%scanning%';" 2>/dev/null || true

# Record initial table counts
echo "Recording initial table counts..."
mysql -u freemed -pfreemed freemed -N -e "SHOW TABLES" 2>/dev/null | while read table; do
    count=$(mysql -u freemed -pfreemed freemed -N -e "SELECT COUNT(*) FROM \`$table\`" 2>/dev/null)
    echo "$table:$count" >> /tmp/initial_table_counts.txt
done

# Ensure Firefox is running
ensure_firefox_running "http://localhost/freemed/"

WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority \
        wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="