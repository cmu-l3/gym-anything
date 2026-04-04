#!/bin/bash
set -e
echo "=== Setting up Task: Validate Model Calibration ==="

# Source HEC-RAS environment settings
source /etc/profile.d/hec-ras.sh 2>/dev/null || true
export PYTHONPATH=$PYTHONPATH:/opt/hec-ras/analysis_scripts

# 1. Setup Directories
mkdir -p /home/ga/Documents/field_data
mkdir -p /home/ga/Documents/hec_ras_results
mkdir -p /var/lib/hec_ras
chown -R ga:ga /home/ga/Documents/field_data
chown -R ga:ga /home/ga/Documents/hec_ras_results

# 2. Prepare Muncie Project
echo "Restoring Muncie project..."
MUNCIE_DIR="/home/ga/Documents/hec_ras_projects/Muncie"
mkdir -p "$MUNCIE_DIR"
if [ -d "/opt/hec-ras/benchmarks/cua_world/environments/Muncie" ]; then
    cp -r /opt/hec-ras/benchmarks/cua_world/environments/Muncie/* "$MUNCIE_DIR/"
    # Ensure input files (wrk_source) are in place if they exist
    if [ -d "$MUNCIE_DIR/wrk_source" ]; then
        cp "$MUNCIE_DIR/wrk_source"/* "$MUNCIE_DIR/" 2>/dev/null || true
    fi
fi
chown -R ga:ga "$MUNCIE_DIR"

# 3. Ensure Simulation Results Exist (Ground Truth Generation)
# We MUST run the simulation now to guarantee the "Observed" data we generate
# matches the physics of the installed HEC-RAS engine.
echo "Running base simulation for ground truth generation..."
cd "$MUNCIE_DIR"

# Check if we need to run RasUnsteady
# Note: In RAS 6.x Linux, the plan file naming can be tricky. We try running the p04 plan.
# If executables are in path (set by profile.d):
if command -v RasUnsteady &> /dev/null; then
    # Create the tmp hdf file expected by RasUnsteady if it doesn't exist
    # (RasUnsteady usually takes Project.p04.tmp.hdf as arg)
    HDF_INPUT="Muncie.p04.tmp.hdf"
    
    # Run simulation quietly
    su - ga -c "cd '$MUNCIE_DIR' && RasUnsteady '$HDF_INPUT' x04" > /tmp/sim_log.txt 2>&1 || true
    
    # Ensure the result is copied to the final .hdf expected by users
    if [ -f "Muncie.p04.tmp.hdf" ]; then
        cp "Muncie.p04.tmp.hdf" "Muncie.p04.hdf"
    fi
else
    echo "WARNING: RasUnsteady not found in PATH. Skipping simulation run."
fi

# 4. Generate Synthetic "Observed" High Water Marks
# This Python script reads the *actual* model results we just generated,
# picks random cross sections, adds noise, and saves the CSV for the agent.
# It also saves a hidden JSON with the "True" values for verification.

cat << 'EOF' > /tmp/generate_data.py
import h5py
import numpy as np
import pandas as pd
import json
import random
import os

hdf_path = '/home/ga/Documents/hec_ras_projects/Muncie/Muncie.p04.hdf'
output_csv = '/home/ga/Documents/field_data/observed_hwm.csv'
ground_truth_json = '/var/lib/hec_ras/calibration_ground_truth.json'

try:
    if not os.path.exists(hdf_path):
        print(f"Error: Results file {hdf_path} not found")
        exit(1)

    with h5py.File(hdf_path, 'r') as f:
        # Standard HEC-RAS 6.x paths
        # Note: Paths might vary slightly by version, trying common ones
        base_path = 'Results/Unsteady/Output/Output Blocks/Base Output/Unsteady Time Series/Cross Sections'
        geom_path = 'Geometry/Cross Sections/Attributes'
        
        # 1. Get Model WSEs
        if base_path not in f:
            print("Error: Results path not found in HDF")
            exit(1)
            
        # Shape: (Time, CrossSection)
        wse_data = f[base_path + '/Water Surface'][:]
        # Get Max WSE per XS
        max_wse = np.max(wse_data, axis=0)
        
        # 2. Get River Stations
        # These are usually stored as bytes
        stations_raw = f[geom_path]['River Station'][:]
        stations = [s.decode('utf-8').strip() if isinstance(s, bytes) else str(s).strip() for s in stations_raw]
        
        # 3. Select random subset for "Field Data"
        num_points = min(12, len(stations))
        indices = sorted(random.sample(range(len(stations)), num_points))
        
        observed_data = []
        ground_truth = []
        
        for idx in indices:
            station = stations[idx]
            true_val = float(max_wse[idx])
            
            # Add Gaussian noise (Mean=0, Std=0.5 ft)
            noise = random.gauss(0, 0.5)
            observed_val = round(true_val + noise, 2)
            
            # Record for agent
            observed_data.append({
                'River_Station': station,
                'Observed_WSE_ft': observed_val
            })
            
            # Record for verifier (True model value vs Observed)
            ground_truth.append({
                'station': station,
                'model_wse': true_val,
                'observed_wse': observed_val,
                'residual': true_val - observed_val
            })
            
        # Calculate expected RMSE for verification
        residuals = [x['residual'] for x in ground_truth]
        rmse = np.sqrt(np.mean(np.array(residuals)**2))
        
        # Save Agent CSV
        df = pd.DataFrame(observed_data)
        df.to_csv(output_csv, index=False)
        
        # Save Verifier JSON
        gt_data = {
            'points': ground_truth,
            'expected_rmse': rmse
        }
        with open(ground_truth_json, 'w') as jf:
            json.dump(gt_data, jf, indent=2)
            
        print(f"Generated {num_points} HWMs. Expected RMSE: {rmse:.4f}")

except Exception as e:
    print(f"Generation failed: {e}")
    exit(1)
EOF

echo "Generating observed data..."
python3 /tmp/generate_data.py

# 5. Finalize Environment
# Timestamp for anti-gaming
date +%s > /tmp/task_start_time.txt
chown ga:ga /home/ga/Documents/field_data/observed_hwm.csv

# Open a terminal for the agent
launch_terminal "$MUNCIE_DIR" 2>/dev/null || true

# Maximize terminal
sleep 2
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Initial screenshot
source /workspace/scripts/task_utils.sh
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="