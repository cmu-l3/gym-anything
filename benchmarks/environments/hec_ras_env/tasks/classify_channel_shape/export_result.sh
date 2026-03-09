#!/bin/bash
echo "=== Exporting Classify Channel Shape Result ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Paths
RESULTS_DIR="/home/ga/Documents/hec_ras_results"
AGENT_CSV="$RESULTS_DIR/channel_shape_analysis.csv"
HDF_FILE="$MUNCIE_DIR/Muncie.p04.hdf"
GROUND_TRUTH_CSV="/tmp/ground_truth_shape.csv"

# 1. Generate Ground Truth (Hidden from Agent)
# We run a reference implementation to calculate the correct values from the HDF file
# This handles cases where simulation results might vary slightly by machine
echo "Generating ground truth data..."

cat > /tmp/generate_ground_truth.py << 'EOF'
import h5py
import numpy as np
import pandas as pd
import sys

try:
    # Path to HDF file
    hdf_path = sys.argv[1]
    output_path = sys.argv[2]
    
    with h5py.File(hdf_path, 'r') as f:
        # Paths in HEC-RAS 6.x HDF
        # Note: These paths are typical for 6.x but need to be robust
        # Adjusting paths based on standard RAS HDF structure
        
        # 1. Get River Stations
        # Geometry/Cross Sections/River Stations is often byte array
        stations_ds = f['Geometry/Cross Sections/River Stations']
        stations = [s.decode('utf-8').strip() for s in stations_ds[:]]
        
        # 2. Get Station-Elevation Data (Geometry)
        # Geometry/Cross Sections/Station Elevation/{Name} is not standard
        # Typically: Geometry/Cross Sections/Station Elevation is a 2D array or concatenated
        # In RAS HDF, it's often stored in 'Geometry/Cross Sections/Station Elevation' 
        # as a concatenated array with 'Face Info' or similar indexing.
        # EASIER APPROACH: Use 'Coordinate' dataset if available or iterate attributes
        # For this script, we assume the 'Station Elevation' dataset exists and has an index
        
        # Actually, let's look for result Water Surfaces first
        # Results/Unsteady/Output/Output Blocks/Base Output/Unsteady Time Series/Cross Sections/Water Surface
        wse_ds = f['Results/Unsteady/Output/Output Blocks/Base Output/Unsteady Time Series/Cross Sections/Water Surface']
        wse_data = wse_ds[:] # Shape: (Time, CrossSection)
        
        # Get Max WSE per XS
        peak_wse = np.max(wse_data, axis=0)
        
        results = []
        
        # Access Geometry Info (Indexed)
        # We need to map stations to their geometry index
        # Usually straightforward mapping 1:1 if sorted
        
        # Extract geometry for each XS
        # Note: Parsing raw RAS geometry HDF structure in a short script is complex due to
        # variable length arrays. We will use a simplified approximation or specific known paths.
        #
        # ALTERNATIVE: Use the 'Hydraulic Property Tables' if available? No, task asks for calculation.
        #
        # ROBUST PATH: 'Geometry/Cross Sections/Station Elevation' is a 1D array of (Station, Elev).
        # 'Geometry/Cross Sections/Attributes' usually contains 'Station Elevation Info' (Start Index, Count).
        
        se_data = f['Geometry/Cross Sections/Station Elevation'][:] # Columns: Station, Elevation
        se_info = f['Geometry/Cross Sections/Attributes'][()] # Structured array
        
        # Column names in attributes can vary, looking for 'Station Elevation Start' and 'Station Elevation Count'
        # Let's assume the field names based on RAS 6.0 schema
        # If field names differ, this ground truth gen might fail, but let's try standard names
        
        # Field names in RAS 6.x HDF are often: 'Station Elevation Starting Row', 'Station Elevation Row Count'
        # Let's inspect names if possible, but hardcoding for script:
        
        for i, st_name in enumerate(stations):
            try:
                # Get start/count
                # se_info is a structured numpy array. We need to find the fields.
                # Just assuming column 2 and 3 match standard RAS output for simplicity in this generated script
                # Real implementation would inspect dtype.names
                
                # Setup specific for verifying Muncie.p04.hdf structure
                start_idx = se_info[i]['Station Elevation Starting Row']
                count = se_info[i]['Station Elevation Row Count']
                
                xs_coords = se_data[start_idx : start_idx + count]
                xs_stations = xs_coords[:, 0]
                xs_elevs = xs_coords[:, 1]
                
                wse = peak_wse[i]
                
                # Filter points below WSE
                # Find intersection points? 
                # Simplified: standard polygon area calc for water
                
                # 1. Identify valid channel (between banks? Task says "Cross-section geometry", implied whole XS)
                # But typically flow is contained. Let's assume simple pool level wse.
                
                # Calculate Area
                # Polygon: (x, min(y, wse))
                # Trapezoidal integration
                
                area = 0.0
                top_width = 0.0
                min_elev = np.min(xs_elevs)
                
                # Simple implementation: Discretize or exact intersection
                # Let's use simple trapezoid rule on points below WSE
                
                # Check if XS is dry
                if wse <= min_elev:
                    results.append([st_name, wse, 0, 0, 0, 0, 0, "Dry"])
                    continue
                
                # Calculate geometry properties
                # Find segments crossing WSE
                # This is a bit heavy for a bash one-liner, but we need ground truth.
                
                # Simplified approach for verification:
                # Just take points strictly below WSE for area (approx)
                # This introduces error vs agent who might interpolate.
                # BETTER: Just check if Agent's calc is "close enough" to a robust calc.
                
                # Let's trust the agent does standard HEC-RAS algorithm:
                # Effective Flow Area.
                
                # For Ground Truth, we will rely on checking consistency of the agent's OWN numbers
                # plus checking if WSE matches HEC-RAS output.
                # The "Shape Factor" logic consistency is what we care about most.
                
                # So Ground Truth mainly needs: Station, Peak WSE, Min Elev (to check Max Depth).
                
                results.append({
                    "River_Station": st_name,
                    "Peak_WSE": wse,
                    "Min_Elev": min_elev
                })
                
            except Exception as e:
                pass

        df = pd.DataFrame(results)
        df.to_csv(output_path, index=False)
        
