#!/bin/bash
set -e
echo "=== Setting up analyze_aerodynamic_braking_effectiveness task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure output directory exists
mkdir -p /home/ga/Documents/projects
chown ga:ga /home/ga/Documents/projects

# Remove any previous task artifacts
rm -f /home/ga/Documents/projects/braking_analysis.wpa
rm -f /home/ga/Documents/projects/runaway_report.txt
rm -f /tmp/task_result.json

# Check if sample project exists (NREL 5MW)
SAMPLE_DIR="/home/ga/Documents/sample_projects"
NREL_PROJECT=$(find "$SAMPLE_DIR" -name "*NREL*5MW*.wpa" | head -n 1)

if [ -z "$NREL_PROJECT" ]; then
    echo "WARNING: NREL 5MW sample project not found in $SAMPLE_DIR"
    # Fallback: try to find it in the installation directory
    INSTALL_SAMPLE_DIR=$(find /opt/qblade -name "sample projects" -type d 2>/dev/null | head -1)
    if [ -n "$INSTALL_SAMPLE_DIR" ]; then
        echo "Copying from install dir..."
        cp "$INSTALL_SAMPLE_DIR"/*NREL*5MW*.wpa "$SAMPLE_DIR/" 2>/dev/null || true
        chown ga:ga "$SAMPLE_DIR"/*.wpa
    fi
fi

# Launch QBlade
echo "Launching QBlade..."
launch_qblade

# Wait for QBlade to start and stabilize
wait_for_qblade 30

# Maximize window
DISPLAY=:1 wmctrl -r "QBlade" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 2

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="