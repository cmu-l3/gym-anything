#!/bin/bash
echo "=== Exporting derive_reach_storage_curve result ==="

source /workspace/scripts/task_utils.sh

# Record timestamps
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

OUTPUT_PATH="/home/ga/Documents/hec_ras_results/reach_storage_curve.csv"
GROUND_TRUTH_PATH="/tmp/ground_truth_storage.csv"

# --- 1. Check Agent Output ---
if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    else
        FILE_CREATED_DURING_TASK="false"
    fi
else
    OUTPUT_EXISTS="false"
    FILE_CREATED_DURING_TASK="false"
fi

# --- 2. Check for Agent Script (Anti-gaming) ---
# Did the agent write a python script?
AGENT_SCRIPT=$(find "$MUNCIE_DIR" /home/ga/Documents -name "*.py" -newer /tmp/task_start_time.txt 2>/dev/null | head -1)
if [ -n "$AGENT_SCRIPT" ]; then
    SCRIPT_CREATED="true"
else
    SCRIPT_CREATED="false"
fi

# --- 3. Generate Ground Truth (Hidden Reference Implementation) ---
echo "Generating ground truth..."

# Create the reference script
cat > /tmp/generate_ground_truth.py << 'EOF'
import h5py
import numpy as np
import sys

def calculate_polygon_area(x, y):
    """Calculate area of polygon using shoelace formula."""
    return 0.5 * np.abs(np.dot(x, np.roll(y, 1)) - np.dot(y, np.roll(x, 1)))

def get_wetted_area(stations, elevations, water_surface_elev):
    """Calculate wetted area below water_surface_elev."""
    # Filter points below water surface
    if np.min(elevations) >= water_surface_elev:
        return 0.0

    # This is a simplified "level pool" intersection logic
    # Find intersection points and construct polygon below WSE
    # For robust calculation, we clip the geometry
    
    # Simple integration: trapezoidal rule for depth
    area = 0.0
    for i in range(len(stations) - 1):
        x1, z1 = stations[i], elevations[i]
        x2, z2 = stations[i+1], elevations[i+1]
        
        # If both above, no area
        if z1 >= water_surface_elev and z2 >= water_surface_elev:
            continue
            
        # If both below
        if z1 <= water_surface_elev and z2 <= water_surface_elev:
            d1 = water_surface_elev - z1
            d2 = water_surface_elev - z2
            dx = x2 - x1
            area += 0.5 * (d1 + d2) * dx
            continue
            
        # One above, one below (intersection)
        # Find x where z = water_surface_elev
        # z = z1 + (z2 - z1) * (x - x1) / (x2 - x1)
        # wse = z1 + slope * (x_int - x1) -> x_int = x1 + (wse - z1) / slope
        slope = (z2 - z1) / (x2 - x1)
        x_int = x1 + (water_surface_elev - z1) / slope
        
        if z1 < water_surface_elev: # z1 below, z2 above
            d1 = water_surface_elev - z1
            dx = x_int - x1
            area += 0.5 * d1 * dx
        else: # z1 above, z2 below
            d2 = water_surface_elev - z2
            dx = x2 - x_int
            area += 0.5 * d2 * dx
            
    return abs(area)

def main():
    try:
        # Find HDF file
        import glob
        files = glob.glob("/home/ga/Documents/hec_ras_projects/Muncie/*.hdf")
        # Prefer the geometry file or plan file
        hdf_path = next((f for f in files if '.g' in f or '.p' in f), None)
        if not hdf_path:
            print("No HDF file found")
            return

        with h5py.File(hdf_path, 'r') as f:
            # Locate Cross Section data
            # Path varies by version, try common paths
            base_path = '/Geometry/Cross Sections'
            if base_path not in f:
                print("Geometry path not found")
                return

            # Get attributes
            xs_table = f[base_path]['Attributes'][()]
            # Columns usually: RS name, Reach name, etc.
            # We need strictly the geometry linkage
            
            # Read reach lengths
            # Often in /Geometry/Cross Sections/Attributes or a separate dataset
            # We'll use the station-elevation data directly
            
            # Map Row index to River Station
            river_stations = [r[0].decode('utf-8') for r in f[base_path]['River Stations'][()]]
            
            # Sort by River Station (downstream usually implies decreasing RS, but we need geometric order)
            # HEC-RAS stores upstream to downstream typically
            
            # Extract Reach Lengths (Channel)
            # Dataset: 'Reach Lengths' column index 2 (Left, Channel, Right)
            reach_lengths = f[base_path]['Reach Lengths'][:, 1] # Main channel
            
            # Extract Coordinate Info to get Station-Elevation
            coord_info = f[base_path]['Station Elevation Info'][()]
            all_coords = f[base_path]['Station Elevation Values'][()]
            
            cross_sections = []
            for i, rs in enumerate(river_stations):
                start_idx = coord_info[i][0]
                count = coord_info[i][1]
                coords = all_coords[start_idx : start_idx + count]
                stations = coords[:, 0]
                elevations = coords[:, 1]
                length = reach_lengths[i]
                cross_sections.append({
                    'rs': rs,
                    'stations': stations,
                    'elevs': elevations,
                    'length': length
                })

        # Calculate Volumes
        print("Elevation_ft,Volume_acft")
        
        for elev in range(925, 956):
            total_vol_ft3 = 0.0
            
            # Calculate area for each XS
            areas = []
            for xs in cross_sections:
                a = get_wetted_area(xs['stations'], xs['elevs'], elev)
                areas.append(a)
            
            # Integrate Volume (Upstream to Downstream)
            # V = Sum( (A_i + A_{i+1})/2 * L_i )
            # NOTE: HEC-RAS Reach Length at index i is typically distance to i+1 (downstream)
            # The last XS usually has length 0.
            
            for i in range(len(cross_sections) - 1):
                avg_area = (areas[i] + areas[i+1]) / 2.0
                reach_len = cross_sections[i]['length'] 
                total_vol_ft3 += avg_area * reach_len
                
            vol_acft = total_vol_ft3 / 43560.0
            print(f"{elev},{vol_acft:.4f}")

    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)

if __name__ == "__main__":
    main()
EOF

# Run Ground Truth Script
python3 /tmp/generate_ground_truth.py > "$GROUND_TRUTH_PATH" 2> /tmp/ground_truth_error.log

# Ensure output permissions
chmod 666 "$OUTPUT_PATH" 2>/dev/null || true
chmod 666 "$GROUND_TRUTH_PATH" 2>/dev/null || true

# Take final screenshot
take_screenshot /tmp/task_final.png

# Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_exists": $OUTPUT_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "script_created": $SCRIPT_CREATED,
    "output_path": "$OUTPUT_PATH",
    "ground_truth_path": "$GROUND_TRUTH_PATH",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="