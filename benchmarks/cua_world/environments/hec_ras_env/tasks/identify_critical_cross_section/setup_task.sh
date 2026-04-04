#!/bin/bash
set -e
echo "=== Setting up identify_critical_cross_section task ==="

source /workspace/scripts/task_utils.sh

# 1. Restore clean Muncie project
restore_muncie_project

# 2. Ensure simulation results exist (Run simulation if needed)
# This ensures the HDF5 file is present and populated
run_simulation_if_needed

# 3. Clean up any previous results from user directory
rm -f /home/ga/Documents/hec_ras_results/critical_section_report.csv
rm -f /home/ga/Documents/hec_ras_results/critical_section_summary.txt
mkdir -p /home/ga/Documents/hec_ras_results
chown -R ga:ga /home/ga/Documents/hec_ras_results

# 4. Generate Ground Truth (Hidden from agent)
echo "Generating ground truth data..."
mkdir -p /var/lib/hec-ras
cat > /tmp/generate_gt.py << 'EOF'
import h5py
import numpy as np
import json
import os

project_dir = "/home/ga/Documents/hec_ras_projects/Muncie"
hdf_file = os.path.join(project_dir, "Muncie.p04.hdf")

if not os.path.exists(hdf_file):
    print(f"Error: HDF file not found at {hdf_file}")
    exit(1)

try:
    with h5py.File(hdf_file, 'r') as f:
        # 1. Get River Stations
        # Location varies slightly by version, checking standard paths
        if 'Geometry/Cross Sections/Attributes' in f:
            # HEC-RAS 6.x standard
            rs_data = f['Geometry/Cross Sections/Attributes'][()]
            # rs_data is often a structured array. Column 'River Station' usually exists.
            # It might be byte strings.
            try:
                river_stations = [x[0].decode('utf-8').strip() for x in rs_data] # Assuming first col is RS
            except:
                # Fallback if column name access is needed
                import pandas as pd
                df = pd.DataFrame(rs_data)
                # Decode all byte columns
                str_df = df.select_dtypes([object]).stack().str.decode('utf-8').unstack()
                for c in str_df.columns: df[c] = str_df[c]
                river_stations = df['River Station'].astype(str).str.strip().tolist()
        else:
            print("Error: Could not find Cross Section Attributes")
            exit(1)

        # 2. Get Bank Stations (Geometry)
        # Usually in Geometry/Cross Sections/Bank Stations
        # This is often a 2D array [Left, Right] per cross section corresponding to RS list
        if 'Geometry/Cross Sections/Bank Stations' in f:
            bank_stations = f['Geometry/Cross Sections/Bank Stations'][()]
        else:
            print("Error: Could not find Bank Stations")
            exit(1)
        
        # 3. Get Station-Elevation Profiles to lookup elevations
        # This is tricky in HDF. It's often 'Station Elevation Values' as a 1D array 
        # with 'Station Elevation Info' giving start/count indices.
        se_values = f['Geometry/Cross Sections/Station Elevation Values'][()] # 2D array: [Station, Elev]
        se_info = f['Geometry/Cross Sections/Station Elevation Info'][()]     # [Start Index, Count, ...]
        
        left_bank_elevs = []
        right_bank_elevs = []
        
        for i, info in enumerate(se_info):
            start_idx = info[0]
            count = info[1]
            # Extract profile for this XS
            profile = se_values[start_idx : start_idx + count]
            stations = profile[:, 0]
            elevations = profile[:, 1]
            
            # Interpolate or find exact bank station elevation
            lb_station = bank_stations[i][0]
            rb_station = bank_stations[i][1]
            
            # Simple linear interpolation
            lb_elev = np.interp(lb_station, stations, elevations)
            rb_elev = np.interp(rb_station, stations, elevations)
            
            left_bank_elevs.append(float(lb_elev))
            right_bank_elevs.append(float(rb_elev))

        # 4. Get Peak WSE (Results)
        # Results/Unsteady/Output/Output Blocks/Base Output/Unsteady Time Series/Cross Sections/Water Surface
        # This is (Time, XS) array. We need Max over time for each XS.
        wse_path = 'Results/Unsteady/Output/Output Blocks/Base Output/Unsteady Time Series/Cross Sections/Water Surface'
        if wse_path in f:
            wse_data = f[wse_path][()]
            # Max over time axis (usually axis 0)
            peak_wse = np.max(wse_data, axis=0)
        else:
            print("Error: Could not find WSE results")
            exit(1)

        # 5. Compile Data
        results = []
        min_freeboard = float('inf')
        critical_rs = ""
        overtopped_count = 0
        
        for i, rs in enumerate(river_stations):
            p_wse = float(peak_wse[i])
            lb_el = left_bank_elevs[i]
            rb_el = right_bank_elevs[i]
            min_bank = min(lb_el, rb_el)
            freeboard = min_bank - p_wse
            
            if freeboard < 0:
                overtopped_count += 1
            
            if freeboard < min_freeboard:
                min_freeboard = freeboard
                critical_rs = rs
                
            results.append({
                "River_Station": rs,
                "Peak_WSE_ft": round(p_wse, 4),
                "Left_Bank_Elev_ft": round(lb_el, 4),
                "Right_Bank_Elev_ft": round(rb_el, 4),
                "Min_Bank_Elev_ft": round(min_bank, 4),
                "Freeboard_ft": round(freeboard, 4)
            })

        ground_truth = {
            "critical_section": critical_rs,
            "min_freeboard": round(min_freeboard, 4),
            "total_sections": len(river_stations),
            "overtopped_count": overtopped_count,
            "data": results
        }
        
        with open("/var/lib/hec-ras/ground_truth.json", "w") as jf:
            json.dump(ground_truth, jf, indent=2)
            
        print("Ground truth generated successfully.")

except Exception as e:
    print(f"GT Generation Failed: {e}")
    # Create fallback for verifying basic execution even if GT fails (should not happen on stable env)
    fallback = {"critical_section": "UNKNOWN", "data": []}
    with open("/var/lib/hec-ras/ground_truth.json", "w") as jf:
        json.dump(fallback, jf)
EOF

# Execute GT generation using system python (has h5py/numpy)
python3 /tmp/generate_gt.py

# 5. Open Terminal in Project Directory
launch_terminal "$MUNCIE_DIR"
sleep 2

# 6. Record start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# 7. Initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="