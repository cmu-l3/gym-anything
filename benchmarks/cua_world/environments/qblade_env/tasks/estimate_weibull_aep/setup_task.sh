#!/bin/bash
echo "=== Setting up estimate_weibull_aep task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Clean up previous run artifacts
rm -f /home/ga/Documents/aep_report.txt 2>/dev/null || true
rm -f /tmp/task_result.json 2>/dev/null || true
rm -f /tmp/task_final.png 2>/dev/null || true

# Ensure sample projects are available
mkdir -p /home/ga/Documents/sample_projects
if [ -d "/opt/qblade/sample_projects" ]; then
    cp -n /opt/qblade/sample_projects/*.wpa /home/ga/Documents/sample_projects/ 2>/dev/null || true
fi

# Ensure QBlade is running and maximized
if ! is_qblade_running > /dev/null; then
    echo "Launching QBlade..."
    launch_qblade
    
    # Wait for window
    wait_for_qblade 30
    
    # Maximize window
    sleep 2
    DISPLAY=:1 wmctrl -r "QBlade" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Take initial screenshot for evidence
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="