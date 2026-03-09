#!/bin/bash
set -e
echo "=== Setting up extract_velocity_distribution task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Restore clean Muncie project
restore_muncie_project

# 2. Run simulation if results don't exist
# We need the .p04.hdf file to be present for the agent to analyze
run_simulation_if_needed

# Verify HDF results file exists
HDF_FILE=""
for f in "$MUNCIE_DIR/Muncie.p04.tmp.hdf" "$MUNCIE_DIR/Muncie.p04.hdf"; do
    if [ -f "$f" ]; then
        HDF_FILE="$f"
        echo "Found results HDF: $f"
        break
    fi
done

if [ -z "$HDF_FILE" ]; then
    echo "ERROR: No HDF results file found. Attempting forced simulation..."
    cd "$MUNCIE_DIR"
    source /etc/profile.d/hec-ras.sh
    su - ga -c "source /etc/profile.d/hec-ras.sh; cd '$MUNCIE_DIR'; RasUnsteady Muncie.p04.tmp.hdf x04"
    if [ -f "$MUNCIE_DIR/Muncie.p04.tmp.hdf" ]; then
        cp "$MUNCIE_DIR/Muncie.p04.tmp.hdf" "$MUNCIE_DIR/Muncie.p04.hdf"
    fi
fi

# 3. Clean output directory
rm -rf "$RESULTS_DIR"
mkdir -p "$RESULTS_DIR"
chown -R ga:ga "$RESULTS_DIR"

# 4. Launch terminal in Muncie directory
launch_terminal "$MUNCIE_DIR"

# 5. Type a hint command to show files
type_in_terminal "ls -lh *.hdf"

# 6. Take initial screenshot
sleep 2
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="