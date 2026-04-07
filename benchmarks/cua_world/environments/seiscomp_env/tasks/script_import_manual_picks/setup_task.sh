#!/bin/bash
echo "=== Setting up Script Import Manual Picks Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure scmaster is running
ensure_scmaster_running

# Wipe any existing picks with "ExternalSource" to prevent gaming/stale data
mysql -u sysop -psysop seiscomp -e "DELETE FROM Pick WHERE creationInfo_agencyID='ExternalSource';" 2>/dev/null || true

# Pre-record the number of picks currently in the database
INITIAL_PICK_COUNT=$(mysql -u sysop -psysop seiscomp -N -e "SELECT COUNT(*) FROM Pick;" 2>/dev/null || echo "0")
echo "$INITIAL_PICK_COUNT" > /tmp/initial_pick_count.txt

# Ensure terminal is open for the agent
if ! pgrep -f "gnome-terminal" > /dev/null; then
    su - ga -c "DISPLAY=:1 gnome-terminal --working-directory=/home/ga &"
    sleep 3
fi

# Focus and maximize terminal
WID=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "Terminal" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -a "$WID"
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz
fi

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="