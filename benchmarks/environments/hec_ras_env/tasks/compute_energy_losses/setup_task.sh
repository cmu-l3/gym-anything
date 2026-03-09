#!/bin/bash
echo "=== Setting up compute_energy_losses task ==="

source /workspace/scripts/task_utils.sh

# 1. Restore clean Muncie project
restore_muncie_project

# 2. Ensure simulation results exist (Run simulation if needed)
# This is critical because the task requires analyzing the HDF output
run_simulation_if_needed

# 3. Clean up any previous results or scripts from prior runs
rm -f /home/ga/Documents/hec_ras_results/energy_loss_analysis.csv
rm -f /home/ga/Documents/hec_ras_results/energy_loss_summary.txt
rm -f /home/ga/Documents/hec_ras_results/energy_loss_analysis.py
rm -f /home/ga/Documents/hec_ras_results/ground_truth.json

# Ensure results directory exists
mkdir -p /home/ga/Documents/hec_ras_results
chown -R ga:ga /home/ga/Documents/hec_ras_results

# 4. Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# 5. Open a terminal in the project directory
echo "Opening terminal in project directory..."
launch_terminal "$MUNCIE_DIR"

# 6. Pre-type a helpful listing command to orient the agent
type_in_terminal "ls -lh Muncie.p04.hdf"

# 7. Take initial screenshot
sleep 2
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="