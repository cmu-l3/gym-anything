#!/bin/bash
echo "=== Exporting compute_loop_rating_curve results ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

CSV_PATH="$RESULTS_DIR/loop_rating_summary.csv"
PLOT_PATH="$RESULTS_DIR/loop_rating_curves.png"
HDF_PATH="$MUNCIE_DIR/Muncie.p04.tmp.hdf"

# --- 1. Capture Final Screenshot ---
take_screenshot /tmp/task_final.png

# --- 2. Calculate Ground Truth (Hidden from Agent) ---
# We run a python script to calculate the actual loop widths from the HDF file
# to compare against the agent's submission.
echo "Calculating ground truth metrics..."
cat > /tmp/calc_ground_truth.py << 'EOF'
import h5py
import numpy as np
import json
import sys

try:
    hdf_path = sys.argv[1]
    
    with h5py.File(hdf_path, 'r') as f:
        # HEC-RAS HDF path structure
        # Geometry/Cross Sections/Attributes (to get RS)
        # Results/Unsteady/Output/Output Blocks/Base Output/Unsteady Time Series/Cross Sections/ (Stage, Flow)
        
        # 1. Get River Stations
        # Note: This path depends on specific RAS version HDF structure. 
        # For RAS 6.x usually: /Geometry/Cross Sections/Attributes
        # We need to find where river stations are stored. 
        # Often dataset "River Stations" under Attributes.
        
        # Fallback for structure exploration if needed, but assuming standard:
        rs_path = '/Geometry/Cross Sections/Attributes'
        if rs_path in f:
            rs_data = f[rs_path][:]
            # RS are usually byte strings in a compound type or array
            # Extract 'River Station' column if compound
            if rs_data.dtype.names and 'River Station' in rs_data.dtype.names:
                stations = [x.decode('utf-8').strip() for x in rs_data['River Station']]
            else:
                # Direct array
                stations = [x.decode('utf-8').strip() for x in rs_data]
        else:
            # Fallback: try to guess from results dimensions
            stations = [f"RS_{i}" for i in range(10)] # Dummy if failing
            
        # 2. Get Data
        base_path = '/Results/Unsteady/Output/Output Blocks/Base Output/Unsteady Time Series/Cross Sections'
        stage_ds = f[f'{base_path}/Water Surface'][:]
        flow_ds = f[f'{base_path}/Flow'][:]
        
        # Transpose if needed: RAS results usually (Time, Node)
        # Check shape
        num_times, num_nodes = stage_ds.shape
        
        indices = [0, num_nodes // 2, num_nodes - 1]
        results = []
        
        for idx in indices:
            rs = stations[idx] if idx < len(stations) else f"Index_{idx}"
            pos = "upstream" if idx == 0 else ("downstream" if idx == num_nodes - 1 else "middle")
            
            s = stage_ds[:, idx]
            q = flow_ds[:, idx]
            
            peak_idx = np.argmax(q)
            peak_flow = float(q[peak_idx])
            peak_stage = float(s[peak_idx])
            
            # Simple loop width calc
            # Interpolate rising and falling to common stage grid
            s_rise = s[:peak_idx]
            q_rise = q[:peak_idx]
            s_fall = s[peak_idx:]
            q_fall = q[peak_idx:]
            
            # Determine overlapping stage range
            min_s = max(np.min(s_rise), np.min(s_fall))
            max_s = min(np.max(s_rise), np.max(s_fall))
            
            max_width = 0.0
            
            if min_s < max_s:
                # Create grid
                s_grid = np.linspace(min_s, max_s, 100)
                # Sort for interp (stage must be monotonic for interp, usually is on limbs)
                # Check monotonicity
                
                # Simple robust approach: for every point on rising, find closest on falling
                # Better: clean interp
                try:
                    # Sort rising by stage
                    sort_r = np.argsort(s_rise)
                    q_rise_interp = np.interp(s_grid, s_rise[sort_r], q_rise[sort_r])
                    
                    # Sort falling by stage
                    sort_f = np.argsort(s_fall)
                    q_fall_interp = np.interp(s_grid, s_fall[sort_f], q_fall[sort_f])
                    
                    diff = np.abs(q_rise_interp - q_fall_interp)
                    max_width = float(np.max(diff))
                except:
                    max_width = 0.0
            
            results.append({
                "river_station": rs,
                "position": pos,
                "peak_flow": peak_flow,
                "peak_stage": peak_stage,
                "max_loop_width": max_width
            })
            
    print(json.dumps(results))

except Exception as e:
    print(json.dumps({"error": str(e)}))
EOF

GROUND_TRUTH_JSON=$(python3 /tmp/calc_ground_truth.py "$HDF_PATH")


# --- 3. Check Agent CSV ---
CSV_EXISTS="false"
CSV_CREATED_DURING="false"
CSV_CONTENT=""

if [ -f "$CSV_PATH" ]; then
    CSV_EXISTS="true"
    if [ "$(stat -c %Y "$CSV_PATH")" -gt "$TASK_START" ]; then
        CSV_CREATED_DURING="true"
    fi
    # Read CSV to JSON
    CSV_CONTENT=$(python3 -c "import pandas as pd; import json; print(pd.read_csv('$CSV_PATH').to_json(orient='records'))" 2>/dev/null || echo "[]")
fi

# --- 4. Check Agent Plot ---
PLOT_EXISTS="false"
PLOT_CREATED_DURING="false"
PLOT_SIZE="0"

if [ -f "$PLOT_PATH" ]; then
    PLOT_EXISTS="true"
    PLOT_SIZE=$(stat -c %s "$PLOT_PATH")
    if [ "$(stat -c %Y "$PLOT_PATH")" -gt "$TASK_START" ]; then
        PLOT_CREATED_DURING="true"
    fi
fi

# --- 5. Create Result JSON ---
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "csv_exists": $CSV_EXISTS,
    "csv_created_during_task": $CSV_CREATED_DURING,
    "csv_content": $CSV_CONTENT,
    "plot_exists": $PLOT_EXISTS,
    "plot_created_during_task": $PLOT_CREATED_DURING,
    "plot_size": $PLOT_SIZE,
    "ground_truth": $GROUND_TRUTH_JSON,
    "final_screenshot": "/tmp/task_final.png"
}
EOF

# Move to standard location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="