#!/bin/bash
echo "=== Setting up refine_magnitude_outliers_scolv task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# ─── 1. Ensure services are running ──────────────────────────────────────────
echo "--- Ensuring SeisComP services are running ---"
ensure_scmaster_running

# ─── 2. Verify and prepare event data ────────────────────────────────────────
echo "--- Verifying event data in database ---"
EVENT_COUNT=$(seiscomp_db_query "SELECT COUNT(*) FROM Event" 2>/dev/null || echo "0")
echo "Events in database: $EVENT_COUNT"

# If no events, try reimporting
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

# Ensure event belongs to USGS so it must be adopted
seiscomp_db_query "UPDATE Event SET creationInfo_agencyID='USGS' WHERE 1=1" 2>/dev/null || true

# Record initial preferred magnitude ID
INITIAL_MAG_ID=$(seiscomp_db_query "SELECT preferredMagnitudeID FROM Event ORDER BY _oid DESC LIMIT 1" 2>/dev/null || echo "NONE")
echo "$INITIAL_MAG_ID" > /tmp/initial_mag_id.txt
echo "Initial Preferred Magnitude ID: $INITIAL_MAG_ID"

# ─── 3. Prepare scolv ────────────────────────────────────────────────────────
echo "--- Preparing scolv ---"
kill_seiscomp_gui scolv

echo "--- Launching scolv ---"
# Launch scolv loading the last 1000 days so the 2024 event shows up
launch_seiscomp_gui scolv "--plugins dbmysql -d mysql://sysop:sysop@localhost/seiscomp --load-event-db 1000"

# Wait for scolv window to appear
wait_for_window "scolv" 45 || wait_for_window "Origin" 30 || wait_for_window "SeisComP" 30
sleep 3

# Dismiss any startup dialogs
dismiss_dialogs 3

# Focus and maximize scolv window
focus_and_maximize "scolv" || focus_and_maximize "Origin" || focus_and_maximize "SeisComP"
sleep 2

# Take initial screenshot
echo "--- Taking initial screenshot ---"
take_screenshot /tmp/task_initial.png
mkdir -p /workspace/evidence
cp /tmp/task_initial.png /workspace/evidence/ 2>/dev/null || true

echo "=== Task setup complete ==="