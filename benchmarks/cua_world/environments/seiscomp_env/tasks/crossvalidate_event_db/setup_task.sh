#!/bin/bash
echo "=== Setting up crossvalidate_event_db task ==="

source /workspace/scripts/task_utils.sh

# Record start time for anti-gaming checks
date +%s > /tmp/task_start_time

# Start scmaster if not running
ensure_scmaster_running

# Wait a moment for DB connection stabilization
sleep 2

# Verify event data is imported (our ground truth relies on it)
EVENT_COUNT=$(seiscomp_db_query "SELECT COUNT(*) FROM Event" 2>/dev/null || echo "0")
if [ "$EVENT_COUNT" = "0" ] || [ -z "$EVENT_COUNT" ]; then
    echo "No events found in SeisComP DB. Attempting to reimport..."
    su - ga -c "SEISCOMP_ROOT=$SEISCOMP_ROOT PATH=$SEISCOMP_ROOT/bin:\$PATH \
        LD_LIBRARY_PATH=$SEISCOMP_ROOT/lib:\$LD_LIBRARY_PATH \
        seiscomp exec scdb --plugins dbmysql -i $SEISCOMP_ROOT/var/lib/events/noto_earthquake.scml \
        -d mysql://sysop:sysop@localhost/seiscomp" 2>/dev/null || true
    sleep 2
fi

# Cleanup old agent outputs to ensure clean state
rm -f /home/ga/earthquake_validation_report.txt 2>/dev/null
rm -f /home/ga/event_dump.xml 2>/dev/null

# Open a terminal for the agent to begin command-line investigation
su - ga -c "DISPLAY=:1 gnome-terminal --working-directory=/home/ga &"

# Wait for terminal window to appear
wait_for_window "Terminal" 10 || wait_for_window "ga@ubuntu" 10

# Maximize the terminal for clarity
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take initial state screenshot
take_screenshot /tmp/task_start.png

echo "=== Task setup complete ==="