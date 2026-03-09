#!/bin/bash
set -e
echo "=== Setting up identify_hydraulic_bottleneck task ==="

source /workspace/scripts/task_utils.sh

# 1. Restore clean Muncie project
restore_muncie_project

# 2. Run simulation to ensure results exist (Critical for this task)
# We need valid results in the HDF file for the agent to analyze
echo "Running simulation to generate results..."
run_simulation_if_needed

# 3. Prepare output directory and clean previous results
mkdir -p /home/ga/Documents/hec_ras_results
rm -f /home/ga/Documents/hec_ras_results/bottleneck_report.txt
chown -R ga:ga /home/ga/Documents/hec_ras_results

# 4. Generate Ground Truth (Hidden from Agent)
# We calculate the correct answer now using the known-good results
# This ensures verification is based on the exact file state the agent sees
echo "Generating ground truth..."
cat << 'PY_EOF' > /tmp/generate_ground_truth.py
import h5py
import numpy as np
import json
import os

try:
    # Path to HDF file
    hdf_path = "/home/ga/Documents/hec_ras_projects/Muncie/Muncie.p04.hdf"
    
    with h5py.File(hdf_path, 'r') as f:
        # 1. Get River Stations (Cross Section Identifiers)
        # HEC-RAS stores these as byte strings
        rs_path = "Geometry/Cross Sections/Attributes"
        river_stations = [x.decode('utf-8').strip() for x in f[rs_path]['River Station']]
        
        # 2. Get Reach Lengths (Channel)
        # Usually stored in 'Reach Lengths' dataset: [LOB, Channel, ROB]
        # We want Channel (index 1)
        # Note: Reach Length at index i is usually distance from i to i-1 (downstream)
        # BUT check HEC-RAS convention: Reach Length stored at XS is distance *to the next downstream XS*
        reach_lengths = f[rs_path]['Reach Lengths'][:, 1] # Column 1 is Channel
        
        # 3. Get Max EGL
        # Path: Results/Unsteady/Output/Output Blocks/Base Output/Unsteady Time Series/Cross Sections/Energy Grade
        # Shape: (Time, XS) -> We need max over time
        egl_data = f["Results/Unsteady/Output/Output Blocks/Base Output/Unsteady Time Series/Cross Sections/Energy Grade"][:]
        max_egl = np.max(egl_data, axis=0)
        
    # Calculate Slopes
    # HEC-RAS arrays are typically ordered Upstream -> Downstream (index 0 is upstream)
    # But let's verify logic:
    # Slope[i] = (EGL[i] - EGL[i+1]) / Length[i]
    # Length[i] is distance from i to i+1
    
    max_slope = -1.0
    crit_idx = -1
    
    # Iterate through all segments (N-1 segments for N cross sections)
    for i in range(len(river_stations) - 1):
        length = reach_lengths[i]
        
        # Skip segments with zero length (e.g. bridges sometimes) or tiny lengths
        if length < 0.1:
            continue
            
        head_loss = max_egl[i] - max_egl[i+1]
        slope = head_loss / length
        
        if slope > max_slope:
            max_slope = slope
            crit_idx = i

    ground_truth = {
        "upstream_station": river_stations[crit_idx],
        "downstream_station": river_stations[crit_idx+1],
        "reach_length": float(reach_lengths[crit_idx]),
        "head_loss": float(max_egl[crit_idx] - max_egl[crit_idx+1]),
        "max_slope": float(max_slope),
        "success": True
    }

    with open('/tmp/ground_truth.json', 'w') as f:
        json.dump(ground_truth, f, indent=2)
        
except Exception as e:
    error_data = {"success": False, "error": str(e)}
    with open('/tmp/ground_truth.json', 'w') as f:
        json.dump(error_data, f)
PY_EOF

# Run ground truth generation with python3
# Ensure h5py is installed (it is in the env definition)
python3 /tmp/generate_ground_truth.py
chmod 644 /tmp/ground_truth.json

# 5. Launch Terminal
launch_terminal "$MUNCIE_DIR"

# 6. Initial Screenshot
sleep 2
take_screenshot /tmp/task_initial.png

# Record start time
date +%s > /tmp/task_start_time.txt

echo "=== Setup complete ==="