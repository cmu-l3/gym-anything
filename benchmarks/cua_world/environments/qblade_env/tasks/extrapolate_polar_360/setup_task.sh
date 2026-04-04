#!/bin/bash
echo "=== Setting up extrapolate_polar_360 ==="

source /workspace/scripts/task_utils.sh

AIRFOIL_DIR="/home/ga/Documents/airfoils"
mkdir -p "$AIRFOIL_DIR"

# Distinct starting state: only naca6412.dat is available
# Remove other airfoils to create a focused, distinct environment
rm -f "$AIRFOIL_DIR"/naca0015.dat "$AIRFOIL_DIR"/naca2412.dat "$AIRFOIL_DIR"/naca4412.dat
rm -f "$AIRFOIL_DIR"/generated_*.dat "$AIRFOIL_DIR"/polar_*.txt

# Ensure naca6412.dat exists
if [ ! -f "$AIRFOIL_DIR/naca6412.dat" ]; then
    if [ -f "/workspace/data/airfoils/naca6412.dat" ]; then
        cp "/workspace/data/airfoils/naca6412.dat" "$AIRFOIL_DIR/naca6412.dat"
        echo "Copied naca6412.dat to airfoils directory"
    else
        echo "ERROR: naca6412.dat not found in workspace data"
    fi
fi

# Record baseline: no 360 polar files should exist
INITIAL_360_COUNT=$(ls "$AIRFOIL_DIR"/*360*.txt 2>/dev/null | wc -l)
echo "$INITIAL_360_COUNT" > /tmp/initial_360_count

# Remove any previous output
rm -f "$AIRFOIL_DIR/naca6412_360polar.txt"

# Record timestamp
date +%s > /tmp/task_start_timestamp

# Launch QBlade
launch_qblade
sleep 8
wait_for_qblade 30

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="
