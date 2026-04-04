#!/bin/bash
echo "=== Setting up run_bem_simulation task ==="

# Clean up leftover temp files
rm -f /tmp/initial_* /tmp/ground_truth_* /tmp/task_result.json /tmp/task_end.png 2>/dev/null || true

# Ensure output directory exists
mkdir -p /home/ga/Documents/projects
chown ga:ga /home/ga/Documents/projects

# Record initial state
INITIAL_RESULTS=$(find /home/ga/Documents/projects -name "*.txt" -o -name "*.csv" 2>/dev/null | wc -l)
echo "$INITIAL_RESULTS" > /tmp/initial_results_count

# Remove previous output
rm -f /home/ga/Documents/projects/bem_results.txt 2>/dev/null || true

# Ensure airfoil data is available
if [ ! -f /home/ga/Documents/airfoils/naca4412.dat ]; then
    cp /workspace/data/airfoils/naca4412.dat /home/ga/Documents/airfoils/ 2>/dev/null || true
    chown ga:ga /home/ga/Documents/airfoils/naca4412.dat 2>/dev/null || true
fi

echo "Initial results file count: $INITIAL_RESULTS"

# Launch QBlade
echo "Launching QBlade..."
source /workspace/scripts/task_utils.sh
launch_qblade

# Wait for QBlade to start
sleep 8

echo "=== Task setup complete ==="
