#!/bin/bash
echo "=== Setting up Conveyance Audit Task ==="

source /workspace/scripts/task_utils.sh

# 1. Restore clean Muncie project
restore_muncie_project

# 2. Run simulation immediately to ensure valid starting state and generate ground truth
# We run it here so we can generate the ground truth file hidden from the agent.
# The agent might re-run it, which is fine, but we need guaranteed results for verification.
echo "Running baseline simulation for ground truth generation..."
run_simulation_if_needed

# 3. Generate Ground Truth CSV (Hidden)
echo "Generating ground truth data..."
mkdir -p /var/lib/hec-ras
cat > /tmp/gen_ground_truth.py << 'EOF'
import h5py
import numpy as np
import pandas as pd
import sys
import os

try:
    # Open HDF5 file
    hdf_path = "/home/ga/Documents/hec_ras_projects/Muncie/Muncie.p04.hdf"
    if not os.path.exists(hdf_path):
        print(f"Error: HDF not found at {hdf_path}")
        sys.exit(1)

    with h5py.File(hdf_path, 'r') as f:
        # 1. Get River Stations (Geometry)
        # Path varies by version, try standard 6.x path
        try:
            geom_path = "Geometry/Cross Sections/Attributes"
            rs_data = f[geom_path][:]
            # Extract RS names (decoded from bytes)
            # Structure usually has 'River Station' field
            rs_names = [x[0].decode('utf-8').strip() for x in rs_data]
        except:
            # Fallback for some HDF structures
            geom_path = "Geometry/Cross Sections/River Stations"
            rs_data = f[geom_path][:]
            rs_names = [x.decode('utf-8').strip() for x in rs_data]

        # 2. Get Results
        # Paths for Flow and Friction Slope
        # Usually: Results/Unsteady/Output/Output Blocks/Base Output/Unsteady Time Series/Cross Sections
        results_path = "Results/Unsteady/Output/Output Blocks/Base Output/Unsteady Time Series/Cross Sections"
        
        flow_data = f[f"{results_path}/Flow"][:] # Shape: (Time, XS)
        slope_data = f[f"{results_path}/Friction Slope"][:] # Shape: (Time, XS)

    # Process data
    audit_rows = []
    
    # Create DataFrame for easier sorting/handling
    # Note: HEC-RAS geometry is usually stored Upstream -> Downstream order in the arrays
    # But let's verify by sorting RS numerically if they are numbers
    df_xs = pd.DataFrame({'RS_Name': rs_names, 'Index': range(len(rs_names))})
    
    # Convert RS to float for sorting
    df_xs['RS_Float'] = pd.to_numeric(df_xs['RS_Name'], errors='coerce')
    df_xs = df_xs.sort_values('RS_Float', ascending=False).reset_index(drop=True)
    
    k_values = {}
    
    for i, row in df_xs.iterrows():
        idx = row['Index']
        rs = row['RS_Name']
        
        # Get time series for this XS
        flows = flow_data[:, idx]
        slopes = slope_data[:, idx]
        
        # Find index of Peak Flow
        # Use abs() because flow could be negative (upstream)? Usually positive in Muncie.
        # But standard is max(Q)
        peak_idx = np.argmax(flows)
        
        q_peak = flows[peak_idx]
        sf_peak = slopes[peak_idx]
        
        # Compute K
        if sf_peak < 0.0001:
            k = 0.0
        else:
            k = q_peak / np.sqrt(sf_peak)
            
        k_values[rs] = k

    # Compute Ratios
    for i in range(len(df_xs) - 1):
        up_rs = df_xs.iloc[i]['RS_Name']
        dn_rs = df_xs.iloc[i+1]['RS_Name']
        
        k_up = k_values[up_rs]
        k_dn = k_values[dn_rs]
        
        status = "OK"
        ratio = 0.0
        
        if k_up == 0 or k_dn == 0:
            status = "Skipped"
        else:
            ratio = k_up / k_dn
            if ratio < 0.7 or ratio > 1.4:
                status = "Warning"
                
        audit_rows.append({
            'Upstream_River_Station': up_rs,
            'Downstream_River_Station': dn_rs,
            'K_Upstream': round(k_up, 2),
            'K_Downstream': round(k_dn, 2),
            'Ratio': round(ratio, 4),
            'Status': status
        })

    # Save CSV
    pd.DataFrame(audit_rows).to_csv("/var/lib/hec-ras/ground_truth_conveyance.csv", index=False)
    print("Ground truth generated successfully.")

except Exception as e:
    print(f"FAILED: {e}")
    sys.exit(1)
EOF

# Execute ground truth generation
python3 /tmp/gen_ground_truth.py
rm -f /tmp/gen_ground_truth.py

# verify it was created
if [ -f "/var/lib/hec-ras/ground_truth_conveyance.csv" ]; then
    echo "Ground truth created: $(wc -l < /var/lib/hec-ras/ground_truth_conveyance.csv) lines"
else
    echo "WARNING: Failed to create ground truth!"
fi

# 4. Clear output directory
rm -rf /home/ga/Documents/hec_ras_results
mkdir -p /home/ga/Documents/hec_ras_results
chown -R ga:ga /home/ga/Documents/hec_ras_results

# 5. Open terminal in project directory
launch_terminal "$MUNCIE_DIR"

# 6. Initial screenshot
take_screenshot /tmp/task_start.png

# 7. Record start time
date +%s > /tmp/task_start_time.txt

echo "=== Task setup complete ==="