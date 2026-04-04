#!/bin/bash
set -e
echo "=== Setting up Stall Margin Assessment Task ==="

# Source utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# 1. Clean up previous run artifacts
echo "Cleaning up previous artifacts..."
rm -f /home/ga/Documents/stall_margin_report.txt
rm -f /home/ga/Documents/projects/stall_assessment.wpa
rm -f /tmp/task_result.json
rm -f /tmp/task_final.png

# 2. Record Task Start Time (Critical for anti-gaming)
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded: $(cat /tmp/task_start_time.txt)"

# 3. Ensure directories exist
mkdir -p /home/ga/Documents/projects
mkdir -p /home/ga/Documents/airfoils
chown -R ga:ga /home/ga/Documents

# 4. Launch QBlade
echo "Launching QBlade..."
if type launch_qblade &>/dev/null; then
    launch_qblade
else
    # Fallback if utility not found
    su - ga -c "export DISPLAY=:1; /opt/qblade/QBlade > /tmp/qblade.log 2>&1 &"
fi

# 5. Wait for QBlade to stabilize
echo "Waiting for QBlade to start..."
sleep 8
# Maximize window (helps agent visibility)
DISPLAY=:1 wmctrl -r "QBlade" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "QBlade" 2>/dev/null || true

# 6. Capture Initial Screenshot
take_screenshot /tmp/task_initial.png 2>/dev/null || DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="