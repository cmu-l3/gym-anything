#!/bin/bash
echo "=== Setting up generate_bulletin_scbulletin task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure MariaDB is running
echo "Ensuring MariaDB is running..."
systemctl start mariadb || true
for i in $(seq 1 15); do
    if mysqladmin ping -h localhost 2>/dev/null; then
        echo "MariaDB is ready"
        break
    fi
    sleep 2
done

# Ensure scmaster is running
ensure_scmaster_running

# Check if events exist, if not, attempt re-import
EVENT_COUNT=$(seiscomp_db_query "SELECT COUNT(*) FROM Event" 2>/dev/null || echo "0")
echo "Events in database: $EVENT_COUNT"

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

# Prepare output directory
mkdir -p /home/ga/bulletins
chown ga:ga /home/ga/bulletins

# Clean up any pre-existing results
rm -f /home/ga/bulletins/noto_bulletin.txt
rm -f /tmp/agent_bulletin.txt

# Extract ground truth internally for later verification
mkdir -p /tmp/ground_truth
seiscomp_db_query "SELECT po.publicID FROM PublicObject po JOIN Event e ON po._oid = e._oid LIMIT 1" > /tmp/ground_truth/event_id.txt 2>/dev/null || true
seiscomp_db_query "SELECT latitude_value, longitude_value, depth_value FROM Origin LIMIT 1" > /tmp/ground_truth/origin_params.txt 2>/dev/null || true
seiscomp_db_query "SELECT magnitude_value, type FROM Magnitude LIMIT 1" > /tmp/ground_truth/magnitude_params.txt 2>/dev/null || true

# Close any SeisComP GUI windows to ensure terminal focus
kill_seiscomp_gui scolv
kill_seiscomp_gui scconfig

# Open a terminal for the agent
killall gnome-terminal-server 2>/dev/null || true
sleep 1

su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority gnome-terminal --maximize" &
sleep 4

# Focus terminal
focus_and_maximize "Terminal" || focus_and_maximize "ga@" || true

# Take initial screenshot
take_screenshot /tmp/task_initial_state.png

echo "=== Task setup complete ==="