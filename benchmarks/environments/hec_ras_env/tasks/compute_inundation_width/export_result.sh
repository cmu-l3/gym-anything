#!/bin/bash
echo "=== Exporting compute_inundation_width result ==="

# Source utilities
source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
CSV_PATH="/home/ga/Documents/hec_ras_results/inundation_width.csv"
SUMMARY_PATH="/home/ga/Documents/hec_ras_results/inundation_summary.txt"
HDF_FILE="/home/ga/Documents/hec_ras_projects/Muncie/Muncie.p04.hdf"
# Fallback if the agent used the tmp file
if [ ! -f "$HDF_FILE" ]; then
    HDF_FILE="/home/ga/Documents/hec_ras_projects/Muncie/Muncie.p04.tmp.hdf"
fi

# 1. Check if Agent Output Files Exist and were created during task
CSV_EXISTS="false"
CSV_CREATED_DURING_TASK="false"
if [ -f "$CSV_PATH" ]; then
    CSV_EXISTS="true"
    MTIME=$(stat -c %Y "$CSV_PATH" 2>/dev/null || echo "0")
    if [ "$MTIME" -gt "$TASK_START" ]; then
        CSV_CREATED_DURING_TASK="true"
    fi
fi

SUMMARY_EXISTS="false"
if [ -f "$SUMMARY_PATH" ]; then
    SUMMARY_EXISTS="true"
fi

# 2. Generate Ground Truth using a Python script running IN THE CONTAINER
# We do this here because we have access to the exact HDF file and h5py environment
echo "Calculating ground truth values..."
cat > /tmp/calc_ground_truth.py << 'PYEOF'
import h5py
import numpy as np
import sys
import json
import os

def calculate_top_width(stations, elevations, wse):
    # If water is below lowest ground, width is 0
    if wse <= np.min(elevations):
        return 0.0
    
    # If water is above highest ground, we assume vertical walls at edges (simplified)
    # or just take the max extent. Let's look for intersections.
    
    # Calculate difference between ground and water
    diff = elevations - wse
    
    # Find crossings (sign changes)
    # np.diff(np.sign(diff)) will be non-zero at crossings
    # sign(0) is 0, so we use signbit to handle 0 cases better or just standard checking
    
    # Get indices where the sign changes
    # Use signbit: True for negative (water above ground), False for positive (ground above water)
    # Wait, elev - wse. 
    # If elev > wse (dry): pos
    # If elev < wse (wet): neg
    
    signs = np.sign(diff)
    # Eliminate zeros for simple crossing detection if needed, but let's do linear interp
    
    crossings = []
    
    for i in range(len(stations) - 1):
        y1 = diff[i]
        y2 = diff[i+1]
        
        if (y1 > 0 and y2 < 0) or (y1 < 0 and y2 > 0):
            # Crossing
            x1, x2 = stations[i], stations[i+1]
            # Linear interpolation for y=0
            # x = x1 + (0 - y1) * (x2 - x1) / (y2 - y1)
            x = x1 - y1 * (x2 - x1) / (y2 - y1)
            crossings.append(x)
        elif y1 == 0:
            crossings.append(stations[i])
        # Note: if y2 is 0, it will be caught as y1 in next iteration
            
    if not crossings:
        # Either fully dry or fully submerged
        if np.all(elevations < wse):
            return stations[-1] - stations[0]
        else:
            return 0.0
            
    return max(crossings) - min(crossings)

def get_geometry_paths(f):
    # Try 1D geometry paths
    # HEC-RAS 6.x paths
    base = "Geometry/Cross Sections"
    if base not in f:
        return None
    
    # Station Elevation
    # This is often stored as a concatenated 2D array or individual datasets
    # In Muncie example (1D), it's usually under "Station Elevation"
    return base

