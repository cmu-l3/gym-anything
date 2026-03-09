#!/bin/bash
echo "=== Setting up set_event_certainty_scolv task ==="

source /workspace/scripts/task_utils.sh

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

# Record initial state
INITIAL_CERTAINTY=$(seiscomp_db_query "SELECT typeCertainty FROM Event ORDER BY _oid DESC LIMIT 1" 2>/dev/null || echo "NULL")
echo "$INITIAL_CERTAINTY" > /tmp/initial_type_certainty
echo "Initial type certainty: $INITIAL_CERTAINTY"

# ─── 3. Kill any existing scolv instances ─────────────────────────────────────

echo "--- Preparing scolv ---"
kill_seiscomp_gui scolv

# ─── 4. Launch scolv ─────────────────────────────────────────────────────────

echo "--- Launching scolv ---"
launch_seiscomp_gui scolv "--plugins dbmysql -d mysql://sysop:sysop@localhost/seiscomp --load-event-db 1000"

wait_for_window "scolv" 60 || wait_for_window "Origin" 30 || wait_for_window "SeisComP" 30

sleep 3

# ─── 5. Dismiss any startup dialogs ──────────────────────────────────────────

dismiss_dialogs 2

# ─── 6. Focus and maximize scolv window ──────────────────────────────────────

focus_and_maximize "scolv" || focus_and_maximize "Origin" || focus_and_maximize "SeisComP"

sleep 2

# ─── 7. Take initial screenshot ──────────────────────────────────────────────

echo "--- Taking initial screenshot ---"
take_screenshot /tmp/task_start_screenshot.png
mkdir -p /workspace/evidence
cp /tmp/task_start_screenshot.png /workspace/evidence/ 2>/dev/null || true

echo "=== Task setup complete ==="
echo "scolv should be visible with earthquake event(s)."
echo "Agent should find the Type certainty dropdown and change it to 'known'."
