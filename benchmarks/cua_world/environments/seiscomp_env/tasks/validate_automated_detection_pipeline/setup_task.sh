#!/bin/bash
echo "=== Setting up validate_automated_detection_pipeline task ==="

source /workspace/scripts/task_utils.sh

TASK="validate_automated_detection_pipeline"

# ─── 1. Ensure services are running ──────────────────────────────────────────

echo "--- Ensuring SeisComP services are running ---"
ensure_scmaster_running

# ─── 2. Ensure the Noto earthquake event exists in the database ──────────────

echo "--- Verifying event data ---"
EVENT_COUNT=$(seiscomp_db_query "SELECT COUNT(*) FROM Event" 2>/dev/null || echo "0")
echo "Events in database: $EVENT_COUNT"

if [ "$EVENT_COUNT" = "0" ] || [ -z "$EVENT_COUNT" ]; then
    echo "No events found, attempting to reimport..."
    SCML_FILE="$SEISCOMP_ROOT/var/lib/events/noto_earthquake.scml"
    QUAKEML_FILE="$SEISCOMP_ROOT/var/lib/events/noto_earthquake.xml"

    if [ ! -s "$SCML_FILE" ] && [ -s "$QUAKEML_FILE" ]; then
        echo "Converting QuakeML to SCML..."
        su - ga -c "SEISCOMP_ROOT=$SEISCOMP_ROOT PATH=$SEISCOMP_ROOT/bin:\$PATH \
            LD_LIBRARY_PATH=$SEISCOMP_ROOT/lib:\$LD_LIBRARY_PATH \
            seiscomp exec fdsnxml2inv -f $QUAKEML_FILE $SCML_FILE" 2>/dev/null || true
    fi

    if [ -s "$SCML_FILE" ]; then
        su - ga -c "SEISCOMP_ROOT=$SEISCOMP_ROOT PATH=$SEISCOMP_ROOT/bin:\$PATH \
            LD_LIBRARY_PATH=$SEISCOMP_ROOT/lib:\$LD_LIBRARY_PATH \
            seiscomp exec scdb --plugins dbmysql -i $SCML_FILE \
            -d mysql://sysop:sysop@localhost/seiscomp" 2>/dev/null || true
        sleep 2
    fi
fi

# ─── 3. Clear ALL automatic processing results ──────────────────────────────

echo "--- Clearing automatic processing results ---"

# Delete arrivals linked to automatic origins
seiscomp_db_query "DELETE FROM Arrival WHERE _parent_oid IN (
    SELECT _oid FROM Origin WHERE evaluationMode='automatic' OR evaluationMode IS NULL
)" 2>/dev/null || true

# Delete automatic picks
seiscomp_db_query "DELETE FROM Pick WHERE evaluationMode='automatic' OR evaluationMode IS NULL" 2>/dev/null || true

# Delete automatic origins
seiscomp_db_query "DELETE FROM Origin WHERE evaluationMode='automatic' OR evaluationMode IS NULL" 2>/dev/null || true

# Delete station magnitudes and amplitudes linked to automatic processing
seiscomp_db_query "DELETE FROM StationMagnitude WHERE _parent_oid IN (
    SELECT _oid FROM Origin WHERE evaluationMode='automatic'
)" 2>/dev/null || true
seiscomp_db_query "DELETE FROM Amplitude WHERE pickID LIKE '%automatic%'" 2>/dev/null || true

echo "Automatic picks, origins, and arrivals cleared"

# ─── 4. Clear ALL module bindings ────────────────────────────────────────────

echo "--- Clearing module bindings ---"

for STA in TOLI GSI KWP SANI BKB; do
    KEY_FILE="$SEISCOMP_ROOT/etc/key/station_GE_${STA}"
    > "$KEY_FILE"
done
chown -R ga:ga "$SEISCOMP_ROOT/etc/key"

echo "All station key files cleared of bindings"

# ─── 5. Clear module configs ────────────────────────────────────────────────

echo "--- Clearing module configs ---"

rm -f "$SEISCOMP_ROOT/etc/scautopick.cfg"
rm -f "$SEISCOMP_ROOT/etc/scautoloc.cfg"
rm -rf "$SEISCOMP_ROOT/etc/key/scautopick"

echo "Module configs cleared"

# ─── 6. Ensure waveform data is in SDS archive ──────────────────────────────

echo "--- Verifying SDS waveform archive ---"

SDS_ROOT="$SEISCOMP_ROOT/var/lib/archive"
YEAR=2024
DOY=001

