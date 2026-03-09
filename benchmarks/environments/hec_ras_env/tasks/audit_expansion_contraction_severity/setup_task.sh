#!/bin/bash
echo "=== Setting up audit_expansion_contraction_severity task ==="

source /workspace/scripts/task_utils.sh

# 1. Restore clean Muncie project
restore_muncie_project

# 2. Ensure simulation results exist to save time (but agent should verify)
# We pre-run the simulation so the Ground Truth is deterministic and available immediately
echo "Ensuring simulation results exist..."
run_simulation_if_needed

# 3. Create results directory
mkdir -p /home/ga/Documents/hec_ras_results
chown ga:ga /home/ga/Documents/hec_ras_results

# 4. Remove any pre-existing output files to ensure fresh creation
rm -f /home/ga/Documents/hec_ras_results/transition_audit.csv
rm -f /home/ga/Documents/hec_ras_results/transition_report.txt

# 5. Open terminal in project directory
echo "Opening terminal..."
launch_terminal "$MUNCIE_DIR"

# 6. Pre-calculate Ground Truth (hidden from agent)
# This ensures we have the correct answers based on the EXACT simulation state
echo "Generating ground truth (hidden)..."
cat << 'PY_GT' > /tmp/generate_ground_truth.py
import h5py
import numpy as np
import json
import os

try:
    # Open HDF file
    hdf_file = "/home/ga/Documents/hec_ras_projects/Muncie/Muncie.p04.hdf"
    if not os.path.exists(hdf_file):
        print(json.dumps({"error": "HDF file not found"}))
        exit(0)

    with h5py.File(hdf_file, 'r') as f:
        # HEC-RAS HDF structure paths
        geom_path = 'Geometry/Cross Sections/Attributes'
        res_path = 'Results/Unsteady/Output/Output Blocks/Base Output/Unsteady Time Series/Cross Sections'
        
        # Read River Stations (Names)
        # They are often stored as byte strings in 'River Station' dataset
        rs_data = f[geom_path]['River Station'][:]
        river_stations = [x.decode('utf-8').strip() for x in rs_data]
        
        # Sort stations: Assuming numeric for Muncie, High to Low is Upstream to Downstream
        # We create a list of (value, index, name)
        rs_numeric = []
        for i, rs in enumerate(river_stations):
            try:
                val = float(rs)
                rs_numeric.append((val, i, rs))
            except:
                pass # Handle non-numeric stations if any
        
        # Sort descending (Upstream -> Downstream)
        rs_numeric.sort(key=lambda x: x[0], reverse=True)
        
        transitions = []
        worst_expansion_ratio = -1.0
        worst_expansion_segment = ""
        severe_expansion_count = 0
        severe_contraction_count = 0
        
        # Loop through sorted stations to calculate transitions
        for i in range(len(rs_numeric) - 1):
            u_node = rs_numeric[i]   # Upstream
            d_node = rs_numeric[i+1] # Downstream
            
            # Get Top Width Data (2D array: Time x XS)
            # We need to find the specific column index for the XS
            # The 'Cross Section' results group usually has datasets like 'Top Width' 
            # where columns correspond to the order in Geometry or have a mapping.
            # In HEC-RAS 6.6 HDF, data is usually (Time, XS_Count).
            # We assume the index `u_node[1]` matches the column in the results.
            
            # Get Flow to find peak time
            flow_ds = f[res_path]['Flow']
            width_ds = f[res_path]['Top Width']
            
            # Upstream Data
            u_idx = u_node[1]
            u_flows = flow_ds[:, u_idx]
            u_widths = width_ds[:, u_idx]
            u_peak_time_idx = np.argmax(u_flows)
            u_width_at_peak = u_widths[u_peak_time_idx]
            
            # Downstream Data
            d_idx = d_node[1]
            d_flows = flow_ds[:, d_idx]
            d_widths = width_ds[:, d_idx]
            d_peak_time_idx = np.argmax(d_flows)
            d_width_at_peak = d_widths[d_peak_time_idx]
            
            # Calculate Ratio
            if u_width_at_peak > 0:
                ratio = d_width_at_peak / u_width_at_peak
            else:
                ratio = 0.0
            
            status = "Acceptable"
            if ratio > 1.5:
                status = "Severe"
                severe_expansion_count += 1
                if ratio > worst_expansion_ratio:
                    worst_expansion_ratio = ratio
                    worst_expansion_segment = f"{u_node[2]} to {d_node[2]}"
            elif ratio < 0.5:
                status = "Severe"
                severe_contraction_count += 1
                
            transitions.append({
                "upstream_xs": u_node[2],
                "downstream_xs": d_node[2],
                "upstream_width": float(u_width_at_peak),
                "downstream_width": float(d_width_at_peak),
                "ratio": float(ratio),
                "status": status
            })

        result = {
            "total_transitions": len(transitions),
            "severe_expansion_count": severe_expansion_count,
            "severe_contraction_count": severe_contraction_count,
            "worst_expansion_segment": worst_expansion_segment,
            "worst_expansion_ratio": float(worst_expansion_ratio),
            "transitions": transitions
        }
        
        print(json.dumps(result, indent=2))

except Exception as e:
    print(json.dumps({"error": str(e)}))
PY_GT

# Run Ground Truth Generation
python3 /tmp/generate_ground_truth.py > /tmp/ground_truth.json
chmod 644 /tmp/ground_truth.json
# Hide the script
rm /tmp/generate_ground_truth.py

# 7. Record start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# 8. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="