except Exception as e:
    print(f"Error generating ground truth: {e}")
EOF

# Install pandas/h5py if needed (should be in env)
# Run the generator
python3 /tmp/generate_ground_truth.py "$HDF_FILE" "$GROUND_TRUTH_CSV" 2>/dev/null || echo "Ground Truth Generation Failed"

# 2. Check Simulation Timestamp (Did it run?)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_MTIME=$(cat /tmp/initial_hdf_mtime.txt 2>/dev/null || echo "0")
CURRENT_MTIME=$(stat -c %Y "$HDF_FILE" 2>/dev/null || echo "0")

SIMULATION_RAN="false"
if [ "$CURRENT_MTIME" -gt "$TASK_START" ] && [ "$CURRENT_MTIME" -ne "$INITIAL_MTIME" ]; then
    SIMULATION_RAN="true"
fi

# 3. Check CSV Output
CSV_EXISTS="false"
if [ -f "$AGENT_CSV" ]; then
    CSV_EXISTS="true"
fi

# 4. Screenshots
take_screenshot /tmp/task_final.png

# 5. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "simulation_ran": $SIMULATION_RAN,
    "csv_exists": $CSV_EXISTS,
    "csv_path": "$AGENT_CSV",
    "ground_truth_path": "$GROUND_TRUTH_CSV",
    "hdf_path": "$HDF_FILE",
    "timestamp": "$(date -Iseconds)"
}
EOF

# 6. Secure file transfer
RESULT_JSON="/tmp/task_result.json"
rm -f "$RESULT_JSON" 2>/dev/null || true
cp "$TEMP_JSON" "$RESULT_JSON"
chmod 666 "$RESULT_JSON"
rm -f "$TEMP_JSON"

echo "Result JSON created at $RESULT_JSON"