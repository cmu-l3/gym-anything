#!/bin/bash
echo "=== Setting up analyze_reach_geometry task ==="

source /workspace/scripts/task_utils.sh

# 1. Restore clean Muncie project
restore_muncie_project

# 2. Ensure user directories exist and are clean
mkdir -p /home/ga/Documents/hec_ras_results
rm -f /home/ga/Documents/hec_ras_results/reach_stats.csv
rm -f /home/ga/Documents/hec_ras_results/geometry_analysis.py
chown -R ga:ga /home/ga/Documents/hec_ras_results

# 3. Pre-generate HDF5 file so data is available (lowers barrier to entry, but agent still needs to find it)
# We run RasGeomPreprocess to ensure Muncie.p04.tmp.hdf exists
if [ -f "$MUNCIE_DIR/Muncie.x04" ]; then
    echo "Running geometry preprocessor to ensure HDF5 exists..."
    cd "$MUNCIE_DIR"
    # Create a dummy run file if needed or just run preprocessor
    # RasGeomPreprocess usually takes Inputfile OutputHDF
    su - ga -c "source /etc/profile.d/hec-ras.sh; cd '$MUNCIE_DIR'; RasGeomPreprocess Muncie.p04.tmp.hdf x04" > /dev/null 2>&1 || true
fi

# 4. Record task start time
date +%s > /tmp/task_start_time.txt

# 5. Launch terminal in project directory
echo "Opening terminal..."
launch_terminal "$MUNCIE_DIR"

# 6. Take initial screenshot
sleep 2
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="