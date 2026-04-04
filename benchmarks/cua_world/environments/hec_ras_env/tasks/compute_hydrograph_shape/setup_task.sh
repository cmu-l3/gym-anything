#!/bin/bash
set -e
echo "=== Setting up hydrograph shape analysis task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Restore clean Muncie project
restore_muncie_project

# 2. Run simulation to ensure results exist (HEC-RAS output)
run_simulation_if_needed

# 3. Clean previous results
rm -f /home/ga/Documents/hec_ras_results/hydrograph_shape_params.csv
rm -f /home/ga/Documents/hec_ras_results/hydrograph_shape_summary.txt
mkdir -p /home/ga/Documents/hec_ras_results
chown -R ga:ga /home/ga/Documents/hec_ras_results

# 4. Compute REFERENCE VALUES (Ground Truth)
# We do this now so we have absolute truth based on the specific simulation file present
echo "--- Computing reference values for verification ---"
python3 << 'PYEOF'
import h5py
import numpy as np
import json
import os
import sys

hdf_path = "/home/ga/Documents/hec_ras_projects/Muncie/Muncie.p04.tmp.hdf"
ref_path = "/tmp/hydrograph_shape_reference.json"

try:
    if not os.path.exists(hdf_path):
        print(f"ERROR: HDF file not found at {hdf_path}")
        sys.exit(0)

    f = h5py.File(hdf_path, 'r')
    
    # Locate flow data
    # Paths can vary in RAS HDF files, search for Unsteady Time Series flow
    flow_ds = None
    flow_path = ""
    
    # Common HEC-RAS 6.x paths
    candidates = [
        "Results/Unsteady/Output/Output Blocks/Base Output/Unsteady Time Series/Cross Sections/Flow",
        "Results/Unsteady/Output/Output Blocks/DSS Profile Output/Unsteady Time Series/Cross Sections/Flow"
    ]
    
    for p in candidates:
        if p in f:
            flow_ds = f[p]
            flow_path = p
            break
            
    if flow_ds is None:
        # Recursive search if standard paths fail
        def visitor(name, node):
            global flow_ds, flow_path
            if flow_ds is None and isinstance(node, h5py.Dataset) and name.endswith("/Flow") and "Cross Sections" in name:
                if node.ndim == 2: # Time x XS
                    flow_ds = node
                    flow_path = name
        f.visititems(visitor)

    if flow_ds is None:
        print("ERROR: Could not find Flow dataset in HDF5")
        with open(ref_path, 'w') as jf:
            json.dump({"error": "Flow dataset not found"}, jf)
        sys.exit(0)

    flow_data = flow_ds[:] # Shape: (Time, CrossSections)
    
    # Get River Stations (Cross Section IDs)
    # Usually in attributes of the group containing Flow, or Geometry
    river_stations = []
    
    # Try Geometry first (most reliable for order)
    try:
        geom_xs = f['Geometry/Cross Sections/Attributes']
        if 'RS' in geom_xs.dtype.names:
             river_stations = [rs.decode('utf-8') if isinstance(rs, bytes) else str(rs) for rs in geom_xs['RS']]
    except:
        pass
        
    # Fallback to result attributes
    if not river_stations:
        try:
            parent = flow_ds.parent
            # Some RAS versions store station names as attributes or datasets here
            pass 
        except:
            pass
            
    # If we can't find names, use indices
    if not river_stations:
        river_stations = [str(i) for i in range(flow_data.shape[1])]

    # Determine indices for Upstream, Midpoint, Downstream
    # RAS typically orders upstream (index 0) to downstream (index -1)
    # We verify by peak flow timing or magnitude if needed, but index order is standard
    n_xs = len(river_stations)
    idx_up = 0
    idx_down = n_xs - 1
    idx_mid = n_xs // 2
    
    target_indices = [idx_up, idx_mid, idx_down]
    
    # Time step - assume 1 hour or try to read
    # For Muncie example, it's usually 15 min or 1 hour. We'll try to deduce or assume 1 hr if unclear
    # Ideally read "Time Date Stamp" or similar, but for shape params relative values matter most.
    # We will assume the agent deduces it. Let's try to get dt from attributes.
    dt_hours = 0.0
    try:
        # Try to find time interval
        base_output = f['Results/Unsteady/Output/Output Blocks/Base Output/Unsteady Time Series']
        times = base_output['Time'][:]
        # Times are usually in days or hours. In RAS HDF, often "Time" dataset is days from start
        # Let's check first two points
        if len(times) > 1:
            dt_days = times[1] - times[0]
            dt_hours = dt_days * 24.0
    except:
        pass
        
    if dt_hours <= 0:
        dt_hours = 1.0 # Fallback if time parsing fails, though this might affect T_rise comparison
        # Usually Muncie is 15 min or 1 hour output interval
        
    results = {}
    
    for idx in target_indices:
        rs = river_stations[idx]
        q = flow_data[:, idx]
        
        q_base = float(np.min(q))
        q_peak = float(np.max(q))
        
        # Thresholds
        q_range = q_peak - q_base
        thresh_10 = q_base + 0.10 * q_range
        thresh_50 = q_base + 0.50 * q_range
        thresh_75 = q_base + 0.75 * q_range
        
        # Indices above threshold
        above_10_indices = np.where(q > thresh_10)[0]
        
        # Default values
        t_rise = 0.0
        t_rec = 0.0
        r_ratio = 0.0
        w50 = 0.0
        w75 = 0.0
        p_coeff = 0.0
        
        if len(above_10_indices) > 0:
            peak_idx = np.argmax(q)
            
            # T_rise: start of >10% to peak
            # Find first index > 10%
            start_idx = above_10_indices[0]
            if peak_idx > start_idx:
                t_rise = (peak_idx - start_idx) * dt_hours
            
            # T_rec: peak to last index > 10%
            # Note: simplified definition from task description
            # "Time from Q_peak to when flow last drops below Q_base + 10%"
            # Meaning last point > 10%
            end_idx = above_10_indices[-1]
            if end_idx > peak_idx:
                t_rec = (end_idx - peak_idx) * dt_hours
            
            if t_rec > 0:
                r_ratio = t_rise / t_rec
            else:
                r_ratio = 999.0 # infinity
                
            # Widths
            count_50 = np.sum(q > thresh_50)
            w50 = count_50 * dt_hours
            
            count_75 = np.sum(q > thresh_75)
            w75 = count_75 * dt_hours
            
            # Peakedness
            q_mean_10 = np.mean(q[above_10_indices])
            if q_mean_10 > 0:
                p_coeff = q_peak / q_mean_10
                
        results[rs] = {
            "index": int(idx),
            "Q_base": q_base,
            "Q_peak": q_peak,
            "T_rise": t_rise,
            "T_rec": t_rec,
            "R_ratio": r_ratio,
            "W50": w50,
            "W75": w75,
            "P_coeff": p_coeff,
            "classification": "fast-rising" if r_ratio < 0.7 else ("slow-rising" if r_ratio > 1.3 else "symmetric")
        }

    # Save reference
    out_data = {
        "river_stations": river_stations,
        "dt_hours": dt_hours,
        "targets": results
    }
    
    with open(ref_path, 'w') as jf:
        json.dump(out_data, jf, indent=2)
        
    print(f"Reference values calculated using dt={dt_hours} hrs")

except Exception as e:
    print(f"Error computing reference: {e}")
    with open(ref_path, 'w') as jf:
        json.dump({"error": str(e)}, jf)
PYEOF

chmod 644 /tmp/hydrograph_shape_reference.json

# 5. Launch terminal
launch_terminal "$MUNCIE_DIR"

# 6. Take initial screenshot
echo "Capturing initial state..."
sleep 2
take_screenshot /tmp/task_initial.png

# Validate screenshot
if [ -f /tmp/task_initial.png ]; then
    echo "Initial screenshot captured."
else
    echo "WARNING: Failed to capture initial screenshot"
fi

echo "=== Task setup complete ==="