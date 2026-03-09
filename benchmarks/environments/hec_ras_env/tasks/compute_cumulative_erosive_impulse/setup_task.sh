#!/bin/bash
set -e
echo "=== Setting up compute_cumulative_erosive_impulse task ==="

source /workspace/scripts/task_utils.sh

# 1. Restore clean Muncie project
restore_muncie_project

# 2. Pre-run the simulation to ensure consistent starting state (optional, but reduces timeout risk)
# The task asks the agent to check, so we'll run it now so it exists, 
# but the agent still needs to handle the file.
run_simulation_if_needed

# 3. Create output directory and ensure it's empty of target files
mkdir -p /home/ga/Documents/hec_ras_results
rm -f /home/ga/Documents/hec_ras_results/erosion_impulse.csv
rm -f /home/ga/Documents/hec_ras_results/erosion_summary.txt
rm -f /home/ga/Documents/hec_ras_results/critical_shear_plot.png
chown -R ga:ga /home/ga/Documents/hec_ras_results

# 4. Record Task Start Time (Anti-gaming)
date +%s > /tmp/task_start_time.txt

# 5. Open Terminal in Muncie Project Directory
echo "Launching terminal..."
launch_terminal "$MUNCIE_DIR"

# 6. Type initial check command to show user where they are
type_in_terminal "ls -lh Muncie.p04.hdf"

# 7. Take initial screenshot
sleep 2
take_screenshot /tmp/task_start_screenshot.png

echo "=== Task setup complete ==="