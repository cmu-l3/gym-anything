#!/bin/bash
set -e
echo "=== Setting up generate_cross_section_summary task ==="

source /workspace/scripts/task_utils.sh

# 1. Restore clean Muncie project
restore_muncie_project

# 2. Ensure simulation results exist (run if needed)
# The task relies on Muncie.p04.hdf being present and valid
if [ ! -f "$MUNCIE_DIR/Muncie.p04.hdf" ]; then
    echo "Running HEC-RAS simulation to generate results..."
    # Using the helper from task_utils.sh, but forcing the specific filename expected
    run_simulation_if_needed
    
    # Ensure the naming matches what the task description promises
    if [ -f "$MUNCIE_DIR/Muncie.p04.tmp.hdf" ] && [ ! -f "$MUNCIE_DIR/Muncie.p04.hdf" ]; then
        cp "$MUNCIE_DIR/Muncie.p04.tmp.hdf" "$MUNCIE_DIR/Muncie.p04.hdf"
    fi
fi

# Double check existence
if [ ! -f "$MUNCIE_DIR/Muncie.p04.hdf" ]; then
    echo "ERROR: Simulation results Muncie.p04.hdf could not be generated."
    # Try one last fallback - copy any HDF if available
    ANY_HDF=$(ls "$MUNCIE_DIR"/*.p*.hdf 2>/dev/null | head -1)
    if [ -n "$ANY_HDF" ]; then
        cp "$ANY_HDF" "$MUNCIE_DIR/Muncie.p04.hdf"
    else
        # Critical failure if no results
        echo "Creating dummy HDF for structure (Task will fail verification but env won't crash)"
        touch "$MUNCIE_DIR/Muncie.p04.hdf"
    fi
fi

# 3. Clean previous results
rm -f /home/ga/Documents/hec_ras_results/cross_section_summary.csv
mkdir -p /home/ga/Documents/hec_ras_results
chown -R ga:ga /home/ga/Documents/hec_ras_results

# 4. Record Task Start Time
date +%s > /tmp/task_start_time.txt

# 5. Open Terminal in Project Directory
echo "Opening terminal..."
launch_terminal "$MUNCIE_DIR"

# 6. Type 'ls' to show the user the files
type_in_terminal "ls -lh Muncie.p04.hdf"

# 7. Take initial screenshot
sleep 2
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="