#!/bin/bash
set -e
echo "=== Setting up task: analyze_2d_mesh_properties ==="

source /workspace/scripts/task_utils.sh

# 1. Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# 2. Restore clean Muncie project
restore_muncie_project

# 3. Ensure simulation results exist (to populate the HDF file with geometry/results)
# The HDF file Muncie.p04.tmp.hdf is generated during simulation
run_simulation_if_needed

# 4. Clean up any previous results or artifacts
rm -f /home/ga/Documents/hec_ras_results/mesh_analysis_report.txt
rm -f /home/ga/Documents/hec_ras_results/mesh_cell_data.csv
mkdir -p /home/ga/Documents/hec_ras_results
chown -R ga:ga /home/ga/Documents/hec_ras_results

# 5. Verify the HDF file exists and has content
HDF_FILE="/home/ga/Documents/hec_ras_projects/Muncie/Muncie.p04.tmp.hdf"
if [ -f "$HDF_FILE" ]; then
    FILE_SIZE=$(stat -c%s "$HDF_FILE")
    echo "Plan HDF file found: $HDF_FILE ($FILE_SIZE bytes)"
else
    echo "WARNING: Plan HDF file not found at $HDF_FILE"
    # List all HDF files to help debug if needed
    find /home/ga/Documents/hec_ras_projects/Muncie -name "*.hdf"
fi

# 6. Launch terminal in the project directory
echo "Opening terminal in project directory..."
launch_terminal "/home/ga/Documents/hec_ras_projects/Muncie"

# 7. Take initial screenshot
sleep 2
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="