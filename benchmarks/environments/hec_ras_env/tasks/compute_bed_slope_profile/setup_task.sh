#!/bin/bash
echo "=== Setting up compute_bed_slope_profile task ==="

source /workspace/scripts/task_utils.sh

# 1. Restore clean Muncie project
restore_muncie_project

# 2. Ensure we have the HDF5 file
# Run the geometry preprocessor or unsteady run setup to generate the .tmp.hdf if it doesn't exist
if [ ! -f "$MUNCIE_DIR/Muncie.p04.tmp.hdf" ]; then
    echo "Generating HEC-RAS HDF5 geometry data..."
    # We can try running RasGeomPreprocess or just relying on the bundled files
    # Checking if the environment setup copied wrk_source correctly
    if [ -f "$MUNCIE_DIR/Muncie.x04" ]; then
        cd "$MUNCIE_DIR"
        # RasGeomPreprocess usually takes input and output arguments
        # Attempt to generate if missing, but usually p04.tmp.hdf is part of the test dataset
        # If missing, we might need to rely on what's there. 
        # For this task, we assume the environment provides it as stated in the env description.
        echo "Checking for HDF file..."
    fi
fi

# Verify the target file exists
if [ ! -f "$MUNCIE_DIR/Muncie.p04.tmp.hdf" ]; then
    echo "WARNING: Muncie.p04.tmp.hdf not found. Listing directory:"
    ls -la "$MUNCIE_DIR"
    # Try to find any HDF file
    HDF_FILE=$(find "$MUNCIE_DIR" -name "*.hdf" | head -1)
    if [ -n "$HDF_FILE" ]; then
        echo "Found alternate HDF: $HDF_FILE"
        # Symlink it to expected name if needed, or just let the agent explore
    fi
fi

# 3. Create output directory
mkdir -p /home/ga/Documents/hec_ras_results
chown -R ga:ga /home/ga/Documents/hec_ras_results

# 4. Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# 5. Open terminal in project directory
echo "Opening terminal..."
launch_terminal "$MUNCIE_DIR"

# 6. Pre-type a hint command (ls to show files)
type_in_terminal "ls -lh *.hdf"

# 7. Take initial screenshot
sleep 2
take_screenshot /tmp/task_start_screenshot.png

echo "=== Task setup complete ==="