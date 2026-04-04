#!/bin/bash
echo "=== Setting up assess_overbank_flood_depth task ==="

source /workspace/scripts/task_utils.sh

# 1. Restore clean Muncie project
restore_muncie_project

# 2. Ensure simulation results exist (Run if needed)
run_simulation_if_needed

# 3. Create output directory
mkdir -p /home/ga/Documents/hec_ras_results
# Clean any previous run artifacts
rm -f /home/ga/Documents/hec_ras_results/overbank_depth_assessment.csv
rm -f /home/ga/Documents/hec_ras_results/assessment_summary.txt
chown -R ga:ga /home/ga/Documents/hec_ras_results

# 4. Record task start time (for anti-gaming)
date +%s > /tmp/task_start_time.txt

# 5. Open terminal in project directory
echo "Opening terminal in Muncie project directory..."
launch_terminal "$MUNCIE_DIR"

# 6. Type 'ls' to show files to the agent
type_in_terminal "ls -lh Muncie.p04.hdf"

# 7. Take initial screenshot
sleep 2
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="