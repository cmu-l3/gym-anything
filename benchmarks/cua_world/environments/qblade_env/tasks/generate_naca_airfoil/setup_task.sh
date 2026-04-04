#!/bin/bash
echo "=== Setting up generate_naca_airfoil task ==="

# Clean up any leftover temp files from previous tasks
rm -f /tmp/initial_* /tmp/ground_truth_* /tmp/task_result.json /tmp/task_end.png 2>/dev/null || true

# Record initial state: count existing airfoil files
AIRFOIL_DIR="/home/ga/Documents/airfoils"
INITIAL_COUNT=$(ls "$AIRFOIL_DIR"/*.dat 2>/dev/null | wc -l)
echo "$INITIAL_COUNT" > /tmp/initial_airfoil_count

# Remove any previous generated output to ensure fresh task
rm -f "$AIRFOIL_DIR/generated_naca4412.dat" 2>/dev/null || true

echo "Initial airfoil count: $INITIAL_COUNT"

# Launch QBlade
echo "Launching QBlade..."
source /workspace/scripts/task_utils.sh
launch_qblade

# Wait for QBlade to start
sleep 8

echo "=== Task setup complete ==="
