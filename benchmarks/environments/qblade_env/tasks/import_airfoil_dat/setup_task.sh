#!/bin/bash
echo "=== Setting up import_airfoil_dat task ==="

# Clean up any leftover temp files from previous tasks
rm -f /tmp/initial_* /tmp/ground_truth_* /tmp/task_result.json /tmp/task_end.png 2>/dev/null || true

# Verify input airfoil file exists
INPUT_FILE="/home/ga/Documents/airfoils/naca2412.dat"
if [ ! -f "$INPUT_FILE" ]; then
    echo "ERROR: Input airfoil file not found at $INPUT_FILE"
    # Try to copy from workspace data
    cp /workspace/data/airfoils/naca2412.dat "$INPUT_FILE" 2>/dev/null || true
fi

# Record initial state
LINES=$(wc -l < "$INPUT_FILE" 2>/dev/null || echo "0")
echo "$LINES" > /tmp/initial_airfoil_lines

# Remove any previous polar output
rm -f /home/ga/Documents/airfoils/naca2412_polar.txt 2>/dev/null || true

echo "Input file: $INPUT_FILE ($LINES lines)"

# Launch QBlade
echo "Launching QBlade..."
source /workspace/scripts/task_utils.sh
launch_qblade

# Wait for QBlade to start
sleep 8

echo "=== Task setup complete ==="
