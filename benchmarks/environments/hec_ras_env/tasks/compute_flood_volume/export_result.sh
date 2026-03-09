#!/bin/bash
echo "=== Exporting compute_flood_volume results ==="

source /workspace/scripts/task_utils.sh

# Paths
SCRIPT_PATH="/home/ga/Documents/analysis_scripts/compute_flood_volume.py"
REPORT_PATH="/home/ga/Documents/hec_ras_results/flood_volume_report.txt"
HDF_FILE="/home/ga/Documents/hec_ras_projects/Muncie/Muncie.p04.hdf"

# 1. Check file existence
SCRIPT_EXISTS="false"
[ -f "$SCRIPT_PATH" ] && SCRIPT_EXISTS="true"

REPORT_EXISTS="false"
[ -f "$REPORT_PATH" ] && REPORT_EXISTS="true"

# 2. Check if script is valid Python (syntax check)
SCRIPT_VALID="false"
if [ "$SCRIPT_EXISTS" = "true" ]; then
    if python3 -m py_compile "$SCRIPT_PATH" 2>/dev/null; then
        SCRIPT_VALID="true"
    fi
fi

# 3. Check imports
IMPORTS_H5PY="false"
if [ "$SCRIPT_EXISTS" = "true" ]; then
    if grep -q "import h5py" "$SCRIPT_PATH" || grep -q "from h5py" "$SCRIPT_PATH"; then
        IMPORTS_H5PY="true"
    fi
fi

# 4. Read Agent's Report Content
AGENT_PEAK_IDX="-1"
AGENT_XS_COUNT="-1"
AGENT_VOL_FT3="-1.0"
AGENT_VOL_M3="-1.0"

if [ "$REPORT_EXISTS" = "true" ]; then
    # Simple extraction logic: looks for numbers in lines containing keywords
    # Index
    AGENT_PEAK_IDX=$(grep -i "Index" "$REPORT_PATH" | grep -oE '[0-9]+' | head -1 || echo "-1")
    # Count
    AGENT_XS_COUNT=$(grep -i "Cross Section" "$REPORT_PATH" | grep -oE '[0-9]+' | head -1 || echo "-1")
    # Volume ft3 (looks for floating point number on line with feet/ft)
    AGENT_VOL_FT3=$(grep -i "feet" "$REPORT_PATH" | grep -oE '[0-9]+\.?[0-9]*' | head -1 || echo "-1.0")
    # Volume m3 (looks for floating point number on line with meters)
    AGENT_VOL_M3=$(grep -i "meters" "$REPORT_PATH" | grep -oE '[0-9]+\.?[0-9]*' | head -1 || echo "-1.0")
fi

# 5. Calculate Ground Truth (Run a hidden verification script inside container)
# We calculate it here to avoid copying the large HDF5 file to the verifier host
echo "Calculating ground truth..."

cat > /tmp/calc_ground_truth.py << 'EOF'
import h5py
import numpy as np
import sys
import json

