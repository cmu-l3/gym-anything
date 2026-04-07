#!/bin/bash
set -e
echo "=== Setting up openice_data_model_fhir_mapping task ==="

export DISPLAY=:1
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt
echo "Task start time: $(cat /tmp/task_start_time.txt)"

# Record initial log size for new-lines-only analysis
LOG_FILE="/home/ga/openice/logs/openice.log"
if [ -f "$LOG_FILE" ]; then
    INITIAL_LOG_SIZE=$(stat -c%s "$LOG_FILE" 2>/dev/null || echo "0")
else
    INITIAL_LOG_SIZE=0
fi
echo "$INITIAL_LOG_SIZE" > /tmp/initial_log_size.txt
echo "Initial log size: $INITIAL_LOG_SIZE bytes"

# Record initial window list
DISPLAY=:1 wmctrl -l 2>/dev/null > /tmp/initial_windows.txt || true
INITIAL_WINDOW_COUNT=$(wc -l < /tmp/initial_windows.txt)
echo "$INITIAL_WINDOW_COUNT" > /tmp/initial_window_count.txt

# Remove any pre-existing deliverable files (clean state)
rm -f /home/ga/Desktop/openice_data_dictionary.txt 2>/dev/null || true
rm -f /home/ga/Desktop/fhir_mapping_proposal.txt 2>/dev/null || true

# Ensure OpenICE source code is accessible
if [ ! -d "/opt/openice/mdpnp/interop-lab" ]; then
    echo "ERROR: OpenICE source code not found at expected location"
    # Try to clone if missing (fallback)
    mkdir -p /opt/openice
    cd /opt/openice
    git clone --depth 1 https://github.com/mdpnp/mdpnp.git || echo "Warning: Clone failed"
fi

# Ensure OpenICE application is running
if ! is_openice_running; then
    echo "Starting OpenICE..."
    ensure_openice_running
    # Give it plenty of time to fully initialize JavaFX
    sleep 30
fi

# Focus and maximize OpenICE window
focus_openice_window || true
sleep 1
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_initial_state.png

echo "=== Task setup complete ==="