#!/bin/bash
echo "=== Setting up import_hualien_earthquake task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

# 1. Ensure SeisComP services are running
echo "--- Ensuring SeisComP services are running ---"
ensure_scmaster_running

# 2. Clean up any previous task artifacts
echo "--- Cleaning up previous state ---"
rm -f /home/ga/Documents/hualien_earthquake.scml 2>/dev/null || true
mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents

# Remove any pre-existing Hualien events from the database to ensure clean initial state
seiscomp_db_query "DELETE FROM Origin WHERE latitude_value BETWEEN 23.0 AND 24.5 AND longitude_value BETWEEN 121.0 AND 122.0;" 2>/dev/null || true
seiscomp_db_query "DELETE FROM EventDescription WHERE text LIKE '%Hualien%';" 2>/dev/null || true

# 3. Record initial database state
echo "--- Recording initial database state ---"
INITIAL_EVENT_COUNT=$(seiscomp_db_query "SELECT COUNT(*) FROM Event" 2>/dev/null || echo "0")
echo "$INITIAL_EVENT_COUNT" > /tmp/initial_event_count.txt
echo "Initial event count: $INITIAL_EVENT_COUNT"

# Verify Noto event is loaded (as reference data)
NOTO_COUNT=$(seiscomp_db_query "SELECT COUNT(*) FROM EventDescription WHERE text LIKE '%Noto%'" 2>/dev/null || echo "0")
if [ "$NOTO_COUNT" = "0" ]; then
    echo "Warning: Noto reference event not found in database. Importing it now..."
    SCML_FILE="$SEISCOMP_ROOT/var/lib/events/noto_earthquake.scml"
    if [ -s "$SCML_FILE" ]; then
        su - ga -c "SEISCOMP_ROOT=$SEISCOMP_ROOT PATH=$SEISCOMP_ROOT/bin:\$PATH \
            LD_LIBRARY_PATH=$SEISCOMP_ROOT/lib:\$LD_LIBRARY_PATH \
            seiscomp exec scdb --plugins dbmysql -i $SCML_FILE \
            -d mysql://sysop:sysop@localhost/seiscomp" 2>/dev/null || true
        sleep 2
    fi
    INITIAL_EVENT_COUNT=$(seiscomp_db_query "SELECT COUNT(*) FROM Event" 2>/dev/null || echo "0")
    echo "$INITIAL_EVENT_COUNT" > /tmp/initial_event_count.txt
fi

# 4. Open a terminal for the user to work in
if ! pgrep -f "gnome-terminal" > /dev/null; then
    su - ga -c "DISPLAY=:1 gnome-terminal --working-directory=/home/ga/Documents &"
    sleep 3
fi

# Maximize the terminal
DISPLAY=:1 wmctrl -r "Terminal" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Terminal" 2>/dev/null || true

# 5. Take initial screenshot
echo "--- Taking initial screenshot ---"
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="