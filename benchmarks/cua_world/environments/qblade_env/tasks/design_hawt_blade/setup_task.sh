#!/bin/bash
echo "=== Setting up design_hawt_blade task ==="

# Clean up leftover temp files from previous tasks
rm -f /tmp/initial_* /tmp/ground_truth_* /tmp/task_result.json /tmp/task_end.png 2>/dev/null || true

# Ensure output directory exists
mkdir -p /home/ga/Documents/projects
chown ga:ga /home/ga/Documents/projects

# Remove any previous blade project output
rm -f /home/ga/Documents/projects/hawt_blade.wpa 2>/dev/null || true

# Ensure airfoil data is available
if [ ! -f /home/ga/Documents/airfoils/naca4412.dat ]; then
    cp /workspace/data/airfoils/naca4412.dat /home/ga/Documents/airfoils/ 2>/dev/null || true
    chown ga:ga /home/ga/Documents/airfoils/naca4412.dat 2>/dev/null || true
fi

# Launch QBlade
echo "Launching QBlade..."
source /workspace/scripts/task_utils.sh
launch_qblade

# Wait for QBlade to start
sleep 8

echo "=== Task setup complete ==="
