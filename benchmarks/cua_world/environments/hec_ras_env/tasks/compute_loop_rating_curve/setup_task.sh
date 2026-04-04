#!/bin/bash
echo "=== Setting up compute_loop_rating_curve task ==="

source /workspace/scripts/task_utils.sh

# 1. Restore clean Muncie project
restore_muncie_project

# 2. Ensure simulation results exist (Muncie.p04.tmp.hdf)
# The task description relies on this file.
if [ ! -f "$MUNCIE_DIR/Muncie.p04.tmp.hdf" ]; then
    echo "Running simulation to generate HDF results..."
    # Run RasUnsteady (using utils or direct call)
    run_simulation_if_needed
    # The utils script usually names it Muncie.p04.hdf, let's copy to .tmp.hdf to match description if needed
    if [ -f "$MUNCIE_DIR/Muncie.p04.hdf" ] && [ ! -f "$MUNCIE_DIR/Muncie.p04.tmp.hdf" ]; then
        cp "$MUNCIE_DIR/Muncie.p04.hdf" "$MUNCIE_DIR/Muncie.p04.tmp.hdf"
    fi
fi

# Ensure the file exists now
if [ ! -f "$MUNCIE_DIR/Muncie.p04.tmp.hdf" ]; then
    echo "ERROR: Simulation failed to produce results."
    exit 1
fi

# 3. Clean up previous results
mkdir -p "$RESULTS_DIR"
rm -f "$RESULTS_DIR/loop_rating_summary.csv"
rm -f "$RESULTS_DIR/loop_rating_curves.png"

# 4. Open terminal in project directory
echo "Opening terminal..."
launch_terminal "$MUNCIE_DIR"

# 5. Type 'ls' to show the user the files
type_in_terminal "ls -lh Muncie.p04.tmp.hdf"

# 6. Record start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# 7. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="