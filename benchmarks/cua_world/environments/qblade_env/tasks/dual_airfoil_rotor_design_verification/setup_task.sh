#!/bin/bash
set -e
echo "=== Setting up dual_airfoil_rotor_design_verification task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# 1. Clean up any previous attempts BEFORE recording timestamp
rm -f /home/ga/Documents/results/dual_airfoil_turbine.wpa
rm -f /home/ga/Documents/results/cp_tsr_sweep.dat
rm -f /home/ga/Documents/results/performance_summary.txt
rm -f /tmp/task_result.json
rm -f /tmp/task_initial.png
rm -f /tmp/task_final.png

# 2. Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# 3. Ensure output directories exist
mkdir -p /home/ga/Documents/results
mkdir -p /home/ga/Documents/airfoils
mkdir -p /home/ga/Documents/projects
chown -R ga:ga /home/ga/Documents

# 4. Verify airfoil data files are available
AIRFOIL_DIR="/home/ga/Documents/airfoils"
if [ ! -f "$AIRFOIL_DIR/naca0015.dat" ]; then
    if [ -f /workspace/data/airfoils/naca0015.dat ]; then
        cp /workspace/data/airfoils/naca0015.dat "$AIRFOIL_DIR/"
    fi
fi
if [ ! -f "$AIRFOIL_DIR/naca4412.dat" ]; then
    if [ -f /workspace/data/airfoils/naca4412.dat ]; then
        cp /workspace/data/airfoils/naca4412.dat "$AIRFOIL_DIR/"
    fi
fi
chown ga:ga "$AIRFOIL_DIR"/*.dat 2>/dev/null || true

# 5. Record sample project hashes for anti-copy detection
SAMPLE_DIR="/home/ga/Documents/sample_projects"
if [ -d "$SAMPLE_DIR" ]; then
    md5sum "$SAMPLE_DIR"/*.wpa 2>/dev/null | awk '{print $1}' | sort > /tmp/sample_hashes.txt
else
    touch /tmp/sample_hashes.txt
fi

# 6. Launch QBlade (fresh session)
echo "Launching QBlade..."
launch_qblade
sleep 5

# 7. Wait for window and maximize
wait_for_qblade 30
DISPLAY=:1 wmctrl -r "QBlade" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "QBlade" 2>/dev/null || true

# 8. Dismiss any startup dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 0.5

# 9. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="
