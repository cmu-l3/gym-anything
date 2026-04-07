#!/bin/bash
echo "=== Setting up develop_json_event_exporter task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure services are running
echo "--- Ensuring SeisComP services are running ---"
ensure_scmaster_running

# Verify event data is in the database (Noto earthquake)
echo "--- Verifying event data ---"
EVENT_COUNT=$(seiscomp_db_query "SELECT COUNT(*) FROM Event" 2>/dev/null || echo "0")
echo "Events in database: $EVENT_COUNT"

# If no events, attempt to reimport
if [ "$EVENT_COUNT" = "0" ] || [ -z "$EVENT_COUNT" ]; then
    echo "No events found, attempting to reimport..."
    SCML_FILE="$SEISCOMP_ROOT/var/lib/events/noto_earthquake.scml"
    if [ -s "$SCML_FILE" ]; then
        su - ga -c "SEISCOMP_ROOT=$SEISCOMP_ROOT PATH=$SEISCOMP_ROOT/bin:\$PATH \
            LD_LIBRARY_PATH=$SEISCOMP_ROOT/lib:\$LD_LIBRARY_PATH \
            seiscomp exec scdb --plugins dbmysql -i $SCML_FILE \
            -d mysql://sysop:sysop@localhost/seiscomp" 2>/dev/null || true
        sleep 2
    fi
fi

# Prepare working directory
echo "--- Preparing workspace ---"
mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents

# Remove any pre-existing files to prevent gaming
rm -f /home/ga/Documents/export_latest_json.py 2>/dev/null
rm -f /home/ga/Documents/latest_event.json 2>/dev/null

# Open a terminal for the agent in the correct directory
if ! pgrep -f gnome-terminal > /dev/null; then
    su - ga -c "DISPLAY=:1 gnome-terminal --working-directory=/home/ga/Documents &"
    sleep 3
    
    # Maximize terminal
    DISPLAY=:1 wmctrl -r "Terminal" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Take initial screenshot
echo "--- Taking initial screenshot ---"
sleep 1
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="