#!/bin/bash
set -e
echo "=== Setting up evaluate_development_flood_risk task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# 1. Restore Muncie project to ensure clean state
restore_muncie_project

# 2. Run simulation if results don't exist
# We need the results to generate the ground truth data dynamically
if [ ! -f "$MUNCIE_DIR/Muncie.p04.hdf" ] && [ ! -f "$MUNCIE_DIR/Muncie.p04.tmp.hdf" ]; then
    echo "Running HEC-RAS simulation to generate base results..."
    run_simulation_if_needed
fi

# Ensure we have a valid HDF path
HDF_FILE="$MUNCIE_DIR/Muncie.p04.hdf"
if [ ! -f "$HDF_FILE" ]; then
    HDF_FILE="$MUNCIE_DIR/Muncie.p04.tmp.hdf"
fi

if [ ! -f "$HDF_FILE" ]; then
    echo "ERROR: Simulation failed to produce HDF file"
    exit 1
fi

# 3. Generate the Input CSV and Ground Truth dynamically
# This ensures the task data matches the actual installed HEC-RAS model results
echo "Generating site inventory and ground truth data..."

mkdir -p /var/lib/hec_ras
mkdir -p "$MUNCIE_DIR"

cat > /tmp/generate_data.py << EOF
import h5py
import numpy as np
import pandas as pd
import random
import os

hdf_path = "$HDF_FILE"
output_csv_path = "$MUNCIE_DIR/proposed_development_sites.csv"
ground_truth_path = "/var/lib/hec_ras/ground_truth.csv"

print(f"Reading HDF: {hdf_path}")
try:
    with h5py.File(hdf_path, 'r') as f:
        # Paths for Muncie 1D Unsteady Results
        # Note: Adjusting paths based on standard HEC-RAS HDF structure
        
        # Geometry: River Stations
        # Path often: /Geometry/Cross Sections/River Stations
        # Or /Geometry/Cross Sections/Attributes (then column 'River Station')
        
        stations = []
        if 'Geometry/Cross Sections/River Stations' in f:
            st_ds = f['Geometry/Cross Sections/River Stations']
            stations = [s.decode('utf-8').strip() for s in st_ds[:]]
        else:
            # Fallback for some versions
            print("Warning: Standard station path not found, looking for attributes...")
            # Simple fallback: Mock stations if geometry read fails (should not happen in Muncie env)
            stations = [str(1000 + i*100) for i in range(20)]
            
        # Results: Max WSE
        # Path: /Results/Unsteady/Output/Output Blocks/Base Output/Unsteady Time Series/Cross Sections/Water Surface
        # Shape: (Time, Station)
        max_wse = []
        if 'Results/Unsteady/Output/Output Blocks/Base Output/Unsteady Time Series/Cross Sections/Water Surface' in f:
            wse_data = f['Results/Unsteady/Output/Output Blocks/Base Output/Unsteady Time Series/Cross Sections/Water Surface'][:]
            # Calculate max over time (axis 0)
            max_wse = np.max(wse_data, axis=0)
        else:
             print("Error: Could not find WSE results path")
             exit(1)

        if len(stations) != len(max_wse):
            print(f"Mismatch: {len(stations)} stations vs {len(max_wse)} result columns")
            # Truncate to shorter
            min_len = min(len(stations), len(max_wse))
            stations = stations[:min_len]
            max_wse = max_wse[:min_len]

        # Generate Data
        sites = []
        ground_truth = []
        
        # Pick 12 random stations
        indices = sorted(random.sample(range(len(stations)), min(12, len(stations))))
        
        for i, idx in enumerate(indices):
            station = stations[idx]
            wse = float(max_wse[idx])
            
            # Determine scenario (Safe, Minor Flood, Major Flood)
            scenario = random.choices(['safe', 'minor', 'major', 'severe'], weights=[0.4, 0.3, 0.2, 0.1])[0]
            
            if scenario == 'safe':
                ffe = wse + random.uniform(1.0, 5.0)
            elif scenario == 'minor':
                ffe = wse - random.uniform(0.1, 1.9)
            elif scenario == 'major':
                ffe = wse - random.uniform(2.1, 4.9)
            else: # severe
                ffe = wse - random.uniform(5.1, 8.0)
                
            prop_value = random.randint(150, 800) * 1000
            
            # Calculate Ground Truth Logic
            depth = max(0.0, wse - ffe)
            damage = 0.0
            
            if depth > 0:
                if depth < 2.0:
                    damage = 0.10 * prop_value
                elif depth < 5.0:
                    damage = 0.25 * prop_value
                else:
                    damage = 0.50 * prop_value
            
            site_id = f"SITE-{100+i}"
            
            # Input data (what agent sees)
            sites.append({
                "Site_ID": site_id,
                "River_Station": station,
                "First_Floor_Elevation_ft": round(ffe, 2),
                "Property_Value_USD": prop_value
            })
            
            # Ground truth (what verifier checks)
            ground_truth.append({
                "Site_ID": site_id,
                "River_Station": station,
                "Max_WSE_ft": round(wse, 3), # Higher precision for check
                "Flood_Depth_ft": round(depth, 3),
                "Damage_USD": int(round(damage))
            })
            
        # Save files
        pd.DataFrame(sites).to_csv(output_csv_path, index=False)
        pd.DataFrame(ground_truth).to_csv(ground_truth_path, index=False)
        print(f"Generated {len(sites)} sites.")

except Exception as e:
    print(f"Generation failed: {e}")
    exit(1)
EOF

# Execute generation script
python3 /tmp/generate_data.py

# Set permissions
chown ga:ga "$MUNCIE_DIR/proposed_development_sites.csv"
chmod 644 "$MUNCIE_DIR/proposed_development_sites.csv"
chmod 600 /var/lib/hec_ras/ground_truth.csv # Hidden from agent

# 4. Prepare UI
echo "Opening directory..."
launch_terminal "$MUNCIE_DIR"
type_in_terminal "ls -lh proposed_development_sites.csv"

# Record start time
date +%s > /tmp/task_start_time.txt

# Take initial screenshot
sleep 2
take_screenshot /tmp/task_start_screenshot.png

echo "=== Task setup complete ==="
echo "Input file generated at: $MUNCIE_DIR/proposed_development_sites.csv"