#!/bin/bash
set -e
echo "=== Setting up generate_jst_event_report task ==="

source /workspace/scripts/task_utils.sh

# 1. Ensure MariaDB and scmaster are running
systemctl start mariadb || true
ensure_scmaster_running

# 2. Verify event data is in the database
EVENT_COUNT=$(seiscomp_db_query "SELECT COUNT(*) FROM Event" 2>/dev/null || echo "0")
if [ "$EVENT_COUNT" = "0" ] || [ -z "$EVENT_COUNT" ]; then
    echo "No events found, attempting to import..."
    SCML_FILE="$SEISCOMP_ROOT/var/lib/events/noto_earthquake.scml"
    if [ -s "$SCML_FILE" ]; then
        su - ga -c "SEISCOMP_ROOT=$SEISCOMP_ROOT PATH=$SEISCOMP_ROOT/bin:\$PATH \
            LD_LIBRARY_PATH=$SEISCOMP_ROOT/lib:\$LD_LIBRARY_PATH \
            seiscomp exec scdb --plugins dbmysql -i $SCML_FILE \
            -d mysql://sysop:sysop@localhost/seiscomp" 2>/dev/null || true
    fi
fi

# 3. Create Documents directory and remove old report
mkdir -p /home/ga/Documents
rm -f /home/ga/Documents/noto_report.html
chown -R ga:ga /home/ga/Documents

# 4. Save task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# 5. Open a terminal for the agent
if ! pgrep -f "gnome-terminal" > /dev/null; then
    su - ga -c "DISPLAY=:1 gnome-terminal --maximize &"
    sleep 2
fi

# 6. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="