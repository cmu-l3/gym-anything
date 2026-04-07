#!/bin/bash
echo "=== Setting up evaluate_network_azimuthal_gap task ==="

# Record task start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

# Ensure SeisComP database is running
echo "--- Starting MariaDB if needed ---"
systemctl start mariadb 2>/dev/null || true
sleep 3

# Delete any pre-existing report files
rm -f /home/ga/azimuthal_gap_report.json
rm -f /tmp/task_result.json
rm -f /tmp/ground_truth.json
rm -f /tmp/stations.txt

# Ensure SeisComP environment is somewhat populated (triggers bundled import if needed)
if [ -f /workspace/scripts/task_utils.sh ]; then
    source /workspace/scripts/task_utils.sh
    ensure_scmaster_running 2>/dev/null || true
fi

# Ensure window focus in case the agent opens graphical tools
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take an initial screenshot for the trajectory
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="