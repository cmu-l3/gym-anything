#!/bin/bash
echo "=== Setting up configure_playback_processing_pipeline task ==="

source /workspace/scripts/task_utils.sh

TASK="configure_playback_processing_pipeline"

# ─── 1. Ensure services are running ──────────────────────────────────────────

echo "--- Ensuring SeisComP services are running ---"
ensure_scmaster_running

# ─── 2. Clear any existing automatic picks and origins ─────────────────────

echo "--- Clearing existing automatic processing results ---"

# Delete automatic origins (not manual ones from other tasks)
seiscomp_db_query "DELETE FROM Arrival WHERE _parent_oid IN (
    SELECT _oid FROM Origin WHERE evaluationMode='automatic' OR evaluationMode IS NULL
)" 2>/dev/null || true

# Delete automatic picks
seiscomp_db_query "DELETE FROM Pick WHERE evaluationMode='automatic' OR evaluationMode IS NULL" 2>/dev/null || true

# Count remaining origins (keep manual ones)
INITIAL_AUTO_ORIGINS=$(seiscomp_db_query "SELECT COUNT(*) FROM Origin WHERE evaluationMode='automatic'" 2>/dev/null || echo "0")
INITIAL_AUTO_PICKS=$(seiscomp_db_query "SELECT COUNT(*) FROM Pick WHERE evaluationMode='automatic'" 2>/dev/null || echo "0")

echo "Initial automatic origins: $INITIAL_AUTO_ORIGINS"
echo "Initial automatic picks: $INITIAL_AUTO_PICKS"

# ─── 3. Clear module bindings (agent must configure them) ──────────────────

echo "--- Clearing module bindings ---"

for STA in TOLI GSI KWP SANI BKB; do
    KEY_FILE="$SEISCOMP_ROOT/etc/key/station_GE_${STA}"
    # Clear the file but keep it existing
    > "$KEY_FILE"
done
chown -R ga:ga "$SEISCOMP_ROOT/etc/key"

echo "All station key files cleared of bindings"

# ─── 4. Clear scautopick and scautoloc configs ────────────────────────────

echo "--- Clearing module configs ---"

rm -f "$SEISCOMP_ROOT/etc/scautopick.cfg"
rm -f "$SEISCOMP_ROOT/etc/scautoloc.cfg"

# Remove any profiles
rm -rf "$SEISCOMP_ROOT/etc/key/scautopick"

echo "Module configs cleared"

# ─── 5. Ensure waveform data is in SDS archive ───────────────────────────

echo "--- Verifying SDS waveform archive ---"

SDS_ROOT="$SEISCOMP_ROOT/var/lib/archive"
YEAR=2024
DOY=001

for STA in GSI SANI BKB; do
    SDS_DIR="$SDS_ROOT/$YEAR/GE/$STA/BHZ.D"
    SDS_FILE="$SDS_DIR/GE.${STA}..BHZ.D.${YEAR}.${DOY}"
    if [ ! -f "$SDS_FILE" ]; then
        echo "WARNING: Missing SDS file for $STA"
        # Try to copy from bundled data
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

# ─── 6. Record baseline ─────────────────────────────────────────────────

echo "--- Recording baseline ---"

echo "$INITIAL_AUTO_ORIGINS" > /tmp/${TASK}_initial_auto_origins
echo "$INITIAL_AUTO_PICKS" > /tmp/${TASK}_initial_auto_picks
date +%s > /tmp/${TASK}_start_ts

rm -f /home/ga/Desktop/playback_results.txt

echo "Baseline: 0 automatic origins, 0 automatic picks, no results file"

# ─── 7. Launch scconfig for agent to configure bindings ──────────────────

echo "--- Launching scconfig ---"
kill_seiscomp_gui scconfig

launch_seiscomp_gui scconfig

wait_for_window "scconfig" 60 || wait_for_window "Configuration" 30 || wait_for_window "SeisComP" 30

sleep 4
dismiss_dialogs 2
focus_and_maximize "scconfig" || focus_and_maximize "Configuration" || focus_and_maximize "SeisComP"
sleep 2

# ─── 8. Also open a terminal for playback commands ───────────────────────

echo "--- Opening terminal ---"
su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xfce4-terminal --title='SeisComP Terminal'" > /dev/null 2>&1 &
sleep 1
if ! DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "terminal"; then
    su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority gnome-terminal -- bash -i" > /dev/null 2>&1 &
fi
sleep 2

# ─── 9. Take initial screenshot ──────────────────────────────────────────

echo "--- Taking initial screenshot ---"
take_screenshot /tmp/${TASK}_start_screenshot.png
mkdir -p /workspace/evidence
cp /tmp/${TASK}_start_screenshot.png /workspace/evidence/ 2>/dev/null || true

echo "=== Task setup complete ==="
echo "scconfig is open. Station bindings are empty. Module configs are cleared."
echo "Agent must: configure scautopick bindings + filter, configure scautoloc,"
echo "run playback for 2024-001, verify picks/origins, write results summary."
