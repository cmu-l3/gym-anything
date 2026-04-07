#!/bin/bash
echo "=== Setting up query_event_inventory_report task ==="

source /workspace/scripts/task_utils.sh

# 1. Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# 2. Ensure SeisComP services are running
echo "--- Ensuring SeisComP services are running ---"
ensure_scmaster_running

# 3. Verify event data is in the database (re-import if missing)
EVENT_COUNT=$(seiscomp_db_query "SELECT COUNT(*) FROM Event" 2>/dev/null || echo "0")
if [ "$EVENT_COUNT" = "0" ] || [ -z "$EVENT_COUNT" ]; then
    echo "No events found. Agent cannot complete task. Fixing state..."
    SCML_FILE="$SEISCOMP_ROOT/var/lib/events/noto_earthquake.scml"
    if [ -s "$SCML_FILE" ]; then
        su - ga -c "SEISCOMP_ROOT=$SEISCOMP_ROOT PATH=$SEISCOMP_ROOT/bin:\$PATH \
            LD_LIBRARY_PATH=$SEISCOMP_ROOT/lib:\$LD_LIBRARY_PATH \
            seiscomp exec scdb --plugins dbmysql -i $SCML_FILE \
            -d mysql://sysop:sysop@localhost/seiscomp" 2>/dev/null || true
    fi
fi

# 4. Clean up any existing report files to ensure clean state
rm -f /home/ga/noto_earthquake_report.txt 2>/dev/null || true

# 5. Open a terminal for the agent (since this is a CLI/scripting task)
if ! pgrep -f "gnome-terminal" > /dev/null; then
    echo "Starting GNOME Terminal..."
    su - ga -c "DISPLAY=:1 gnome-terminal --working-directory=/home/ga &"
    sleep 3
fi

# Focus and maximize terminal
focus_and_maximize "Terminal" 2>/dev/null || true

# 6. Take initial screenshot
echo "--- Taking initial screenshot ---"
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="