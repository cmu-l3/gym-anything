#!/bin/bash
set -e
echo "=== Setting up compute_flood_duration task ==="

source /workspace/scripts/task_utils.sh

# 1. Record task start time
date +%s > /tmp/task_start_time.txt

# 2. Setup Directories
RESULTS_DIR="/home/ga/Documents/hec_ras_results"
mkdir -p "$RESULTS_DIR"
# Clean previous results if they exist
rm -f "$RESULTS_DIR/flood_duration.csv"
rm -f "$RESULTS_DIR/flood_duration_analysis.py"

# 3. Restore Muncie Project
restore_muncie_project

# 4. Ensure Simulation Results Exist
# We need the .p04.hdf file. If it doesn't exist, run the simulation.
if [ ! -f "$MUNCIE_DIR/Muncie.p04.hdf" ]; then
    echo "Running HEC-RAS simulation to generate results..."
    run_simulation_if_needed
else
    echo "Simulation results already exist."
fi

# 5. Generate Ground Truth (Hidden from Agent)
# We calculate the expected values now so the verifier can compare later.
# This ensures verification is robust even if the simulation environment changes slightly.
echo "Generating ground truth data..."
GT_DIR="/var/lib/hec_ras"
mkdir -p "$GT_DIR"

cat > /tmp/gen_gt.py << 'EOF'
import h5py
import numpy as np
import json
import os

try:
    # Find HDF file
    muncie_dir = "/home/ga/Documents/hec_ras_projects/Muncie"
    hdf_file = os.path.join(muncie_dir, "Muncie.p04.hdf")
    
    if not os.path.exists(hdf_file):
        # Fallback to tmp
        hdf_file = os.path.join(muncie_dir, "Muncie.p04.tmp.hdf")

    results = {}
    
    with h5py.File(hdf_file, 'r') as f:
        # Locate WSE dataset
        # Path varies by version, try standard paths
        wse_path = None
        paths_to_check = [
            "Results/Unsteady/Output/Output Blocks/Base Output/Unsteady Time Series/Cross Sections/Water Surface",
            "Results/Unsteady/Output/Output Blocks/DSS Profile Output/Unsteady Time Series/Cross Sections/Water Surface"
        ]
        
        for p in paths_to_check:
            if p in f:
                wse_path = p
                break
        
        if wse_path is None:
            # Recursive search
            def visitor(name, node):
                nonlocal wse_path
                if wse_path is None and isinstance(node, h5py.Dataset) and 'water surface' in name.lower() and 'time series' in name.lower():
                    wse_path = name
            f.visititems(visitor)

        if wse_path:
            wse_data = f[wse_path][:] # Shape: (Time, XS)
            
            # Determine time interval (approximate if attribute missing)
            # Standard Muncie example is often 1 hour or 15 min. 
            # We'll calculate indices first.
            
            # Calculate metrics for first 5 and last 5 XS to save space
            num_xs = wse_data.shape[1]
            num_steps = wse_data.shape[0]
            
            # Assume 1 hour interval if not found, but we store raw steps for verification
            # Actually, let's try to find interval
            dt_hours = 1.0 # Default
            # Try to find Time dataset
            time_path = wse_path.replace("Water Surface", "Time")
            if "Time" in f:
                 # Check common time paths
                 pass
            
            xs_indices = list(range(min(10, num_xs))) + list(range(max(10, num_xs-10), num_xs))
            xs_indices = sorted(list(set(xs_indices)))
            
            gt_data = []
            
            for idx in xs_indices:
                series = wse_data[:, idx]
                initial_wse = series[0]
                threshold = initial_wse + 2.0
                peak = np.max(series)
                
                # Count steps above
                steps_above = np.sum(series > threshold)
                
                gt_data.append({
                    "xs_index": int(idx),
                    "initial_wse": float(initial_wse),
                    "threshold": float(threshold),
                    "peak_wse": float(peak),
                    "steps_above_threshold": int(steps_above),
                    "total_steps": int(num_steps)
                })
            
            results["valid"] = True
            results["data"] = gt_data
            results["total_xs"] = int(num_xs)
        else:
            results["valid"] = False
            results["error"] = "WSE path not found"

    with open("/var/lib/hec_ras/ground_truth.json", "w") as f:
        json.dump(results, f, indent=2)

except Exception as e:
    with open("/var/lib/hec_ras/ground_truth.json", "w") as f:
        json.dump({"valid": False, "error": str(e)}, f)
EOF

python3 /tmp/gen_gt.py
chmod 644 "$GT_DIR/ground_truth.json"

# 6. Open Terminal in Project Directory
echo "Launching terminal..."
launch_terminal "$MUNCIE_DIR"

# 7. Initial Screenshot
sleep 5
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="