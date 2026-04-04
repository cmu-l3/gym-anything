#!/bin/bash
set -e
echo "=== Setting up Multi-Parameter BEM Map Task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# 1. Record task start time (anti-gaming)
date +%s > /tmp/task_start_time.txt

# 2. Clean up previous artifacts
OUTPUT_FILE="/home/ga/Documents/projects/performance_map.wpa"
rm -f "$OUTPUT_FILE" 2>/dev/null || true
mkdir -p /home/ga/Documents/projects
chown ga:ga /home/ga/Documents/projects

# 3. Verify sample data availability
# Ensure we have at least one valid .wpa file in sample_projects
SAMPLE_DIR="/home/ga/Documents/sample_projects"
mkdir -p "$SAMPLE_DIR"
COUNT=$(find "$SAMPLE_DIR" -name "*.wpa" | wc -l)

if [ "$COUNT" -eq 0 ]; then
    echo "WARNING: No sample projects found in $SAMPLE_DIR. Attempting to recover from install..."
    INSTALL_SAMPLES=$(find /opt/qblade -name "sample projects" -type d 2>/dev/null | head -1)
    if [ -z "$INSTALL_SAMPLES" ]; then
         INSTALL_SAMPLES=$(find /opt/qblade -name "sampleprojects" -type d 2>/dev/null | head -1)
    fi
    
    if [ -n "$INSTALL_SAMPLES" ]; then
        cp "$INSTALL_SAMPLES"/*.wpa "$SAMPLE_DIR/" 2>/dev/null || true
        chown ga:ga "$SAMPLE_DIR"/*.wpa
        echo "Recovered sample projects."
    else
        echo "ERROR: Critical failure - no sample projects available."
        # We don't exit here to avoid crashing the container, but the task will likely fail
    fi
fi

# 4. Launch QBlade
echo "Launching QBlade..."
launch_qblade
sleep 10

# 5. Wait for window and maximize
wait_for_qblade 60

# Maximize (Standard wmctrl interaction)
DISPLAY=:1 wmctrl -r "QBlade" -b add,maximized_vert,maximized_horz 2>/dev/null || true
# Ensure it is focused
DISPLAY=:1 wmctrl -a "QBlade" 2>/dev/null || true

# 6. Capture initial state
take_screenshot /tmp/task_initial_state.png

echo "=== Task setup complete ==="