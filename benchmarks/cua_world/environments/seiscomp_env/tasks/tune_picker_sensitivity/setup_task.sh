#!/bin/bash
echo "=== Setting up tune_picker_sensitivity task ==="

source /workspace/scripts/task_utils.sh

# ─── 1. Ensure SeisComP services are running ─────────────────────────────────
ensure_scmaster_running

# ─── 2. Clean database of any existing picks for KWP ─────────────────────────
echo "Cleaning old picks for station KWP..."
mysql -u sysop -psysop seiscomp -e "DELETE FROM Pick WHERE stream_stationCode='KWP';" 2>/dev/null || true

# ─── 3. Set up misconfigured profile "HighThreshold" for scautopick ──────────
echo "Configuring HighThreshold profile..."
mkdir -p "$SEISCOMP_ROOT/etc/key/scautopick/profile_HighThreshold"
cat > "$SEISCOMP_ROOT/etc/key/scautopick/profile_HighThreshold/config" << 'EOF'
detecFilter = "RMHP(10)->ITAPER(30)->BW(4,0.7,2)->STALTA(2,80)"
trigOn = 25.0
trigOff = 1.5
EOF

# Ensure station key exists and bind to profile
touch "$SEISCOMP_ROOT/etc/key/station_GE_KWP"
echo "profile:HighThreshold" > "$SEISCOMP_ROOT/etc/key/station_GE_KWP_scautopick"

chown -R ga:ga "$SEISCOMP_ROOT/etc/key"

# Apply the configuration
su - ga -c "SEISCOMP_ROOT=$SEISCOMP_ROOT PATH=$SEISCOMP_ROOT/bin:\$PATH LD_LIBRARY_PATH=$SEISCOMP_ROOT/lib:\$LD_LIBRARY_PATH seiscomp update-config" 2>/dev/null

# ─── 4. Record initial state ─────────────────────────────────────────────────
INITIAL_PICKS=$(mysql -u sysop -psysop seiscomp -N -e "SELECT COUNT(*) FROM Pick WHERE stream_stationCode='KWP'" 2>/dev/null || echo "0")
echo "$INITIAL_PICKS" > /tmp/initial_pick_count
date +%s > /tmp/task_start_time.txt
echo "Initial picks for KWP: $INITIAL_PICKS"

# ─── 5. Prepare environment for agent ────────────────────────────────────────
# Open an xterm for command-line execution
su - ga -c "DISPLAY=:1 xterm -geometry 80x24+100+100 &"

# Launch scconfig
kill_seiscomp_gui scconfig
launch_seiscomp_gui scconfig "--plugins dbmysql"

wait_for_window "scconfig" 30 || wait_for_window "Configuration" 15
sleep 3
dismiss_dialogs 2
focus_and_maximize "scconfig" || focus_and_maximize "Configuration"
sleep 2

# Take initial screenshot for evidence
take_screenshot /tmp/task_start.png

echo "=== Task setup complete ==="