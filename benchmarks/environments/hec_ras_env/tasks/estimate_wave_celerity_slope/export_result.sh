#!/bin/bash
echo "=== Exporting estimate_wave_celerity_slope results ==="

source /workspace/scripts/task_utils.sh

# 1. Capture final state
take_screenshot /tmp/task_final.png

# 2. Paths
CSV_PATH="/home/ga/Documents/hec_ras_results/celerity_data.csv"
REPORT_PATH="/home/ga/Documents/hec_ras_results/celerity_analysis.txt"
HDF_PATH="$MUNCIE_DIR/Muncie.p04.hdf"

# 3. Check for output files
CSV_EXISTS="false"
REPORT_EXISTS="false"
CSV_SIZE="0"

if [ -f "$CSV_PATH" ]; then
    CSV_EXISTS="true"
    CSV_SIZE=$(stat -c %s "$CSV_PATH")
fi

if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
fi

# 4. Generate Ground Truth (Internal)
# We run a python script inside the container to calculate the correct values
# from the HDF file. This avoids dependency issues on the verifier host.
cat > /tmp/gen_ground_truth.py << 'EOF'
import h5py
import numpy as np
import json
import scipy.stats

try:
    # Load HDF
    f = h5py.File('/home/ga/Documents/hec_ras_projects/Muncie/Muncie.p04.hdf', 'r')
    
    # Path to results (standard HEC-RAS 6.x structure)
    base_path = 'Results/Unsteady/Output/Output Blocks/Base Output/Unsteady Time Series/Cross Sections'
    
    # Find station 15781.9
    # Station names are often stored as attributes or in a separate dataset
    # We'll search for the index
    
    # Get station names (2D array of byte strings)
    try:
        # Try finding station names in geometry definition first to map to index
        geom_path = 'Geometry/Cross Sections/Attributes'
        station_names = f[geom_path]['River Station'][:]
        target = b'15781.9'
        idx = -1
        for i, name in enumerate(station_names):
            if target in name or name == target:
                idx = i
                break
    except:
        # Fallback: assume it's one of the upstream ones if specific lookup fails
        # 15781.9 is usually near index 3 or 4 in Muncie demo
        idx = 4 

    if idx == -1:
        # Fallback for demo stability
        idx = 4

    # Extract Data
    # Shape is typically (Time, Station)
    flow_ds = f[f'{base_path}/Flow']
    area_ds = f[f'{base_path}/Flow Area']
    
    flow = flow_ds[:, idx]
    area = area_ds[:, idx]
    
    # Logic to isolate rising limb
    peak_idx = np.argmax(flow)
    
    # Find start: look backwards from peak for flow < 100 or min flow
    start_idx = 0
    for i in range(peak_idx, 0, -1):
        if flow[i] < 100:
            start_idx = i
            break
            
    # Rising limb slice
    Q_rise = flow[start_idx:peak_idx+1]
    A_rise = area[start_idx:peak_idx+1]
    
    # Calculate Celerity (Slope of Q vs A)
    slope, intercept, r_value, p_value, std_err = scipy.stats.linregress(A_rise, Q_rise)
    celerity = slope
    
    # Calculate Mean Velocity
    # Avoid divide by zero
    mask = A_rise > 0
    velocities = Q_rise[mask] / A_rise[mask]
    mean_velocity = np.mean(velocities)
    
    result = {
        "ground_truth_calculated": True,
        "celerity": float(celerity),
        "mean_velocity": float(mean_velocity),
        "ratio": float(celerity / mean_velocity),
        "rising_limb_points": int(len(Q_rise)),
        "peak_flow": float(np.max(Q_rise))
    }
    
except Exception as e:
    result = {
        "ground_truth_calculated": False,
        "error": str(e)
    }

with open('/tmp/ground_truth.json', 'w') as f:
    json.dump(result, f)
EOF

# Run the ground truth generator
python3 /tmp/gen_ground_truth.py 2>/dev/null || true

# 5. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "timestamp": "$(date -Iseconds)",
    "csv_exists": $CSV_EXISTS,
    "csv_size": $CSV_SIZE,
    "report_exists": $REPORT_EXISTS,
    "csv_path": "$CSV_PATH",
    "report_path": "$REPORT_PATH",
    "ground_truth_path": "/tmp/ground_truth.json",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# 6. Move to shared location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"