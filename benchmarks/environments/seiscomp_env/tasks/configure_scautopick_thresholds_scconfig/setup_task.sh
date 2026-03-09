#!/bin/bash
echo "=== Setting up configure_scautopick_thresholds_scconfig task ==="

source /workspace/scripts/task_utils.sh

TASK="configure_scautopick_thresholds_scconfig"

# ─── 1. Ensure services are running ──────────────────────────────────────────

echo "--- Ensuring SeisComP services are running ---"
ensure_scmaster_running

# ─── 2. Clear any existing scautopick.cfg so agent starts from scratch ────────

echo "--- Resetting scautopick configuration ---"

SCAUTOPICK_CFG="$SEISCOMP_ROOT/etc/scautopick.cfg"

# Record what was there initially
if [ -f "$SCAUTOPICK_CFG" ]; then
    cp "$SCAUTOPICK_CFG" /tmp/${TASK}_initial_config.bak 2>/dev/null || true
fi

# Remove the config file entirely so the agent must create it fresh via GUI
rm -f "$SCAUTOPICK_CFG" 2>/dev/null || true

# Verify it's gone
if [ ! -f "$SCAUTOPICK_CFG" ]; then
    echo "scautopick.cfg cleared (starting from no config)"
else
    echo "WARN: Could not clear scautopick.cfg"
fi

# Record baseline state
echo "0" > /tmp/${TASK}_initial_filter_set
date +%s > /tmp/${TASK}_start_ts
echo "Baseline state recorded"

# ─── 3. Kill any existing scconfig instances ──────────────────────────────────

echo "--- Preparing scconfig ---"
kill_seiscomp_gui scconfig

# ─── 4. Launch scconfig ──────────────────────────────────────────────────────

echo "--- Launching scconfig ---"
launch_seiscomp_gui scconfig "--plugins dbmysql"

wait_for_window "scconfig" 60 || wait_for_window "Configuration" 30 || wait_for_window "SeisComP" 30

sleep 3
dismiss_dialogs 2
focus_and_maximize "scconfig" || focus_and_maximize "Configuration" || focus_and_maximize "SeisComP"
sleep 2

# ─── 5. Take initial screenshot ──────────────────────────────────────────────

echo "--- Taking initial screenshot ---"
take_screenshot /tmp/${TASK}_start_screenshot.png
mkdir -p /workspace/evidence
cp /tmp/${TASK}_start_screenshot.png /workspace/evidence/ 2>/dev/null || true

echo "=== Task setup complete ==="
echo "scconfig is open. Agent must navigate to Module Parameters > scautopick"
echo "and set: filter=BW(4,4,20), thresholds.trigOn=3.5, thresholds.trigOff=1.5, picker.AIC.minSNR=2.0"
