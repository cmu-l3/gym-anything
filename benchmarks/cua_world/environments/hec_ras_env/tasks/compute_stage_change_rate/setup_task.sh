#!/bin/bash
set -e
echo "=== Setting up compute_stage_change_rate task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# 1. Record task start time (for anti-gaming)
date +%s > /tmp/task_start_time.txt

# 2. Restore clean Muncie project
echo "Restoring Muncie project..."
restore_muncie_project

# 3. Ensure results directory exists and is clean
mkdir -p /home/ga/Documents/hec_ras_results
rm -f /home/ga/Documents/hec_ras_results/stage_change_rates.csv
rm -f /home/ga/Documents/hec_ras_results/stage_change_summary.txt
chown -R ga:ga /home/ga/Documents/hec_ras_results

# 4. Pre-run the simulation to ensure HDF results exist
# This allows the agent to focus on the analysis, but they should still check.
echo "Pre-running HEC-RAS simulation..."
if [ ! -f "$MUNCIE_DIR/Muncie.p04.hdf" ]; then
    cd "$MUNCIE_DIR"
    # Run in background to not block too long, but wait for it
    su - ga -c "source /etc/profile.d/hec-ras.sh; cd '$MUNCIE_DIR'; RasUnsteady Muncie.p04.tmp.hdf x04" > /tmp/sim_run.log 2>&1
    
    # Rename temp output to final if needed
    if [ -f "Muncie.p04.tmp.hdf" ] && [ ! -f "Muncie.p04.hdf" ]; then
        cp Muncie.p04.tmp.hdf Muncie.p04.hdf
    fi
    chown ga:ga *.hdf 2>/dev/null || true
fi

# 5. Open terminal in project directory
echo "Opening terminal..."
launch_terminal "$MUNCIE_DIR"

# 6. Type 'ls' to show files to agent
type_in_terminal "ls -lh"

# 7. Take initial screenshot
sleep 2
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="