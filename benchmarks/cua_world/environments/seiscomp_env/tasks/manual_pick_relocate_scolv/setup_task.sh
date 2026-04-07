#!/bin/bash
echo "=== Setting up manual_pick_relocate_scolv task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (Unix timestamp)
date +%s > /tmp/task_start_time.txt

# Configure global recordstream to point to local SDS archive
# This ensures scolv can load waveforms automatically without agent configuring it
if ! grep -q "recordstream.service" $SEISCOMP_ROOT/etc/global.cfg 2>/dev/null; then
    echo "recordstream.service = sdsarchive" >> $SEISCOMP_ROOT/etc/global.cfg
    echo "recordstream.source = /home/ga/seiscomp/var/lib/archive" >> $SEISCOMP_ROOT/etc/global.cfg
fi

# Ensure scmaster is running
ensure_scmaster_running

# Verify event data is in the database
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

# Record initial counts to check against
INITIAL_PICK_COUNT=$(seiscomp_db_query "SELECT COUNT(*) FROM Pick WHERE waveformID_stationCode='TOLI'" 2>/dev/null || echo "0")
echo "$INITIAL_PICK_COUNT" > /tmp/initial_toli_pick_count
echo "Initial manual picks for GE.TOLI: $INITIAL_PICK_COUNT"

# Kill any existing scolv instances to start fresh
kill_seiscomp_gui scolv

echo "--- Launching scolv ---"
launch_seiscomp_gui scolv "--plugins dbmysql -d mysql://sysop:sysop@localhost/seiscomp --load-event-db 1000"

# Wait for scolv window to appear
wait_for_window "scolv" 60 || wait_for_window "Origin" 30 || wait_for_window "SeisComP" 30
sleep 3

# Dismiss any startup dialogs
dismiss_dialogs 2

# Focus and maximize scolv
focus_and_maximize "scolv" || focus_and_maximize "Origin" || focus_and_maximize "SeisComP"
sleep 2

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png
mkdir -p /workspace/evidence
cp /tmp/task_start_screenshot.png /workspace/evidence/ 2>/dev/null || true

echo "=== Task setup complete ==="