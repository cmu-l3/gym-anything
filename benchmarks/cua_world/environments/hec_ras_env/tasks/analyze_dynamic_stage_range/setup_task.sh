#!/bin/bash
echo "=== Setting up analyze_dynamic_stage_range task ==="

source /workspace/scripts/task_utils.sh

# 1. Restore Muncie project to clean state
restore_muncie_project

# 2. Ensure simulation results exist
# The task requires analyzing results, so we must ensure they are present.
if [ ! -f "$MUNCIE_DIR/Muncie.p04.hdf" ]; then
    echo "Running HEC-RAS simulation to generate results..."
    # Copy source files if needed (usually done by restore_muncie_project)
    
    # Run Unsteady simulation
    # Note: RasUnsteady requires the geometry preprocessor to have run, 
    # but the example project usually comes with geometry ready.
    # We run the geometry preprocessor just in case.
    su - ga -c "source /etc/profile.d/hec-ras.sh; cd '$MUNCIE_DIR'; RasGeomPreprocess Muncie.p04.tmp.hdf x04" > /dev/null 2>&1
    
    # Run Unsteady
    su - ga -c "source /etc/profile.d/hec-ras.sh; cd '$MUNCIE_DIR'; RasUnsteady Muncie.p04.tmp.hdf x04" > /dev/null 2>&1
    
    # Rename/Finalize output
    if [ -f "$MUNCIE_DIR/Muncie.p04.tmp.hdf" ]; then
        cp "$MUNCIE_DIR/Muncie.p04.tmp.hdf" "$MUNCIE_DIR/Muncie.p04.hdf"
        chown ga:ga "$MUNCIE_DIR/Muncie.p04.hdf"
    fi
fi

if [ ! -f "$MUNCIE_DIR/Muncie.p04.hdf" ]; then
    echo "ERROR: Failed to generate HEC-RAS results file."
    exit 1
fi

# 3. Clean output directory
rm -rf "$RESULTS_DIR"
mkdir -p "$RESULTS_DIR"
chown ga:ga "$RESULTS_DIR"

# 4. Record Task Start Time
date +%s > /tmp/task_start_time.txt

# 5. Launch Terminal in Project Directory
launch_terminal "$MUNCIE_DIR"

# 6. Capture Initial Screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="