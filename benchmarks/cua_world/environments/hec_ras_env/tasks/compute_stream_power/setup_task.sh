#!/bin/bash
set -e
echo "=== Setting up compute_stream_power task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

HECRAS_HOME="/opt/hec-ras"
MUNCIE_DIR="/home/ga/Documents/hec_ras_projects/Muncie"
RESULTS_DIR="/home/ga/Documents/hec_ras_results"

# 1. Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# 2. Setup Directories
mkdir -p "$MUNCIE_DIR"
mkdir -p "$RESULTS_DIR"
chown -R ga:ga "$RESULTS_DIR"

# 3. Restore Muncie project from clean copy
echo "--- Restoring Muncie project ---"
if [ -d "$HECRAS_HOME/examples/Muncie" ]; then
    rm -rf "$MUNCIE_DIR"/*
    cp -r "$HECRAS_HOME/examples/Muncie"/* "$MUNCIE_DIR/"
    # Copy source files (inputs) if separated
    if [ -d "$MUNCIE_DIR/wrk_source" ]; then
        cp "$MUNCIE_DIR/wrk_source"/* "$MUNCIE_DIR/" 2>/dev/null || true
    fi
    chown -R ga:ga "$MUNCIE_DIR"
else
    echo "ERROR: Muncie example not found"
    exit 1
fi

# 4. Pre-run the simulation
# The task focuses on analysis, not running the sim, so we ensure results exist.
# However, we leave the option for the agent to re-run it if they want.
echo "--- Pre-computing simulation results ---"
HDF_FILE="$MUNCIE_DIR/Muncie.p04.tmp.hdf"

# Source environment variables for HEC-RAS
source /etc/profile.d/hec-ras.sh

# Run RasUnsteady
cd "$MUNCIE_DIR"
if [ ! -f "$HDF_FILE" ]; then
    echo "Running RasUnsteady..."
    su - ga -c "source /etc/profile.d/hec-ras.sh; cd '$MUNCIE_DIR'; RasUnsteady Muncie.p04.tmp.hdf x04" > /tmp/sim_log.txt 2>&1 || true
fi

if [ -f "$HDF_FILE" ]; then
    echo "Simulation results confirmed at $HDF_FILE"
else
    echo "WARNING: Simulation failed to generate HDF file. Agent will need to run it."
fi

# 5. Clean up any previous attempts in results dir
rm -f "$RESULTS_DIR/stream_power_profile.csv"
rm -f "$RESULTS_DIR/stream_power_summary.txt"
rm -f "$RESULTS_DIR/compute_stream_power.py"

# 6. Open Terminal in Project Directory
launch_terminal "$MUNCIE_DIR"

# 7. Take initial screenshot
sleep 2
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="