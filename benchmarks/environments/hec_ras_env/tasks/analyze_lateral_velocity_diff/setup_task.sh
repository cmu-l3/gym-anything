#!/bin/bash
echo "=== Setting up analyze_lateral_velocity_diff task ==="

source /workspace/scripts/task_utils.sh

# 1. Restore clean Muncie project
restore_muncie_project

# 2. Run simulation to ensure results exist (Deterministic Ground Truth)
# We do this so the verifier can calculate the EXACT expected answer from the same file the agent uses.
echo "Running simulation to prepare results..."
if [ -f "$MUNCIE_DIR/Muncie.p04.tmp.hdf" ]; then
    rm "$MUNCIE_DIR/Muncie.p04.tmp.hdf"
fi

# Run RasUnsteady
su - ga -c "source /etc/profile.d/hec-ras.sh; cd '$MUNCIE_DIR'; RasUnsteady Muncie.p04.tmp.hdf x04" > /tmp/sim_run.log 2>&1

# Rename output to standard HDF name
if [ -f "$MUNCIE_DIR/Muncie.p04.tmp.hdf" ]; then
    mv "$MUNCIE_DIR/Muncie.p04.tmp.hdf" "$MUNCIE_DIR/Muncie.p04.hdf"
    chown ga:ga "$MUNCIE_DIR/Muncie.p04.hdf"
    echo "Simulation complete. Results available at Muncie.p04.hdf"
else
    echo "WARNING: Simulation failed. Agent may need to run it."
    # We leave it failed - the agent's first step is to check/run.
fi

# 3. Setup user directories
mkdir -p /home/ga/Documents/hec_ras_results
chown -R ga:ga /home/ga/Documents/hec_ras_results

# 4. Open terminal in project directory
launch_terminal "$MUNCIE_DIR"

# 5. Record start time
date +%s > /tmp/task_start_time.txt

# 6. Take initial screenshot
sleep 2
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="