#!/bin/bash
set -e
echo "=== Setting up tune_blade_stiffness_resonance task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure directories exist
mkdir -p /home/ga/Documents/projects
chown -R ga:ga /home/ga/Documents/projects

# Clean up previous outputs
rm -f /home/ga/Documents/projects/stiffened_blade.wpa
rm -f /home/ga/Documents/projects/resonance_report.txt
rm -f /tmp/task_result.json

# Locate the NREL 5MW sample project for baseline comparison later
SAMPLE_DIR=$(find /opt/qblade -name "sample projects" -type d 2>/dev/null | head -1)
if [ -z "$SAMPLE_DIR" ]; then
    SAMPLE_DIR=$(find /opt/qblade -iname "sampleprojects" -type d 2>/dev/null | head -1)
fi
if [ -z "$SAMPLE_DIR" ]; then
    SAMPLE_DIR="/home/ga/Documents/sample_projects"
fi

# Find the specific NREL 5MW file
BASELINE_PROJECT=$(find "$SAMPLE_DIR" -name "*NREL*5MW*.wpa" | head -1)
if [ -n "$BASELINE_PROJECT" ]; then
    echo "Found baseline project: $BASELINE_PROJECT"
    # Calculate baseline hash to detect if agent just saves the same file
    md5sum "$BASELINE_PROJECT" > /tmp/baseline_project.md5
else
    echo "WARNING: NREL 5MW sample project not found in $SAMPLE_DIR"
fi

# Launch QBlade
echo "Launching QBlade..."
launch_qblade

# Wait for QBlade window
wait_for_qblade 30

# Maximize window
DISPLAY=:1 wmctrl -r "QBlade" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="