#!/bin/bash
echo "=== Setting up relocate_event_manual_picks_scolv task ==="

source /workspace/scripts/task_utils.sh

TASK="relocate_event_manual_picks_scolv"

# ─── 1. Ensure services are running ──────────────────────────────────────────

echo "--- Ensuring SeisComP services are running ---"
ensure_scmaster_running

# ─── 2. Verify event data is in the database ─────────────────────────────────

echo "--- Verifying event data ---"

EVENT_COUNT=$(seiscomp_db_query "SELECT COUNT(*) FROM Event" 2>/dev/null || echo "0")
echo "Events in database: $EVENT_COUNT"

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

# ─── 3. Reset event to automatic evaluation mode (remove any prior manual origins) ──

echo "--- Resetting event evaluation mode ---"

# Delete any manually-created origins so the test starts from automatic-only state
# This ensures do-nothing test will correctly return score=0
seiscomp_db_query "UPDATE Origin SET evaluationMode='automatic' WHERE evaluationMode IS NOT NULL" 2>/dev/null || true
seiscomp_db_query "DELETE FROM Arrival WHERE _oid IN (
    SELECT a._oid FROM Arrival a JOIN Origin o ON a._parent_oid = o._oid
    WHERE o.evaluationMode = 'manual'
)" 2>/dev/null || true
seiscomp_db_query "DELETE FROM Origin WHERE evaluationMode = 'manual'" 2>/dev/null || true

# ─── 4. Record baseline state ────────────────────────────────────────────────

echo "--- Recording baseline state ---"

# Count of manual origins (should be 0 after reset)
INITIAL_MANUAL_COUNT=$(seiscomp_db_query "SELECT COUNT(*) FROM Origin WHERE evaluationMode='manual'" 2>/dev/null || echo "0")
echo "$INITIAL_MANUAL_COUNT" > /tmp/${TASK}_initial_manual_count
echo "Initial manual origins: $INITIAL_MANUAL_COUNT"

# Record initial (automatic) origin coordinates as reference
INITIAL_ORIGIN_LAT=$(seiscomp_db_query "SELECT latitude_value FROM Origin WHERE evaluationMode='automatic' ORDER BY _oid DESC LIMIT 1" 2>/dev/null || echo "0")
INITIAL_ORIGIN_LON=$(seiscomp_db_query "SELECT longitude_value FROM Origin WHERE evaluationMode='automatic' ORDER BY _oid DESC LIMIT 1" 2>/dev/null || echo "0")
echo "$INITIAL_ORIGIN_LAT" > /tmp/${TASK}_initial_lat
echo "$INITIAL_ORIGIN_LON" > /tmp/${TASK}_initial_lon
echo "Initial auto origin: lat=$INITIAL_ORIGIN_LAT lon=$INITIAL_ORIGIN_LON"

# Record timestamp
date +%s > /tmp/${TASK}_start_ts
echo "Task start timestamp recorded"

# ─── 5. Configure scolv for waveform access ──────────────────────────────────

echo "--- Configuring scolv ---"

# Ensure SDS archive is accessible and scolv config enables it
cat > "$SEISCOMP_ROOT/etc/scolv.cfg" << 'CFGEOF'
loadEventDB = 1000
# Enable SDS waveform record stream
recordstream = sds://var/lib/archive
CFGEOF
chown ga:ga "$SEISCOMP_ROOT/etc/scolv.cfg" 2>/dev/null || true

# ─── 6. Kill any existing scolv, then launch fresh ───────────────────────────

echo "--- Launching scolv ---"
kill_seiscomp_gui scolv

launch_seiscomp_gui scolv "--plugins dbmysql -d mysql://sysop:sysop@localhost/seiscomp --load-event-db 1000"

wait_for_window "scolv" 60 || wait_for_window "Origin" 30 || wait_for_window "SeisComP" 30

sleep 4
dismiss_dialogs 2
focus_and_maximize "scolv" || focus_and_maximize "Origin" || focus_and_maximize "SeisComP"
sleep 2

# ─── 7. Take initial screenshot ──────────────────────────────────────────────

echo "--- Taking initial screenshot ---"
take_screenshot /tmp/${TASK}_start_screenshot.png
mkdir -p /workspace/evidence
cp /tmp/${TASK}_start_screenshot.png /workspace/evidence/ 2>/dev/null || true

echo "=== Task setup complete ==="
echo "scolv is open with the Noto earthquake event."
echo "Agent must: open waveform picker, re-pick P arrivals on GE.GSI/BKB/SANI, relocate, commit."