try:
    hdf_path = "/home/ga/Documents/hec_ras_projects/Muncie/Muncie.p04.hdf"
    
    with h5py.File(hdf_path, 'r') as f:
        # Paths typically found in RAS 6.x Unsteady Output
        # Try common paths for Flow Area
        area_path = None
        possible_area_paths = [
            '/Results/Unsteady/Output/Output Blocks/Base Output/Unsteady Time Series/Cross Sections/Flow Area',
            '/Results/Unsteady/Output/Output Blocks/DSS Hydrograph Output/Unsteady Time Series/Cross Sections/Flow Area'
        ]
        
        for p in possible_area_paths:
            if p in f:
                area_path = p
                break
        
        if not area_path:
            print(json.dumps({"error": "Flow Area path not found"}))
            sys.exit(0)
            
        # Try common paths for Lengths
        # Lengths are usually in Geometry/Cross Sections/Lengths or Attributes
        # Lengths table usually has columns: LOB, Channel, ROB. Index 1 is Channel.
        length_path = None
        possible_len_paths = [
            '/Geometry/Cross Sections/Lengths',
            '/Geometry/Cross Sections/Attributes' # Sometimes here in older versions
        ]
        
        for p in possible_len_paths:
            if p in f:
                length_path = p
                break

        if not length_path:
            # Fallback: Assume constant distance if not found (unlikely for Muncie)
            print(json.dumps({"error": "Lengths path not found"}))
            sys.exit(0)

        # Read Data
        # Area: Time x CrossSection
        flow_areas = f[area_path][:] 
        
        # Lengths: CrossSection x 3 (LOB, Channel, ROB)
        # We need downstream lengths. In RAS HDF, 'Lengths' usually stores length to next XS.
        lengths_data = f[length_path][:]
        
        # Check shape to identify channel column (usually index 1)
        if lengths_data.ndim == 2 and lengths_data.shape[1] >= 2:
            reach_lengths = lengths_data[:, 1] # Main Channel
        else:
            reach_lengths = lengths_data # Assume 1D array if that's what it is

        # Verify shapes match (Flow Area XS dimension vs Lengths XS dimension)
        # flow_areas.shape is (Time, XS)
        num_xs = flow_areas.shape[1]
        
        # Compute Total Volume at each time step
        # Volume = Sum over reaches of (A_upstream + A_downstream)/2 * L
        # Note: lengths[i] is typically length from XS[i] to XS[i-1] or XS[i+1]. 
        # In RAS: XS are ordered upstream to downstream. 
        # Length at index i is distance to the *next* downstream cross section.
        # The last XS usually has length 0.
        
        # We need to perform operation along the XS axis (axis 1)
        # V_t = Sum_i ( (A_t,i + A_t,i+1)/2 * L_i )
        
        # Vectorized trapezoidal integration across XS dimension
        A_upstream = flow_areas[:, :-1]
        A_downstream = flow_areas[:, 1:]
        L_reach = reach_lengths[:-1] # Exclude last XS length (usually 0)
        
        # Adjust shapes if necessary
        if L_reach.shape[0] != A_upstream.shape[1]:
            # Fallback for shape mismatch
             print(json.dumps({"error": f"Shape mismatch: Area {A_upstream.shape}, Len {L_reach.shape}"}))
             sys.exit(0)

        segment_volumes = 0.5 * (A_upstream + A_downstream) * L_reach
        total_storage_time_series = np.sum(segment_volumes, axis=1)
        
        # Find Peak
        peak_idx = int(np.argmax(total_storage_time_series))
        peak_vol_ft3 = float(total_storage_time_series[peak_idx])
        peak_vol_m3 = peak_vol_ft3 * 0.0283168
        
        result = {
            "gt_peak_idx": peak_idx,
            "gt_xs_count": num_xs,
            "gt_vol_ft3": peak_vol_ft3,
            "gt_vol_m3": peak_vol_m3,
            "success": True
        }
        print(json.dumps(result))

except Exception as e:
    print(json.dumps({"error": str(e), "success": False}))
EOF

GT_JSON=$(python3 /tmp/calc_ground_truth.py)

# 6. Take final screenshot
take_screenshot /tmp/task_final.png

# 7. Create Result JSON
cat > /tmp/task_result.json << EOF
{
    "script_exists": $SCRIPT_EXISTS,
    "script_valid": $SCRIPT_VALID,
    "imports_h5py": $IMPORTS_H5PY,
    "report_exists": $REPORT_EXISTS,
    "agent_data": {
        "peak_idx": $AGENT_PEAK_IDX,
        "xs_count": $AGENT_XS_COUNT,
        "vol_ft3": $AGENT_VOL_FT3,
        "vol_m3": $AGENT_VOL_M3
    },
    "ground_truth": $GT_JSON,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Output for logging
cat /tmp/task_result.json
echo "=== Export complete ==="