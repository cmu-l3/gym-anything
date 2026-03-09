#!/bin/bash
echo "=== Setting up visualize_critical_section task ==="

source /workspace/scripts/task_utils.sh

# 1. Restore clean Muncie project
restore_muncie_project

# 2. Ensure simulation results exist (run if needed)
# The task relies on analyzing existing results
run_simulation_if_needed

# Ensure the HDF file is where we expect it for the description
if [ -f "$MUNCIE_DIR/Muncie.p04.hdf" ] && [ ! -f "$MUNCIE_DIR/Muncie.p04.tmp.hdf" ]; then
    cp "$MUNCIE_DIR/Muncie.p04.hdf" "$MUNCIE_DIR/Muncie.p04.tmp.hdf"
fi

# 3. Clean up previous results
RESULTS_DIR="/home/ga/Documents/hec_ras_results"
mkdir -p "$RESULTS_DIR"
rm -f "$RESULTS_DIR/critical_section_plot.png"
rm -f "$RESULTS_DIR/critical_section_info.txt"
chown -R ga:ga "$RESULTS_DIR"

# 4. Create a helpful starting script template (optional, but helpful for 'medium' difficulty)
# We won't give the solution, but we'll ensure the environment is ready for Python scripting
cat > /home/ga/Documents/analysis_scripts/skeleton_script.py << 'EOF'
import h5py
import numpy as np
import matplotlib.pyplot as plt

# HEC-RAS HDF5 file path
hdf_file = "/home/ga/Documents/hec_ras_projects/Muncie/Muncie.p04.tmp.hdf"

print(f"Opening {hdf_file}...")
# TODO: Open file, iterate cross sections, find max depth, plot results
EOF
chown ga:ga /home/ga/Documents/analysis_scripts/skeleton_script.py

# 5. Open terminal in project directory
launch_terminal "$MUNCIE_DIR"

# 6. Record task start time
date +%s > /tmp/task_start_time.txt

# 7. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="