#!/bin/bash
echo "=== Setting up enable_scautopick_scconfig task ==="

source /workspace/scripts/task_utils.sh

# ─── 1. Ensure services are running ──────────────────────────────────────────

echo "--- Ensuring SeisComP services are running ---"
ensure_scmaster_running

# ─── 2. Ensure scautopick is disabled ─────────────────────────────────────────

echo "--- Ensuring scautopick is disabled ---"

# Disable scautopick if it's enabled (ensure clean start state)
su - ga -c "SEISCOMP_ROOT=$SEISCOMP_ROOT PATH=$SEISCOMP_ROOT/bin:\$PATH \
    LD_LIBRARY_PATH=$SEISCOMP_ROOT/lib:\$LD_LIBRARY_PATH \
    seiscomp disable scautopick" 2>/dev/null || true

# Record initial state
ENABLED=$(su - ga -c "SEISCOMP_ROOT=$SEISCOMP_ROOT PATH=$SEISCOMP_ROOT/bin:\$PATH \
    LD_LIBRARY_PATH=$SEISCOMP_ROOT/lib:\$LD_LIBRARY_PATH \
    seiscomp list enabled 2>/dev/null" | grep -c "scautopick" || echo "0")
echo "scautopick enabled: $ENABLED"
echo "$ENABLED" > /tmp/initial_scautopick_state

# ─── 3. Kill any existing scconfig instances ──────────────────────────────────

echo "--- Preparing scconfig ---"
kill_seiscomp_gui scconfig

# ─── 4. Launch scconfig ──────────────────────────────────────────────────────

echo "--- Launching scconfig ---"
launch_seiscomp_gui scconfig "--plugins dbmysql"

wait_for_window "scconfig" 60 || wait_for_window "Configuration" 30 || wait_for_window "SeisComP" 30

sleep 3

# ─── 5. Dismiss any startup dialogs ──────────────────────────────────────────

dismiss_dialogs 2

# ─── 6. Focus and maximize scconfig window ────────────────────────────────────

focus_and_maximize "scconfig" || focus_and_maximize "Configuration" || focus_and_maximize "SeisComP"

sleep 2

# ─── 7. Take initial screenshot ──────────────────────────────────────────────

echo "--- Taking initial screenshot ---"
take_screenshot /tmp/task_start_screenshot.png
mkdir -p /workspace/evidence
cp /tmp/task_start_screenshot.png /workspace/evidence/ 2>/dev/null || true

echo "=== Task setup complete ==="
echo "scconfig should be visible on the System panel."
echo "Agent should enable scautopick module and save."
