#!/bin/bash
echo "=== Setting up analyze_geometry_containment task ==="

source /workspace/scripts/task_utils.sh

# 1. Restore Muncie project to clean state
restore_muncie_project

# 2. Pre-run simulation to ensure results exist (agent should focus on analysis)
# If the file doesn't exist or is old, run the simulation
if [ ! -f "$MUNCIE_DIR/Muncie.p04.hdf" ]; then
    echo "Running HEC-RAS simulation to generate base results..."
    run_simulation_if_needed
fi

# 3. Clean output directory to ensure fresh results
RESULTS_DIR="/home/ga/Documents/hec_ras_results"
rm -rf "$RESULTS_DIR"
mkdir -p "$RESULTS_DIR"
chown ga:ga "$RESULTS_DIR"

# 4. Copy analysis scripts (helper scripts) if needed, but we want the agent to write their own or use helpers
# We'll ensure the general scripts folder is populated
mkdir -p /home/ga/Documents/analysis_scripts
cp /workspace/data/analysis_scripts/*.py /home/ga/Documents/analysis_scripts/ 2>/dev/null || true
chown -R ga:ga /home/ga/Documents/analysis_scripts

# 5. Launch Terminal in Project Directory
echo "Opening terminal..."
launch_terminal "$MUNCIE_DIR"

# 6. Type initial ls command to orient the agent
type_in_terminal "ls -lh *.hdf"

# 7. Take initial screenshot
take_screenshot /tmp/task_start.png

# 8. Record Start Time
date +%s > /tmp/task_start_time.txt

echo "=== Setup Complete ==="