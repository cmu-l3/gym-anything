#!/bin/bash
echo "=== Setting up benchmark_simulation_performance task ==="

source /workspace/scripts/task_utils.sh

# 1. Restore clean Muncie project
restore_muncie_project

# 2. Prepare results directory and clean previous artifacts
mkdir -p /home/ga/Documents/hec_ras_results
rm -f /home/ga/Documents/hec_ras_results/simulation.log
rm -f /home/ga/Documents/hec_ras_results/benchmark_report.csv
chown -R ga:ga /home/ga/Documents/hec_ras_results

# 3. Ensure RasUnsteady is available (sanity check)
if ! command -v RasUnsteady &> /dev/null; then
    echo "WARNING: RasUnsteady not found in PATH. Sourcing profile..."
    source /etc/profile.d/hec-ras.sh
fi

# 4. Record task start time (for anti-gaming)
date +%s > /tmp/task_start_time.txt

# 5. Open terminal in the project directory
echo "Opening terminal in Muncie project directory..."
launch_terminal "$MUNCIE_DIR"

# 6. Display available files to hint at the starting state
type_in_terminal "ls -lh Muncie.p04.tmp.hdf"

# 7. Take initial screenshot
sleep 2
take_screenshot /tmp/task_start_screenshot.png

echo "=== Task setup complete ==="
echo "Terminal open in $MUNCIE_DIR"
echo "Ready to benchmark simulation."