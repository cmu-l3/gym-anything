#!/bin/bash
echo "=== Setting up disable_station_picking task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming timestamp checks)
date +%s > /tmp/task_start_time.txt

# ─── 1. Ensure SeisComP services are running ───────────────────────────────
echo "--- Ensuring SeisComP services are running ---"
ensure_scmaster_running

# ─── 2. Configure initial bindings for all stations ────────────────────────
echo "--- Configuring Station Bindings ---"

BINDING_DIR="$SEISCOMP_ROOT/etc/key"
mkdir -p "$BINDING_DIR"
mkdir -p "$SEISCOMP_ROOT/etc/defaults"

STATIONS=("TOLI" "GSI" "KWP" "SANI" "BKB")
for STA in "${STATIONS[@]}"; do
    KEY_FILE="$BINDING_DIR/station_GE_${STA}"
    
    # Create the key file with default bindings
    cat > "$KEY_FILE" << EOF
global:default
scautopick:production
EOF
    chown ga:ga "$KEY_FILE"
done

# Ensure a basic scautopick config exists so the module doesn't fail
if [ ! -f "$SEISCOMP_ROOT/etc/scautopick.cfg" ]; then
    cat > "$SEISCOMP_ROOT/etc/scautopick.cfg" << EOF
filter = "BW(3, 0.7, 2.0)"
timeCorr = 0.0
EOF
    chown ga:ga "$SEISCOMP_ROOT/etc/scautopick.cfg"
fi

# ─── 3. Restart scautopick to load new bindings ────────────────────────────
echo "--- Restarting scautopick ---"
su - ga -c "SEISCOMP_ROOT=$SEISCOMP_ROOT PATH=$SEISCOMP_ROOT/bin:\$PATH \
    LD_LIBRARY_PATH=$SEISCOMP_ROOT/lib:\$LD_LIBRARY_PATH \
    seiscomp restart scautopick" || true
sleep 3

# ─── 4. Kill any existing scconfig instances and launch ────────────────────
echo "--- Preparing scconfig ---"
kill_seiscomp_gui scconfig

echo "--- Launching scconfig ---"
launch_seiscomp_gui scconfig "--plugins dbmysql"

wait_for_window "scconfig" 45 || wait_for_window "Configuration" 30 || wait_for_window "SeisComP" 30
sleep 2

# Dismiss any startup dialogs
dismiss_dialogs 2

# Focus and maximize scconfig window
focus_and_maximize "scconfig" || focus_and_maximize "Configuration" || focus_and_maximize "SeisComP"
sleep 2

# ─── 5. Take initial screenshot ────────────────────────────────────────────
echo "--- Taking initial screenshot ---"
take_screenshot /tmp/task_start_screenshot.png
mkdir -p /workspace/evidence
cp /tmp/task_start_screenshot.png /workspace/evidence/ 2>/dev/null || true

echo "=== Task setup complete ==="
echo "Bindings created for stations. Target is GE.KWP."