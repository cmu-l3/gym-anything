#!/bin/bash
echo "=== Setting up airfoil_polar_comparison ==="

source /workspace/scripts/task_utils.sh

# Ensure the 3 required airfoil files exist
AIRFOIL_DIR="/home/ga/Documents/airfoils"
mkdir -p "$AIRFOIL_DIR"

for FOIL in naca0015 naca2412 naca4412; do
    if [ ! -f "$AIRFOIL_DIR/${FOIL}.dat" ]; then
        if [ -f "/workspace/data/airfoils/${FOIL}.dat" ]; then
            cp "/workspace/data/airfoils/${FOIL}.dat" "$AIRFOIL_DIR/${FOIL}.dat"
            echo "Copied ${FOIL}.dat to airfoils directory"
        else
            echo "ERROR: ${FOIL}.dat not found in workspace data"
        fi
    fi
done

# Record baseline: count existing polar files
INITIAL_POLAR_COUNT=$(ls "$AIRFOIL_DIR"/polar_*.txt 2>/dev/null | wc -l)
echo "$INITIAL_POLAR_COUNT" > /tmp/initial_polar_count

# Remove any previous polar output files to ensure clean state
rm -f "$AIRFOIL_DIR/polar_naca0015.txt"
rm -f "$AIRFOIL_DIR/polar_naca2412.txt"
rm -f "$AIRFOIL_DIR/polar_naca4412.txt"

# Record timestamp
date +%s > /tmp/task_start_timestamp

# Launch QBlade
launch_qblade
sleep 8

# Wait for QBlade window
wait_for_qblade 30

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="
