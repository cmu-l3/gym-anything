#!/bin/bash
echo "=== Exporting compute_specific_energy results ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
RESULTS_DIR="/home/ga/Documents/hec_ras_results"
CSV_PATH="$RESULTS_DIR/specific_energy_curve.csv"
REPORT_PATH="$RESULTS_DIR/specific_energy_report.txt"
HDF_PATH="/home/ga/Documents/hec_ras_projects/Muncie/Muncie.p04.hdf"

# 1. Capture final screenshot
take_screenshot /tmp/task_final.png

# 2. Check output files
CSV_EXISTS="false"
REPORT_EXISTS="false"
CSV_CREATED_DURING_TASK="false"
REPORT_CREATED_DURING_TASK="false"

if [ -f "$CSV_PATH" ]; then
    CSV_EXISTS="true"
    MTIME=$(stat -c %Y "$CSV_PATH")
    if [ "$MTIME" -gt "$TASK_START" ]; then
        CSV_CREATED_DURING_TASK="true"
    fi
fi

if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    MTIME=$(stat -c %Y "$REPORT_PATH")
    if [ "$MTIME" -gt "$TASK_START" ]; then
        REPORT_CREATED_DURING_TASK="true"
    fi
fi

# 3. Generate GROUND TRUTH inside the container
# We run a python script to parse the HDF file and compute the correct physics
# This ensures we compare against the exact model state
echo "Generating ground truth data..."
cat > /tmp/generate_ground_truth.py << 'PYEOF'
import h5py
import numpy as np
import json
import sys

G = 32.174

def compute_area(station, elevation, wse):
    """Compute flow area for a given WSE using trapezoidal rule."""
    # Filter points below WSE
    idx = np.where(elevation < wse)[0]
    if len(idx) < 2:
        return 0.0
    
    area = 0.0
    # Find segments that intersect WSE
    # This is a simplified integration for the task verification
    # We assume the agent does something similar (standard trapezoidal)
    
    # Simple approach: clip geometry at WSE
    clipped_elev = np.minimum(elevation, wse)
    depths = wse - clipped_elev
    depths[depths < 0] = 0
    
    # Integrate depths over station
    area = np.trapz(depths, station)
    return max(0.0, area)

try:
    with h5py.File("/home/ga/Documents/hec_ras_projects/Muncie/Muncie.p04.hdf", "r") as f:
        # 1. Find Max Q
        # Path structure varies slightly by version, assuming typical 6.x
        # Results/Unsteady/Output/Output Blocks/Base Output/Unsteady Time Series/Cross Sections/Flow
        try:
            flow_path = "Results/Unsteady/Output/Output Blocks/Base Output/Unsteady Time Series/Cross Sections/Flow"
            flows = f[flow_path][:]
            # flows shape: (time, cross_section)
            peak_flows = np.max(flows, axis=0)
            max_q_idx = np.argmax(peak_flows)
            max_q = float(peak_flows[max_q_idx])
            
            # Get associated WSE
            wse_path = "Results/Unsteady/Output/Output Blocks/Base Output/Unsteady Time Series/Cross Sections/Water Surface"
            wses = f[wse_path][:]
            actual_wse = float(np.max(wses[:, max_q_idx])) # Peak WSE at that cross section
        except KeyError:
            # Fallback for Steady or different structure
            print("Could not find standard Unsteady flow path", file=sys.stderr)
            sys.exit(1)

        # 2. Get Geometry for this RS
        # Geometry/Cross Sections/Attributes -> needed to map index to RS name
        rs_names = f["Geometry/Cross Sections/Attributes"][:]["River Station"]
        rs_name = rs_names[max_q_idx].decode('utf-8')
        
        # Get Station/Elevation
        # Coordinate path: Geometry/Cross Sections/Station Elevation/{rs_name} (sometimes organized by 2D/3D structure)
        # In HEC-RAS HDF, Cross Section geometry is stored in "Geometry/Cross Sections/Station Elevation"
        # The organization is often a concatenated array with starting indices
        
        # Alternative: look for specific group structure
        # Let's try to find the 1D cross section data
        # "Geometry/Cross Sections/Station Elevation Info" contains starting row and count
        info = f["Geometry/Cross Sections/Station Elevation Info"][max_q_idx]
        start_idx = info[0] # "Starting Row"
        count = info[1]     # "Row Count"
        
        all_coords = f["Geometry/Cross Sections/Station Elevation Data"][:]
        coords = all_coords[start_idx : start_idx + count]
        station = coords[:, 0]
        elevation = coords[:, 1]
        
        thalweg = float(np.min(elevation))
        actual_depth = actual_wse - thalweg
        
        # 3. Compute Specific Energy Curve
        depths = np.arange(0.1, 25.1, 0.1)
        energies = []
        areas = []
        
        min_e = float('inf')
        crit_depth = 0.0
        
        for y in depths:
            wse_hypothetical = thalweg + y
            area = compute_area(station, elevation, wse_hypothetical)
            if area > 0.001:
                velocity = max_q / area
                e = y + (velocity**2) / (2 * G)
            else:
                e = float('inf')
            
            energies.append(float(e))
            areas.append(float(area))
            
            if e < min_e:
                min_e = e
                crit_depth = y

        # 4. Classify actual flow
        actual_area = compute_area(station, elevation, actual_wse)
        actual_vel = max_q / actual_area if actual_area > 0 else 0
        actual_e = actual_depth + (actual_vel**2)/(2*G)
        
        regime = "Subcritical" if actual_depth > crit_depth else "Supercritical"

        result = {
            "river_station": rs_name,
            "peak_discharge": max_q,
            "thalweg": thalweg,
            "critical_depth": float(crit_depth),
            "min_specific_energy": float(min_e),
            "actual_depth": actual_depth,
            "actual_specific_energy": actual_e,
            "flow_regime": regime,
            "curve_sample": {
                "depths": [float(d) for d in depths[::10]], # Sample for verification
                "energies": [float(e) for e in energies[::10]]
            }
        }
        
        print(json.dumps(result))

except Exception as e:
    print(json.dumps({"error": str(e)}))
PYEOF

python3 /tmp/generate_ground_truth.py > /tmp/ground_truth.json 2>/tmp/gt_error.log

# 4. Prepare results for export
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "csv_exists": $CSV_EXISTS,
    "csv_created_during_task": $CSV_CREATED_DURING_TASK,
    "report_exists": $REPORT_EXISTS,
    "report_created_during_task": $REPORT_CREATED_DURING_TASK,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Save results
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

# Copy agent outputs to tmp for easy extraction
if [ -f "$CSV_PATH" ]; then
    cp "$CSV_PATH" /tmp/agent_curve.csv
    chmod 666 /tmp/agent_curve.csv
fi
if [ -f "$REPORT_PATH" ]; then
    cp "$REPORT_PATH" /tmp/agent_report.txt
    chmod 666 /tmp/agent_report.txt
fi

# Ensure ground truth is readable
chmod 666 /tmp/ground_truth.json 2>/dev/null || true

echo "Export complete. Result:"
cat /tmp/task_result.json