for STA in GSI SANI BKB; do
    SDS_DIR="$SDS_ROOT/$YEAR/GE/$STA/BHZ.D"
    SDS_FILE="$SDS_DIR/GE.${STA}..BHZ.D.${YEAR}.${DOY}"
    if [ ! -f "$SDS_FILE" ]; then
        echo "WARNING: Missing SDS file for $STA"
        BUNDLED="/workspace/data/fdsn/GE.${STA}..BHZ.2024.001.mseed"
        if [ -f "$BUNDLED" ]; then
            mkdir -p "$SDS_DIR"
            cp "$BUNDLED" "$SDS_FILE"
            echo "  Copied from bundled data"
        fi
    else
        echo "  SDS file exists: $SDS_FILE ($(wc -c < "$SDS_FILE") bytes)"
    fi
done

chown -R ga:ga "$SDS_ROOT"

# ─── 7. Configure recordstream for waveform access ──────────────────────────

echo "--- Configuring recordstream ---"

GLOBAL_CFG="$SEISCOMP_ROOT/etc/global.cfg"
if ! grep -q "recordstream" "$GLOBAL_CFG" 2>/dev/null; then
    echo 'recordstream = sdsarchive:///home/ga/seiscomp/var/lib/archive' >> "$GLOBAL_CFG"
    echo "Added recordstream to global.cfg"
fi

chown ga:ga "$GLOBAL_CFG"

# ─── 7b. Ensure scmaster has interface.bind (needed for update-config) ───────

SCMASTER_CFG="$SEISCOMP_ROOT/etc/scmaster.cfg"
if ! grep -q "interface.bind" "$SCMASTER_CFG" 2>/dev/null; then
    echo "interface.bind = 0.0.0.0:18180" >> "$SCMASTER_CFG"
    echo "Added interface.bind to scmaster.cfg"
fi
chown ga:ga "$SCMASTER_CFG"

# ─── 8. Delete stale output files ───────────────────────────────────────────

echo "--- Cleaning stale output files ---"

rm -f /home/ga/validate_pipeline.py
rm -f /home/ga/pipeline_report.json

# ─── 9. Record baseline ─────────────────────────────────────────────────────

echo "--- Recording baseline ---"

INITIAL_AUTO_PICKS=$(seiscomp_db_query "SELECT COUNT(*) FROM Pick WHERE evaluationMode='automatic'" 2>/dev/null || echo "0")
INITIAL_AUTO_ORIGINS=$(seiscomp_db_query "SELECT COUNT(*) FROM Origin WHERE evaluationMode='automatic'" 2>/dev/null || echo "0")

echo "$INITIAL_AUTO_PICKS" > /tmp/${TASK}_initial_auto_picks
echo "$INITIAL_AUTO_ORIGINS" > /tmp/${TASK}_initial_auto_origins
date +%s > /tmp/${TASK}_start_ts

echo "Baseline: $INITIAL_AUTO_PICKS automatic picks, $INITIAL_AUTO_ORIGINS automatic origins"

# ─── 10. Launch scconfig for agent to configure bindings ─────────────────────

echo "--- Launching scconfig ---"
kill_seiscomp_gui scconfig

launch_seiscomp_gui scconfig

wait_for_window "scconfig" 60 || wait_for_window "Configuration" 30 || wait_for_window "SeisComP" 30

sleep 4
dismiss_dialogs 2
focus_and_maximize "scconfig" || focus_and_maximize "Configuration" || focus_and_maximize "SeisComP"
sleep 2

# ─── 11. Also open a terminal for playback and scripting ─────────────────────

echo "--- Opening terminal ---"
su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xfce4-terminal --title='SeisComP Terminal'" > /dev/null 2>&1 &
sleep 2
if ! DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "terminal"; then
    su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority gnome-terminal -- bash -i" > /dev/null 2>&1 &
    sleep 2
fi
if ! DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "terminal\|ga@"; then
    su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xterm -e bash &" > /dev/null 2>&1 &
    sleep 2
fi

# ─── 12. Take initial screenshot ────────────────────────────────────────────

echo "--- Taking initial screenshot ---"
take_screenshot /tmp/${TASK}_start_screenshot.png
mkdir -p /workspace/evidence
cp /tmp/${TASK}_start_screenshot.png /workspace/evidence/ 2>/dev/null || true

echo "=== Task setup complete ==="
echo "scconfig is open. Station bindings are empty. Module configs are cleared."
echo "SDS archive has waveform data for GSI, SANI, BKB (BHZ, day 2024-001)."
echo "Agent must: discover which stations have data, configure scautopick bindings"
echo "with teleseismic filter, run playback, write validation script, produce report."
