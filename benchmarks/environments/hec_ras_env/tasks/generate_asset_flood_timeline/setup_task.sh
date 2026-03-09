#!/bin/bash
set -e
echo "=== Setting up Generate Asset Flood Timeline Task ==="

source /workspace/scripts/task_utils.sh

# 1. Restore clean Muncie project
restore_muncie_project

# 2. Ensure simulation results exist (Run simulation if needed)
# This is critical because we need results to generate the ground truth
run_simulation_if_needed

# 3. Create a Python script to generate assets.csv and ground_truth.json
# We do this dynamically so the values are always correct for the current simulation state
cat > /tmp/generate_scenario.py << 'PYEOF'
import h5py
import numpy as np
import pandas as pd
import json
import os

# Paths
hdf_file = "/home/ga/Documents/hec_ras_projects/Muncie/Muncie.p04.hdf"
assets_csv = "/home/ga/Documents/hec_ras_projects/Muncie/assets.csv"
ground_truth_json = "/var/lib/hec_ras/ground_truth.json"

# Ensure directories exist
os.makedirs(os.path.dirname(ground_truth_json), exist_ok=True)

try:
    with h5py.File(hdf_file, 'r') as f:
        # Locate results
        # Path structure varies by version, try standard locations
        base_path = '/Results/Unsteady/Output/Output Blocks/Base Output/Unsteady Time Series/Cross Sections'
        if base_path not in f:
            print(f"Error: Could not find base path {base_path}")
            exit(1)
            
        wse_ds = f[base_path + '/Water Surface']
        
        # Get River Stations (often stored as bytes)
        # Location of attributes depends on geometry, but usually reachable via:
        # /Geometry/Cross Sections/Attributes
        geom_path = '/Geometry/Cross Sections/Attributes'
        if geom_path in f:
            stations = f[geom_path][:]['River Station']
            # Decode bytes if needed
            stations = [s.decode('utf-8').strip() if isinstance(s, bytes) else str(s).strip() for s in stations]
        else:
            # Fallback: assume 1-based index maps to some stations or just use indices
            print("Warning: Could not find river stations, using indices")
            stations = [str(i) for i in range(wse_ds.shape[1])]

        # Get Time (hours)
        # Time path is usually at /Results/Unsteady/Output/Output Blocks/Base Output/Unsteady Time Series/Time Date Stamp
        # But raw time values might be in /Results/Unsteady/Output/Output Blocks/Base Output/Unsteady Time Series/Time
        time_path = '/Results/Unsteady/Output/Output Blocks/Base Output/Unsteady Time Series/Time'
        if time_path in f:
            time_hours = f[time_path][:]
            # If it's stored as days, convert to hours? Usually it's hours in this dataset
            # Let's assume the first value is t0.
            # Actually, standard HEC-RAS is hours.
        else:
            # Fallback
            time_hours = np.arange(wse_ds.shape[0])

        # Select 4 representative cross sections
        # We need a mix of behaviors.
        # Let's pick indices spread out.
        indices = np.linspace(0, len(stations)-1, 4, dtype=int)
        
        assets = []
        ground_truth = []
        
        # Scenario definitions
        scenarios = [
            ("School", "floods_early", -2.0),   # Threshold = Max - 2.0 (Floods well)
            ("Hospital", "floods_late", -0.2),  # Threshold = Max - 0.2 (Floods briefly/late)
            ("Bridge", "safe", 5.0),            # Threshold = Max + 5.0 (Safe)
            ("Park", "floods_deep", -5.0)       # Threshold = Max - 5.0 (Floods deeply)
        ]
        
        for i, (name, sce_type, delta) in enumerate(scenarios):
            idx = indices[i]
            station = stations[idx]
            wse_series = wse_ds[:, idx]
            
            max_wse = np.max(wse_series)
            threshold = float(max_wse + delta)
            
            # Round threshold to 1 decimal place to look realistic
            threshold = round(threshold, 1)
            
            # Calculate Ground Truth
            is_flooded = False
            onset = None
            duration = 0.0
            peak_depth = 0.0
            
            flooded_mask = wse_series > threshold
            if np.any(flooded_mask):
                is_flooded = True
                # Onset: first time index where flooded
                onset_idx = np.argmax(flooded_mask)
                onset = float(time_hours[onset_idx])
                
                # Duration: simply count hours (assuming constant time step for simplicity, or sum dt)
                # dt is usually constant. Let's approximate by count * dt
                dt = time_hours[1] - time_hours[0]
                duration = float(np.sum(flooded_mask) * dt)
                
                # Peak depth
                peak_depth = float(np.max(wse_series) - threshold)
            
            assets.append({
                "Asset_ID": f"A{i+1:03d}",
                "Asset_Name": name,
                "River_Station": station,
                "Threshold_Elevation_ft": threshold
            })
            
            ground_truth.append({
                "Asset_Name": name,
                "Flooded": is_flooded,
                "Time_of_Onset_Hours": onset,
                "Flood_Duration_Hours": duration,
                "Peak_Depth_Above_Threshold_ft": peak_depth
            })
            
        # Write assets.csv
        df = pd.DataFrame(assets)
        df.to_csv(assets_csv, index=False)
        print(f"Created {assets_csv}")
        
        # Write ground_truth.json (hidden)
        with open(ground_truth_json, 'w') as f:
            json.dump(ground_truth, f, indent=2)
        print(f"Created {ground_truth_json}")

except Exception as e:
    print(f"Failed to generate scenario: {e}")
    import traceback
    traceback.print_exc()
PYEOF

# 4. Run the generation script
python3 /tmp/generate_scenario.py

# 5. Clean up previous results directory
rm -rf /home/ga/Documents/hec_ras_results
mkdir -p /home/ga/Documents/hec_ras_results
chown -R ga:ga /home/ga/Documents/hec_ras_results
chown ga:ga /home/ga/Documents/hec_ras_projects/Muncie/assets.csv

# 6. Open terminal in the project directory
launch_terminal "$MUNCIE_DIR"

# 7. Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Task setup complete ==="