def main():
    hdf_path = sys.argv[1]
    results = {}
    
    try:
        with h5py.File(hdf_path, 'r') as f:
            # 1. Get River Stations
            # Path: Geometry/Cross Sections/Attributes -> column "River Station"
            try:
                attrs = f['Geometry/Cross Sections/Attributes'][()]
                # Decode bytes to strings
                river_stations = [r[0].decode('utf-8').strip() for r in attrs['River Station']]
            except:
                # Fallback path or logic
                results['error'] = "Could not read River Stations"
                print(json.dumps(results))
                return

            # 2. Get Station-Elevation Data
            # This is complex in HDF. 
            # "Station Elevation" table: [River Station Index, Station, Elevation] or similar?
            # Or "Polyline Info" pointing to "Station Elevation" 
            # In RAS 6.x: Geometry/Cross Sections/Station Elevation is a Dataset containing all points concatenated?
            # Usually there is an index table.
            
            # Simplified approach: If we can't easily parse complex geometry, we can try to verify 
            # based on the Results arrays if they have top width directly?
            # HEC-RAS results often export "Top Width" in the output!
            # Path: Results/Unsteady/Output/Output Blocks/Base Output/Unsteady Time Series/Cross Sections/Top Width
            
            gt_data = []
            
            # CHECK IF TOP WIDTH IS PRE-CALCULATED IN RESULTS (Much more robust)
            tw_path = 'Results/Unsteady/Output/Output Blocks/Base Output/Unsteady Time Series/Cross Sections/Top Width'
            wse_path = 'Results/Unsteady/Output/Output Blocks/Base Output/Unsteady Time Series/Cross Sections/Water Surface'
            
            if tw_path in f:
                # Shape: (Time, CrossSection)
                tw_data = f[tw_path][()]
                wse_data = f[wse_path][()]
                
                # We need Peak WSE and the Top Width AT that Peak
                # Note: Peak Top Width might not occur exactly at Peak WSE (hysteresis), 
                # but usually they are coincident for max flood extent.
                # Task asks for "Top Width of flow at that peak elevation"
                
                # Get max WSE indices
                max_wse_indices = np.argmax(wse_data, axis=0)
                
                for i, rs in enumerate(river_stations):
                    idx = max_wse_indices[i]
                    peak_wse = float(wse_data[idx, i])
                    top_width = float(tw_data[idx, i])
                    
                    gt_data.append({
                        "River_Station": rs,
                        "Peak_WSE_ft": peak_wse,
                        "Top_Width_ft": top_width
                    })
            else:
                results['error'] = "Top Width results not found in HDF"
                print(json.dumps(results))
                return
                
            results['ground_truth'] = gt_data
            
            # Stats
            widths = [d['Top_Width_ft'] for d in gt_data]
            results['max_width'] = max(widths)
            results['mean_width'] = sum(widths) / len(widths)
            results['max_width_station'] = gt_data[widths.index(max(widths))]['River_Station']
            results['count'] = len(gt_data)
            
    except Exception as e:
        results['error'] = str(e)
        
    print(json.dumps(results))

if __name__ == "__main__":
    main()
PYEOF

# Run the python script
GROUND_TRUTH_JSON="{}"
if [ -f "$HDF_FILE" ]; then
    GROUND_TRUTH_JSON=$(python3 /tmp/calc_ground_truth.py "$HDF_FILE")
fi

# 3. Read Agent's CSV file content if exists
AGENT_CSV_CONTENT=""
if [ "$CSV_EXISTS" = "true" ]; then
    AGENT_CSV_CONTENT=$(cat "$CSV_PATH" | head -n 50) # Limit size
fi

# 4. Read Agent's Summary content
AGENT_SUMMARY_CONTENT=""
if [ "$SUMMARY_EXISTS" = "true" ]; then
    AGENT_SUMMARY_CONTENT=$(cat "$SUMMARY_PATH")
fi

# 5. Take Final Screenshot
take_screenshot /tmp/task_end_screenshot.png

# 6. Construct Final Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "csv_exists": $CSV_EXISTS,
    "csv_created_during_task": $CSV_CREATED_DURING_TASK,
    "summary_exists": $SUMMARY_EXISTS,
    "agent_csv_content": $(python3 -c "import json, sys; print(json.dumps(sys.stdin.read()))" <<< "$AGENT_CSV_CONTENT"),
    "agent_summary_content": $(python3 -c "import json, sys; print(json.dumps(sys.stdin.read()))" <<< "$AGENT_SUMMARY_CONTENT"),
    "ground_truth": $GROUND_TRUTH_JSON,
    "screenshot_path": "/tmp/task_end_screenshot.png"
}
EOF

# Safe copy to output
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="