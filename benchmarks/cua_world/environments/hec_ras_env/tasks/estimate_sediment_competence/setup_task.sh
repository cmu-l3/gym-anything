#!/bin/bash
echo "=== Setting up estimate_sediment_competence task ==="

source /workspace/scripts/task_utils.sh

# 1. Restore Muncie project to clean state
restore_muncie_project

# 2. Ensure simulation results exist (Run simulation if needed)
# The task requires analyzing results, so we ensure they are present.
run_simulation_if_needed

# 3. Clean up previous results directory
rm -rf /home/ga/Documents/hec_ras_results
mkdir -p /home/ga/Documents/hec_ras_results
chown -R ga:ga /home/ga/Documents/hec_ras_results

# 4. Create analysis scripts directory (empty, ready for user)
mkdir -p /home/ga/Documents/analysis_scripts
chown -R ga:ga /home/ga/Documents/analysis_scripts

# 5. Record task start time
date +%s > /tmp/task_start_time.txt

# 6. Open Terminal in Project Directory
echo "Opening terminal..."
launch_terminal "$MUNCIE_DIR"

# 7. Type `ls` to show files to the agent
type_in_terminal "ls -lh Muncie.p04.hdf"

# 8. Take initial screenshot
sleep 2
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="