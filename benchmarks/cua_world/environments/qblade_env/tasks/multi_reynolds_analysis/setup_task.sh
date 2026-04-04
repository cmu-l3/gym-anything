#!/bin/bash
echo "=== Setting up multi_reynolds_analysis ==="

source /workspace/scripts/task_utils.sh

AIRFOIL_DIR="/home/ga/Documents/airfoils"
mkdir -p "$AIRFOIL_DIR"

# Distinct starting state: only naca4412.dat available
rm -f "$AIRFOIL_DIR"/naca0015.dat "$AIRFOIL_DIR"/naca2412.dat "$AIRFOIL_DIR"/naca6412.dat
rm -f "$AIRFOIL_DIR"/generated_*.dat "$AIRFOIL_DIR"/polar_*.txt

# Ensure naca4412.dat exists
if [ ! -f "$AIRFOIL_DIR/naca4412.dat" ]; then
    if [ -f "/workspace/data/airfoils/naca4412.dat" ]; then
        cp "/workspace/data/airfoils/naca4412.dat" "$AIRFOIL_DIR/naca4412.dat"
        echo "Copied naca4412.dat to airfoils directory"
    else
        echo "ERROR: naca4412.dat not found in workspace data"
    fi
fi

# Record baseline
INITIAL_POLAR_COUNT=$(ls "$AIRFOIL_DIR"/polar_re*.txt 2>/dev/null | wc -l)
echo "$INITIAL_POLAR_COUNT" > /tmp/initial_polar_count

# Remove any previous outputs
rm -f "$AIRFOIL_DIR/polar_re200k.txt"
rm -f "$AIRFOIL_DIR/polar_re500k.txt"
rm -f "$AIRFOIL_DIR/polar_re1m.txt"

# Record timestamp
date +%s > /tmp/task_start_timestamp

# Launch QBlade
launch_qblade
sleep 8
wait_for_qblade 30

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="
