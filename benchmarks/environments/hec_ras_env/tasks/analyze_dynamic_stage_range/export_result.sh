#!/bin/bash
echo "=== Exporting analyze_dynamic_stage_range results ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
RESULTS_DIR="/home/ga/Documents/hec_ras_results"
MUNCIE_HDF="/home/ga/Documents/hec_ras_projects/Muncie/Muncie.p04.hdf"

# --- 1. Capture Final Screenshot ---
take_screenshot /tmp/task_final.png

# --- 2. Generate Ground Truth (server-side calculation) ---
# We calculate the true values from the HDF file now to compare against agent output
echo "Generating ground truth from HDF5 file..."

cat > /tmp/generate_ground_truth.py << 'EOF'
import h5py
import numpy as np
import json
import sys

try:
    with h5py.File(sys.argv[1], 'r') as f:
        # Paths in HEC-RAS 6.6 HDF5
        # Note: These paths are standard for Unsteady plans
        # Geometry
        geom_path = 'Geometry/Cross Sections/Attributes'
        results_path = 'Results/Unsteady/Output/Output Blocks/Base Output/Unsteady Time Series/Cross Sections'
        
        # Get River Stations
        # River stations are typically stored as bytes/strings in Attributes
        river_stations = []
        if geom_path in f:
            rs_data = f[geom_path][:]
            # RS is typically the 3rd column or named 'RS'
            # Let's try to find the 'RS' name in dtype
            if 'RS' in rs_data.dtype.names:
                 river_stations = [rs.decode('utf-8') for rs in rs_data['RS']]
            else:
                 # Fallback to index if needed, but names are safer
                 pass
        
        # Get WSE Data (Time x CrossSection)
        wse_path = f"{results_path}/Water Surface"
        if wse_path in f:
            wse_data = f[wse_path][:] # Shape: (Time, Node)
            
            # Compute Stats
            min_wse = np.min(wse_data, axis=0)
            max_wse = np.max(wse_data, axis=0)
            fluctuation = max_wse - min_wse
            
            # Identify Max Fluctuation
            max_fluc_idx = np.argmax(fluctuation)
            max_fluc_val = float(fluctuation[max_fluc_idx])
            critical_station = river_stations[max_fluc_idx] if river_stations else str(max_fluc_idx)
            
            # Sample data for verification (first, middle, last)
            indices = [0, len(fluctuation)//2, len(fluctuation)-1]
            sample_stats = []
            for idx in indices:
                rs = river_stations[idx] if river_stations else str(idx)
                sample_stats.append({
                    "station": rs,
                    "min": float(min_wse[idx]),
                    "max": float(max_wse[idx]),
                    "range": float(fluctuation[idx])
                })
                
            output = {
                "status": "success",
                "critical_station": critical_station,
                "max_fluctuation": max_fluc_val,
                "samples": sample_stats,
                "total_sections": len(fluctuation)
            }
        else:
            output = {"status": "error", "message": "WSE path not found"}

    with open('/tmp/ground_truth.json', 'w') as jf:
        json.dump(output, jf, indent=2)

except Exception as e:
    with open('/tmp/ground_truth.json', 'w') as jf:
        json.dump({"status": "error", "message": str(e)}, jf)
EOF

python3 /tmp/generate_ground_truth.py "$MUNCIE_HDF"

# --- 3. Check User Outputs ---

# CSV check
CSV_PATH="$RESULTS_DIR/stage_fluctuation_summary.csv"
CSV_EXISTS="false"
CSV_CREATED_DURING="false"
if [ -f "$CSV_PATH" ]; then
    CSV_EXISTS="true"
    CSV_MTIME=$(stat -c %Y "$CSV_PATH")
    if [ "$CSV_MTIME" -gt "$TASK_START" ]; then
        CSV_CREATED_DURING="true"
    fi
fi

# TXT check
TXT_PATH="$RESULTS_DIR/max_fluctuation_location.txt"
TXT_EXISTS="false"
if [ -f "$TXT_PATH" ]; then TXT_EXISTS="true"; fi

# Plot check
PLOT_PATH="$RESULTS_DIR/wse_envelope_plot.png"
PLOT_EXISTS="false"
PLOT_SIZE="0"
if [ -f "$PLOT_PATH" ]; then 
    PLOT_EXISTS="true"
    PLOT_SIZE=$(stat -c %s "$PLOT_PATH")
fi

# --- 4. Package Results ---
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "csv_exists": $CSV_EXISTS,
    "csv_created_during_task": $CSV_CREATED_DURING,
    "txt_exists": $TXT_EXISTS,
    "plot_exists": $PLOT_EXISTS,
    "plot_size": $PLOT_SIZE,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move files to temp for verification (to avoid permission issues)
# We copy the user's result files to /tmp so the verifier can read them easily via copy_from_env
if [ -f "$CSV_PATH" ]; then cp "$CSV_PATH" /tmp/agent_summary.csv; chmod 666 /tmp/agent_summary.csv; fi
if [ -f "$TXT_PATH" ]; then cp "$TXT_PATH" /tmp/agent_location.txt; chmod 666 /tmp/agent_location.txt; fi
if [ -f "$PLOT_PATH" ]; then cp "$PLOT_PATH" /tmp/agent_plot.png; chmod 666 /tmp/agent_plot.png; fi

# Save final result JSON
rm -f /tmp/task_result.json 2>/dev/null
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "=== Export complete ==="