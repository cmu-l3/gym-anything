#!/bin/bash
echo "=== Exporting compute_energy_losses result ==="

# Source task utils
source /workspace/scripts/task_utils.sh

# Record timestamps
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

RESULTS_DIR="/home/ga/Documents/hec_ras_results"
CSV_PATH="$RESULTS_DIR/energy_loss_analysis.csv"
SUMMARY_PATH="$RESULTS_DIR/energy_loss_summary.txt"
SCRIPT_PATH="$RESULTS_DIR/energy_loss_analysis.py"
HDF_PATH="/home/ga/Documents/hec_ras_projects/Muncie/Muncie.p04.hdf"
GROUND_TRUTH_JSON="/tmp/ground_truth.json"

# --- 1. Generate Ground Truth Data (Internal Python Script) ---
# We calculate the ground truth INSIDE the container to ensure we have
# access to h5py and the exact HDF file version.
echo "Generating ground truth data..."

cat > /tmp/generate_ground_truth.py << 'PYEOF'
import h5py
import numpy as np
import json
import sys

try:
    hdf_path = "/home/ga/Documents/hec_ras_projects/Muncie/Muncie.p04.hdf"
    
    with h5py.File(hdf_path, 'r') as f:
        # 1. Get Geometry Info (Cross Sections)
        # Location depends on RAS version, typically /Geometry/Cross Sections/
        # or /Geometry/2D Flow Areas/ for 2D, but Muncie is 1D/Combined.
        # Checking standard 1D path
        xs_path = '/Geometry/Cross Sections'
        
        # Extract station names/dn distances
        # Note: RAS HDF structures can be complex. We'll look for basics.
        # Simplified approach: If 1D data exists
        if 'Geometry' in f and 'Cross Sections' in f['Geometry']:
            xs_props = f['Geometry']['Cross Sections']['Attributes']
            # station names usually in 'River Stations' dataset under Attributes or similar
            # Actually, usually under /Geometry/Cross Sections/River Stations
            river_stations = f['Geometry']['Cross Sections']['River Stations'][:]
            river_stations = [s.decode('utf-8').strip() for s in river_stations]
            
            # Reach lengths (Channel)
            lengths = f['Geometry']['Cross Sections']['Lengths'][:]
            # Columns often: LOB, Channel, ROB. Index 1 is channel.
            channel_lengths = lengths[:, 1]
        else:
            # Fallback or error
            print("Could not find Cross Sections in HDF")
            sys.exit(0) # Non-fatal, will just output empty GT
            
        # 2. Get Unsteady Results
        # /Results/Unsteady/Output/Output Blocks/Base Output/Unsteady Time Series/Cross Sections/
        base_path = '/Results/Unsteady/Output/Output Blocks/Base Output/Unsteady Time Series/Cross Sections'
        
        flow_ds = f[f'{base_path}/Flow'][:]
        wse_ds = f[f'{base_path}/Water Surface'][:]
        vel_ds = f[f'{base_path}/Velocity Channel'][:] # Using channel velocity for EGL approx
        
        # 3. Identify Peak Flow Time Step
        # Find max flow at most downstream XS (index 0 usually upstream, check coordinates)
        # In RAS HDF, index 0 is usually downstream? Or Upstream?
        # Actually standard RAS array order matches River Stations order.
        # River stations are usually sorted downstream to upstream or vice versa.
        # We will assume index 0 is the first station in the list.
        # Let's find the max flow across the whole domain or specific DS.
        # Task says: "maximum at the most downstream cross section"
        # We need to know which one is downstream. 
        # Usually river stations are numeric. Lowest number = downstream.
        
        # Parse stations to float to find min
        try:
            stations_float = [float(x) for x in river_stations]
            ds_idx = np.argmin(stations_float) # Index of lowest station value
        except:
            ds_idx = -1 # Fallback to last index
            
        ds_flow_series = flow_ds[:, ds_idx]
        peak_step_idx = np.argmax(ds_flow_series)
        
        # 4. Compute EGL at Peak Step
        g = 32.174
        egls = []
        
        # Get values for peak step
        wses = wse_ds[peak_step_idx, :]
        vels = vel_ds[peak_step_idx, :]
        
        # Compute EGL = WSE + V^2/2g
        # Note: This is an approximation using channel velocity. 
        # RAS might store 'Energy Grade' directly. Let's check.
        if 'Energy Grade' in f[base_path]:
            egls = f[f'{base_path}/Energy Grade'][peak_step_idx, :]
        else:
            egls = wses + (vels**2) / (2*g)
            
        # 5. Compute Losses
        # We need to pair them. Assuming array order corresponds to river stations order.
        # Sort stations by value (High -> Low = Upstream -> Downstream)
        sorted_indices = np.argsort(stations_float)[::-1]
        
        gt_rows = []
        total_loss = 0.0
        max_loss = -999.0
        max_loss_pair = ""
        energy_slopes = []
        
        for i in range(len(sorted_indices) - 1):
            us_idx = sorted_indices[i]
            ds_idx = sorted_indices[i+1]
            
            us_st = river_stations[us_idx]
            ds_st = river_stations[ds_idx]
            
            # Reach length is associated with the upstream cross section?
            # In RAS, "Lengths" at index i usually distances to next XS downstream.
            reach_len = channel_lengths[us_idx]
            
            us_egl = float(egls[us_idx])
            ds_egl = float(egls[ds_idx])
            
            loss = us_egl - ds_egl
            if reach_len > 0:
                slope = loss / reach_len
            else:
                slope = 0.0
                
            gt_rows.append({
                "upstream_xs": us_st,
                "downstream_xs": ds_st,
                "loss": loss,
                "slope": slope
            })
            
            total_loss += loss
            energy_slopes.append(slope)
            
            if loss > max_loss:
                max_loss = loss
                max_loss_pair = f"{us_st}-{ds_st}"

        avg_slope = np.mean(energy_slopes) if energy_slopes else 0.0

        output = {
            "peak_time_step": int(peak_step_idx),
            "total_loss": float(total_loss),
            "max_loss": float(max_loss),
            "max_loss_pair": max_loss_pair,
            "avg_slope": float(avg_slope),
            "rows": gt_rows
        }
        
        with open("/tmp/ground_truth.json", "w") as jf:
            json.dump(output, jf, indent=2)
            
