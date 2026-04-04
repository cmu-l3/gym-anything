#!/bin/bash
set -e
echo "=== Setting up flood wave travel time task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# 1. Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# 2. Clean any previous results
rm -f /home/ga/Documents/hec_ras_results/flood_wave_travel_time.txt
rm -f /home/ga/Documents/hec_ras_results/*.txt 2>/dev/null || true

# 3. Restore Muncie project to clean state
restore_muncie_project

# 4. Ensure simulation has been run (CRITICAL step)
echo "--- Ensuring simulation results are available ---"
run_simulation_if_needed

# Verify the HDF results file exists
HDF_FILE=""
for f in /home/ga/Documents/hec_ras_projects/Muncie/Muncie.p04.hdf \
         /home/ga/Documents/hec_ras_projects/Muncie/Muncie.p04.tmp.hdf; do
    if [ -f "$f" ]; then
        HDF_FILE="$f"
        echo "Found HDF results: $f ($(du -h "$f" | cut -f1))"
        break
    fi
done

if [ -z "$HDF_FILE" ]; then
    echo "WARNING: No HDF results file found. Attempting forced simulation..."
    cd /home/ga/Documents/hec_ras_projects/Muncie
    source /etc/profile.d/hec-ras.sh 2>/dev/null || true
    su - ga -c "source /etc/profile.d/hec-ras.sh; cd /home/ga/Documents/hec_ras_projects/Muncie; RasUnsteady Muncie.p04.tmp.hdf x04" 2>&1 | tail -10
fi

# 5. Ensure results directory exists
mkdir -p /home/ga/Documents/hec_ras_results
chown -R ga:ga /home/ga/Documents/hec_ras_results

# 6. Launch terminal in the project directory (Initial State)
echo "--- Launching terminal ---"
launch_terminal /home/ga/Documents/hec_ras_projects/Muncie

sleep 5

# 7. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Flood wave travel time task setup complete ==="