#!/bin/bash
echo "=== Setting up analyze_peak_wse task ==="

source /workspace/scripts/task_utils.sh

# 1. Restore clean Muncie project (with pre-computed results)
restore_muncie_project

# 2. Run simulation to produce results (if not already present)
run_simulation_if_needed

# 3. Clean previous results
rm -f /home/ga/Documents/hec_ras_results/peak_wse_results.csv
mkdir -p /home/ga/Documents/hec_ras_results
chown -R ga:ga /home/ga/Documents/hec_ras_results

# 4. Ensure analysis scripts are available
mkdir -p /home/ga/Documents/analysis_scripts
cp /workspace/data/analysis_scripts/analyze_peak_wse.py /home/ga/Documents/analysis_scripts/ 2>/dev/null || true
chmod +x /home/ga/Documents/analysis_scripts/analyze_peak_wse.py 2>/dev/null || true
chown -R ga:ga /home/ga/Documents/analysis_scripts

# Record start time
date +%s > /tmp/task_start_time.txt

# 5. Open a terminal in the Muncie directory
echo "Opening terminal in project directory..."
launch_terminal "$MUNCIE_DIR"

# 6. Show simulation results and available analysis scripts in the terminal
type_in_terminal "echo '=== Simulation Results ===' && ls -lh Muncie.p04*.hdf && echo '' && echo '=== Analysis Scripts ===' && ls ~/Documents/analysis_scripts/"

# 7. Take initial screenshot
sleep 2
take_screenshot /tmp/task_start_screenshot.png

echo "=== Task setup complete ==="
echo "Terminal is open in the Muncie project directory."
echo "Task: Run the analysis script to extract peak water surface elevation."