except Exception as e:
    error = {"error": str(e)}
    with open("/tmp/ground_truth.json", "w") as jf:
        json.dump(error, jf)
PYEOF

# Execute the ground truth generator
python3 /tmp/generate_ground_truth.py
echo "Ground truth generated at /tmp/ground_truth.json"


# --- 2. Check Agent Outputs ---

# Check CSV
CSV_EXISTS="false"
CSV_MODIFIED="false"
CSV_ROWS=0
if [ -f "$CSV_PATH" ]; then
    CSV_EXISTS="true"
    CSV_MTIME=$(stat -c %Y "$CSV_PATH" 2>/dev/null || echo "0")
    if [ "$CSV_MTIME" -gt "$TASK_START" ]; then
        CSV_MODIFIED="true"
    fi
    CSV_ROWS=$(wc -l < "$CSV_PATH" || echo "0")
fi

# Check Summary
SUMMARY_EXISTS="false"
SUMMARY_MODIFIED="false"
if [ -f "$SUMMARY_PATH" ]; then
    SUMMARY_EXISTS="true"
    SUMMARY_MTIME=$(stat -c %Y "$SUMMARY_PATH" 2>/dev/null || echo "0")
    if [ "$SUMMARY_MTIME" -gt "$TASK_START" ]; then
        SUMMARY_MODIFIED="true"
    fi
fi

# Check Script
SCRIPT_EXISTS="false"
if [ -f "$SCRIPT_PATH" ]; then
    SCRIPT_EXISTS="true"
fi


# --- 3. Take Final Screenshot ---
take_screenshot /tmp/task_final.png


# --- 4. Create Result JSON ---
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "csv_exists": $CSV_EXISTS,
    "csv_modified": $CSV_MODIFIED,
    "csv_rows": $CSV_ROWS,
    "csv_path": "$CSV_PATH",
    "summary_exists": $SUMMARY_EXISTS,
    "summary_modified": $SUMMARY_MODIFIED,
    "summary_path": "$SUMMARY_PATH",
    "script_exists": $SCRIPT_EXISTS,
    "screenshot_path": "/tmp/task_final.png",
    "ground_truth_path": "$GROUND_TRUTH_JSON"
}
EOF

# Move to standard location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="