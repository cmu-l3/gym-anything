#!/bin/bash
echo "=== Setting up plot_flood_hydrograph task ==="

source /workspace/scripts/task_utils.sh

# 1. Restore clean Muncie project (with pre-computed results)
restore_muncie_project

# 2. Run simulation to produce results (if not already present)
run_simulation_if_needed

# 3. Clean previous plot outputs
rm -f /home/ga/Documents/hec_ras_results/flood_hydrograph.png
mkdir -p /home/ga/Documents/hec_ras_results
chown -R ga:ga /home/ga/Documents/hec_ras_results

# 4. Ensure analysis scripts are available
mkdir -p /home/ga/Documents/analysis_scripts
cp /workspace/data/analysis_scripts/plot_flood_hydrograph.py /home/ga/Documents/analysis_scripts/ 2>/dev/null || true
chmod +x /home/ga/Documents/analysis_scripts/plot_flood_hydrograph.py 2>/dev/null || true
chown -R ga:ga /home/ga/Documents/analysis_scripts

# Record start time
date +%s > /tmp/task_start_time.txt

# 5. Open a terminal in the Muncie directory
echo "Opening terminal in project directory..."
launch_terminal "$MUNCIE_DIR"

# 6. Show simulation results and available plotting scripts in the terminal
type_in_terminal "echo '=== Simulation Results ===' && ls -lh Muncie.p04*.hdf && echo '' && echo '=== Plotting Scripts ===' && ls ~/Documents/analysis_scripts/plot*.py && echo '' && echo '=== Output Directory ===' && ls ~/Documents/hec_ras_results/ 2>/dev/null || echo '(empty - no plots yet)'"

# 7. Take initial screenshot
sleep 2
take_screenshot /tmp/task_start_screenshot.png

echo "=== Task setup complete ==="
echo "Terminal is open in the Muncie project directory."
echo "Task: Run the plotting script to create a flood hydrograph."
