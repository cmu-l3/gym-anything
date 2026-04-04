#!/bin/bash
set -e
echo "=== Exporting compute_cumulative_erosive_impulse results ==="

source /workspace/scripts/task_utils.sh

# Paths
RESULTS_DIR="/home/ga/Documents/hec_ras_results"
CSV_FILE="$RESULTS_DIR/erosion_impulse.csv"
SUMMARY_FILE="$RESULTS_DIR/erosion_summary.txt"
PLOT_FILE="$RESULTS_DIR/critical_shear_plot.png"
HDF_FILE="/home/ga/Documents/hec_ras_projects/Muncie/Muncie.p04.hdf"
GT_JSON="/tmp/ground_truth.json"

# Record timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot
take_screenshot /tmp/task_final.png

# --- GENERATE GROUND TRUTH ---
# We run a trusted python script INSIDE the container to calculate the expected values
# from the ACTUAL HDF file present. This handles version differences or simulation slight variations.
cat << 'EOF' > /tmp/gen_ground_truth.py
import h5py
import numpy as np
import json
import os
import sys

hdf_path = "/home/ga/Documents/hec_ras_projects/Muncie/Muncie.p04.hdf"
threshold = 0.03

if not os.path.exists(hdf_path):
    print(json.dumps({"error": "HDF file not found"}))
    sys.exit(0)

try:
    with h5py.File(hdf_path, 'r') as f:
        # Paths based on standard HEC-RAS HDF structure
        # Note: Paths might vary slightly by version, using likely 6.x paths
        results_base = f['Results/Unsteady/Output/Output Blocks/Base Output/Unsteady Time Series/Cross Sections']
        
        # Get River Stations
        # Geometry usually stores stations, but results link them too.
        # Often mapped via attributes or explicit datasets. 
        # For this ground truth, we'll try to get them from Geometry if available, or just index.
        # Actually, let's look at the mapping in 'Geometry/Cross Sections/River Stations'
        geom_base = f['Geometry/Cross Sections']
        river_stations = geom_base['River Stations'][()].astype(str)
        
        # Get Shear Stress (Channel)
        # Dataset shape: (Time, CrossSection) or similar
        # Validating dataset name... usually 'Shear Stress'
        shear_ds = results_base['Shear Stress']
        shear_data = shear_ds[()] # Load into memory
        
        # Get Time info to calculate dt
        # Time usually in 'Results/Unsteady/Output/Output Blocks/Base Output/Unsteady Time Series/Time Date Stamp'
        # Or we assume fixed step if we can't parse strings easily.
        # Let's rely on the simulation interval. 
        # Alternative: look at 'Unsteady Time Series/2D Flow Areas/.../Time' if 2D, 
        # but this is 1D Muncie.
        # Simple approach: The Muncie example usually has 1 hour or 15 min steps. 
        # Let's calculate dt from the 'Time' dataset if it exists (usually hours since start).
        # Note: HEC-RAS often stores time as strings.
        # Let's assume a standard dt or try to find 'Time Step' attribute.
        # For Muncie default, it's often 1 hour output interval.
        # Let's try to infer from data shape vs simulation duration? 
        # Safer: Just set dt = 1.0 hr if we can't find it, but let's try.
        dt = 1.0 # Default fallback
        
        # Calculation
        # shear_data shape is likely (Time, Station)
        # We need Channel Shear. The dataset 'Shear Stress' in XS results usually has columns 
        # for LOB, Channel, ROB? Or just average?
        # Actually 'Shear Stress' under XS is typically the channel shear or average. 
        # Let's assume the dataset is simple (Time, Station).
        
        # Calculate Impulse
        # excess = max(shear - 0.03, 0)
        excess = np.maximum(shear_data - threshold, 0)
        
        # Integrate: sum * dt
        # simple rectangular integration
        impulse = np.sum(excess, axis=0) * dt
        
        # Find critical
        max_idx = np.argmax(impulse)
        crit_rs = river_stations[max_idx]
        crit_val = impulse[max_idx]
        
        # Create dictionary of RS -> Impulse for verification
        rs_impulse_map = {rs: float(val) for rs, val in zip(river_stations, impulse)}
        
        output = {
            "critical_station": str(crit_rs),
            "critical_impulse": float(crit_val),
            "station_data": rs_impulse_map,
            "error": None
        }
        print(json.dumps(output))

except Exception as e:
    print(json.dumps({"error": str(e)}))
EOF

# Run Ground Truth Generator
python3 /tmp/gen_ground_truth.py > "$GT_JSON" 2>/dev/null || echo '{"error": "Failed to run GT script"}' > "$GT_JSON"

# --- CHECK AGENT OUTPUTS ---

# 1. CSV
CSV_EXISTS="false"
CSV_MODIFIED="false"
if [ -f "$CSV_FILE" ]; then
    CSV_EXISTS="true"
    CSV_MTIME=$(stat -c %Y "$CSV_FILE")
    if [ "$CSV_MTIME" -gt "$TASK_START" ]; then
        CSV_MODIFIED="true"
    fi
fi

# 2. Plot
PLOT_EXISTS="false"
PLOT_MODIFIED="false"
if [ -f "$PLOT_FILE" ]; then
    PLOT_EXISTS="true"
    PLOT_MTIME=$(stat -c %Y "$PLOT_FILE")
    if [ "$PLOT_MTIME" -gt "$TASK_START" ]; then
        PLOT_MODIFIED="true"
    fi
fi

# 3. Summary
SUMMARY_EXISTS="false"
if [ -f "$SUMMARY_FILE" ]; then
    SUMMARY_EXISTS="true"
fi

# --- PACKAGE RESULTS ---
TEMP_RESULT=$(mktemp /tmp/result.XXXXXX.json)
cat << EOF > "$TEMP_RESULT"
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "csv_exists": $CSV_EXISTS,
    "csv_modified": $CSV_MODIFIED,
    "plot_exists": $PLOT_EXISTS,
    "plot_modified": $PLOT_MODIFIED,
    "summary_exists": $SUMMARY_EXISTS,
    "csv_path": "$CSV_FILE",
    "summary_path": "$SUMMARY_FILE",
    "plot_path": "$PLOT_FILE",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Save result to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_RESULT" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_RESULT"

# Ensure ground truth is accessible
chmod 666 "$GT_JSON" 2>/dev/null || true

echo "Export complete. Result:"
cat /tmp/task_result.json