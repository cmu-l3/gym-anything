#!/bin/bash
echo "=== Exporting estimate_bankfull_capacity results ==="

source /workspace/scripts/task_utils.sh

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Check output file status
OUTPUT_CSV="/home/ga/Documents/hec_ras_results/bankfull_capacity.csv"
OUTPUT_EXISTS="false"
if [ -f "$OUTPUT_CSV" ]; then
    OUTPUT_EXISTS="true"
    # Copy to /tmp for easier extraction if needed, though verifier pulls directly
    cp "$OUTPUT_CSV" /tmp/agent_output.csv
fi

# 3. Check if agent created a script (Process verification)
SCRIPT_COUNT=$(find /home/ga/Documents/hec_ras_results -name "*.py" -newer /tmp/task_start_time.txt 2>/dev/null | wc -l)

# 4. GENERATE GROUND TRUTH
# We run a trusted Python script INSIDE the container to calculate the correct values
# from the exact HDF5 file present. This ensures perfect alignment with the data.

echo "Generating ground truth data..."
cat > /tmp/generate_ground_truth.py << 'EOF'
import h5py
import numpy as np
import json
import os

try:
    project_dir = "/home/ga/Documents/hec_ras_projects/Muncie"
    # Find the HDF file (p04.tmp.hdf or p04.hdf)
    hdf_files = [f for f in os.listdir(project_dir) if f.endswith('.hdf') and '.p' in f]
    if not hdf_files:
        print(json.dumps({"error": "No HDF file found"}))
        exit(0)
    
    # Prefer the temp file if it exists (fresh run), else the result file
    target_file = next((f for f in hdf_files if 'tmp' in f), hdf_files[0])
    hdf_path = os.path.join(project_dir, target_file)
    
    ground_truth = []
    
    with h5py.File(hdf_path, 'r') as f:
        # Paths for HEC-RAS 6.x HDF format
        
        # 1. Geometry: Cross Section info
        geom_path = '/Geometry/Cross Sections'
        if geom_path not in f:
            # Fallback for some versions
            geom_path = '/Geometry/Cross Sections' 
            
        # Identifiers
        rs_objs = f[f'{geom_path}/Identifier'][()]
        river_stations = [x.decode('utf-8').strip() for x in rs_objs]
        
        # Bank Stations (X coordinates) [Left, Right]
        bank_stations = f[f'{geom_path}/Bank Stations'][()]
        
        # Station Elevation Info (Start Index, Count)
        se_info = f[f'{geom_path}/Station Elevation Info'][()]
        
        # Station Elevation Values (Table of X, Z)
        se_values = f[f'{geom_path}/Station Elevation Values'][()]
        
        # 2. Results: Unsteady
        res_path = '/Results/Unsteady/Output/Output Blocks/Base Output/Unsteady Time Series/Cross Sections'
        wse_data = f[f'{res_path}/Water Surface'][()]
        flow_data = f[f'{res_path}/Flow'][()]
        
        for idx, rs in enumerate(river_stations):
            # --- Geometry Analysis ---
            left_bank_x = bank_stations[idx][0]
            right_bank_x = bank_stations[idx][1]
            
            # Extract SE curve for this XS
            start_idx = se_info[idx][0]
            count = se_info[idx][1]
            xs_se = se_values[start_idx : start_idx + count]
            
            # Interpolate Z for Bank X
            # xs_se[:,0] is X (Station), xs_se[:,1] is Z (Elevation)
            left_bank_z = np.interp(left_bank_x, xs_se[:,0], xs_se[:,1])
            right_bank_z = np.interp(right_bank_x, xs_se[:,0], xs_se[:,1])
            
            min_bank_elev = min(left_bank_z, right_bank_z)
            
            # --- Hydrograph Analysis ---
            wse_ts = wse_data[:, idx]
            flow_ts = flow_data[:, idx]
            max_wse = np.max(wse_ts)
            
            bankfull_q = 0.0
            
            if max_wse > min_bank_elev:
                # Find rising limb crossing
                # Condition: wse[i] < thresh AND wse[i+1] >= thresh
                crossings = np.where((wse_ts[:-1] < min_bank_elev) & (wse_ts[1:] >= min_bank_elev))[0]
                
                if len(crossings) > 0:
                    i = crossings[0]
                    # Linear interpolation for Q
                    wse1, wse2 = wse_ts[i], wse_ts[i+1]
                    flow1, flow2 = flow_ts[i], flow_ts[i+1]
                    
                    if wse2 != wse1:
                        fraction = (min_bank_elev - wse1) / (wse2 - wse1)
                        bankfull_q = flow1 + fraction * (flow2 - flow1)
                    else:
                        bankfull_q = flow1
            
            ground_truth.append({
                "RiverStation": rs,
                "Min_Bank_Elev_ft": float(min_bank_elev),
                "Bankfull_Q_cfs": float(bankfull_q),
                "Max_WSE_ft": float(max_wse)
            })
            
    print(json.dumps(ground_truth))

except Exception as e:
    print(json.dumps({"error": str(e)}))
EOF

# Execute ground truth generation
python3 /tmp/generate_ground_truth.py > /tmp/ground_truth.json 2> /tmp/gt_gen.log

# 5. Create final result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "output_exists": $OUTPUT_EXISTS,
    "script_count": $SCRIPT_COUNT,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Save to public location
rm -f /tmp/task_result.json 2>/dev/null
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "=== Export complete ==="