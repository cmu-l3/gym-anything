#!/bin/bash
echo "=== Setting up assign_p_wave_polarity task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Ensure services are running
echo "--- Ensuring SeisComP services are running ---"
ensure_scmaster_running

# 2. Verify event data is in the database (re-import if missing)
echo "--- Verifying event data ---"
EVENT_COUNT=$(seiscomp_db_query "SELECT COUNT(*) FROM Event" 2>/dev/null || echo "0")
if [ "$EVENT_COUNT" = "0" ] || [ -z "$EVENT_COUNT" ]; then
    echo "No events found, attempting to reimport..."
    SCML_FILE="$SEISCOMP_ROOT/var/lib/events/noto_earthquake.scml"
    QML_FILE="$SEISCOMP_ROOT/var/lib/events/noto_earthquake.xml"
    if [ ! -s "$SCML_FILE" ] && [ -s "$QML_FILE" ]; then
        su - ga -c "SEISCOMP_ROOT=$SEISCOMP_ROOT PATH=$SEISCOMP_ROOT/bin:\$PATH \
            LD_LIBRARY_PATH=$SEISCOMP_ROOT/lib:\$LD_LIBRARY_PATH \
            PYTHONPATH=$SEISCOMP_ROOT/lib/python:\$PYTHONPATH \
            python3 /workspace/scripts/convert_quakeml.py $QML_FILE $SCML_FILE" 2>/dev/null || true
    fi
    if [ -s "$SCML_FILE" ]; then
        su - ga -c "SEISCOMP_ROOT=$SEISCOMP_ROOT PATH=$SEISCOMP_ROOT/bin:\$PATH \
            LD_LIBRARY_PATH=$SEISCOMP_ROOT/lib:\$LD_LIBRARY_PATH \
            seiscomp exec scdb --plugins dbmysql -i $SCML_FILE \
            -d mysql://sysop:sysop@localhost/seiscomp" 2>/dev/null || true
        sleep 2
    fi
fi

# 3. Record initial state to detect new origins created during the task
echo "--- Recording initial state ---"
INITIAL_ORIGINS=$(seiscomp_db_query "SELECT COUNT(*) FROM Origin WHERE creationInfo_agencyID = 'GYM'" 2>/dev/null || echo "0")
echo "$INITIAL_ORIGINS" > /tmp/initial_gym_origins
echo "Initial GYM origins: $INITIAL_ORIGINS"

# 4. Prepare and launch scolv
echo "--- Launching scolv ---"
kill_seiscomp_gui scolv
launch_seiscomp_gui scolv "--plugins dbmysql -d mysql://sysop:sysop@localhost/seiscomp --load-event-db 1000"

wait_for_window "scolv" 60 || wait_for_window "Origin" 30
sleep 3
dismiss_dialogs 2
focus_and_maximize "scolv" || focus_and_maximize "Origin"
sleep 2

# 5. Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Task setup complete ==="