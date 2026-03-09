#!/bin/bash
echo "=== Exporting Audit Kinematic Wave Assumption Results ==="

source /workspace/scripts/task_utils.sh

# 1. Parameters
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
OUTPUT_CSV="/home/ga/Documents/hec_ras_results/kinematic_wave_audit.csv"
HDF_FILE="/home/ga/Documents/hec_ras_projects/Muncie/Muncie.p04.hdf"
TMP_HDF_FILE="/home/ga/Documents/hec_ras_projects/Muncie/Muncie.p04.tmp.hdf"

# 2. Check for HDF file (Agent might have left it as .tmp.hdf)
if [ ! -f "$HDF_FILE" ] && [ -f "$TMP_HDF_FILE" ]; then
    echo "Found temporary HDF file, using that..."
    HDF_FILE="$TMP_HDF_FILE"
fi

# 3. Generate Ground Truth INSIDE container
# We do this here to use the container's environment (h5py, rashdf)
# independent of the host verifier environment.
echo "Generating ground truth data..."
cat > /tmp/gen_ground_truth.py << 'PYEOF'
import h5py
import numpy as np
import json
import sys
import os

hdf_path = sys.argv[1]
output_path = "/tmp/ground_truth.json"

result = {
    "hdf_exists": False,
    "peak_time_index": -1,
    "upstream_station": None,
    "peak_flow": 0.0,
    "data": []
}

if not os.path.exists(hdf_path):
    with open(output_path, 'w') as f:
        json.dump(result, f)
    sys.exit(0)

try:
    with h5py.File(hdf_path, 'r') as f:
        result["hdf_exists"] = True
        
        # 1. Get Geometry Info
        # Note: Path structures vary slightly by version, trying standard RAS 6.x paths
        geom_path = '/Geometry/Cross Sections'
        res_path = '/Results/Unsteady/Output/Output Blocks/Base Output/Unsteady Time Series/Cross Sections'
        
        # Get Station Names/Values
        # Station identifiers are usually stored as strings in 'River Stations'
        # But for indexing, we often assume 1:1 mapping with data arrays
        
        # Get Flow to find peak at Upstream
        # Upstream is usually index 0 or index -1 depending on sorting. 
        # HEC-RAS usually sorts downstream, so Upstream is index 0? 
        # Actually, let's check River Station values.
        
        # Load River Stations
        rs_data = f[f'{geom_path}/Identifier'][()]
        river_stations = [x.decode('utf-8').strip() for x in rs_data]
        
        # HEC-RAS convention: Higher river station = Upstream
        # Let's find the index of the max numeric value of river station
        try:
            rs_floats = [float(x) for x in river_stations]
            upstream_idx = np.argmax(rs_floats)
        except:
            upstream_idx = 0 # Fallback
            
        result["upstream_station"] = river_stations[upstream_idx]
        
        # Get Flow at Upstream
        flow_ds = f[f'{res_path}/Flow']
        # flow_ds shape is usually (Time, CrossSection)
        flow_ts = flow_ds[:, upstream_idx]
        
        # Find peak time index
        peak_idx = np.argmax(flow_ts)
        result["peak_time_index"] = int(peak_idx)
        result["peak_flow"] = float(flow_ts[peak_idx])
        
        # 2. Extract WSE and Bed at Peak Time
        wse_ds = f[f'{res_path}/Water Surface']
        wse_snapshot = wse_ds[peak_idx, :]
        
        # Extract Bed Elevation (Thalweg)
        # Often in /Geometry/Cross Sections/Station Elevation Info -> min values
        # Or sometimes simplified in results
        # We'll calculate min from Station-Elevation pairs if needed, 
        # but let's look for Minimum Elevation info.
        # Fallback: Attributes table
        
        bed_elevs = []
        if 'Minimum Elevation' in f[f'{geom_path}/Attributes'].dtype.names:
            bed_elevs = f[f'{geom_path}/Attributes']['Minimum Elevation']
        else:
            # Fallback calculation if attribute not found (unlikely in 6.6)
            bed_elevs = np.zeros(len(river_stations))
            
        # 3. Calculate Slopes between consecutive sections
        # We need to sort by River Station (Upstream -> Downstream)
        # Create pairs (index, rs_float)
        pairs = []
        for i, rs in enumerate(river_stations):
            try:
                val = float(rs)
            except:
                val = 0
            pairs.append((i, val))
            
        # Sort descending (Upstream first)
        pairs.sort(key=lambda x: x[1], reverse=True)
        
        sorted_indices = [p[0] for p in pairs]
        
        # Reach lengths usually in Attributes 'Reach Length' (Channel)
        reach_lengths = f[f'{geom_path}/Attributes']['Reach Length'] 
        # Note: Reach length at index i is distance to i+1 (downstream)
        
        computed_data = []
        
        for i in range(len(sorted_indices) - 1):
            curr_idx = sorted_indices[i]
            next_idx = sorted_indices[i+1]
            
            curr_rs = river_stations[curr_idx]
            next_rs = river_stations[next_idx]
            
            # Distance
            dist = float(reach_lengths[curr_idx])
            if dist <= 0: dist = 1.0 # Avoid div/0 if bad data
            
            # Bed Slope
            z1 = float(bed_elevs[curr_idx])
            z2 = float(bed_elevs[next_idx])
            s0 = (z1 - z2) / dist
            
            # WSE Slope
            w1 = float(wse_snapshot[curr_idx])
            w2 = float(wse_snapshot[next_idx])
            sw = (w1 - w2) / dist
            
            ratio = sw / s0 if abs(s0) > 1e-6 else 0.0
            
            computed_data.append({
                "upstream": curr_rs,
                "downstream": next_rs,
                "dist": dist,
                "s0": s0,
                "sw": sw,
                "ratio": ratio
            })
            
        result["data"] = computed_data

except Exception as e:
    result["error"] = str(e)

with open(output_path, 'w') as f:
    json.dump(result, f, indent=2)
PYEOF

# Run the ground truth generator
python3 /tmp/gen_ground_truth.py "$HDF_FILE"

# 4. Check outputs
CSV_EXISTS="false"
CSV_MODIFIED="false"
if [ -f "$OUTPUT_CSV" ]; then
    CSV_EXISTS="true"
    F_TIME=$(stat -c %Y "$OUTPUT_CSV")
    if [ "$F_TIME" -gt "$TASK_START" ]; then
        CSV_MODIFIED="true"
    fi
fi

SIM_RUN="false"
if [ -f "$HDF_FILE" ]; then
    SIM_RUN="true"
fi

# 5. Take final screenshot
take_screenshot /tmp/task_final.png

# 6. Prepare result JSON
# We include paths to the generated ground truth and user csv
# These will be copied out by the verifier
cat > /tmp/task_result.json << EOF
{
    "task_start": $TASK_START,
    "csv_exists": $CSV_EXISTS,
    "csv_modified": $CSV_MODIFIED,
    "simulation_run": $SIM_RUN,
    "csv_path": "$OUTPUT_CSV",
    "ground_truth_path": "/tmp/ground_truth.json",
    "hdf_path": "$HDF_FILE",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Ensure permissions
chmod 666 /tmp/task_result.json /tmp/ground_truth.json 2>/dev/null || true
if [ -f "$OUTPUT_CSV" ]; then chmod 666 "$OUTPUT_CSV"; fi

echo "Result export complete."
cat /tmp/task_result.json