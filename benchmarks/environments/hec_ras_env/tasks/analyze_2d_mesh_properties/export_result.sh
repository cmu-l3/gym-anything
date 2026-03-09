#!/bin/bash
echo "=== Exporting analyze_2d_mesh_properties results ==="

source /workspace/scripts/task_utils.sh

# Record timestamps
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

REPORT_PATH="/home/ga/Documents/hec_ras_results/mesh_analysis_report.txt"
CSV_PATH="/home/ga/Documents/hec_ras_results/mesh_cell_data.csv"
HDF_PATH="/home/ga/Documents/hec_ras_projects/Muncie/Muncie.p04.tmp.hdf"

# --- 1. Check Output Files ---

# Report File
if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    REPORT_SIZE=$(stat -c%s "$REPORT_PATH")
    REPORT_MTIME=$(stat -c%Y "$REPORT_PATH")
    if [ "$REPORT_MTIME" -gt "$TASK_START" ]; then
        REPORT_FRESH="true"
    else
        REPORT_FRESH="false"
    fi
else
    REPORT_EXISTS="false"
    REPORT_SIZE="0"
    REPORT_FRESH="false"
fi

# CSV File
if [ -f "$CSV_PATH" ]; then
    CSV_EXISTS="true"
    CSV_SIZE=$(stat -c%s "$CSV_PATH")
    CSV_MTIME=$(stat -c%Y "$CSV_PATH")
    if [ "$CSV_MTIME" -gt "$TASK_START" ]; then
        CSV_FRESH="true"
    else
        CSV_FRESH="false"
    fi
else
    CSV_EXISTS="false"
    CSV_SIZE="0"
    CSV_FRESH="false"
fi

# --- 2. Generate Ground Truth from HDF (inside container) ---
# We do this inside the container because it has h5py installed and access to the file.
# The result is saved to a JSON file for the verifier to read.

cat > /tmp/generate_ground_truth.py << 'PYEOF'
import h5py
import numpy as np
import json
import sys
import os

hdf_path = "/home/ga/Documents/hec_ras_projects/Muncie/Muncie.p04.tmp.hdf"
output_path = "/tmp/ground_truth.json"

gt = {
    "flow_areas": {},
    "total_cells": 0,
    "area_names": [],
    "success": False
}

try:
    if not os.path.exists(hdf_path):
        gt["error"] = "HDF file not found"
    else:
        with h5py.File(hdf_path, "r") as hdf:
            # Locate 2D Flow Areas group
            geom = hdf.get("Geometry")
            flow_areas_grp = None
            if geom:
                # Try standard paths
                if "2D Flow Areas" in geom:
                    flow_areas_grp = geom["2D Flow Areas"]
                else:
                    # Case-insensitive search
                    for k in geom.keys():
                        if "2d flow areas" in k.lower():
                            flow_areas_grp = geom[k]
                            break
            
            if flow_areas_grp:
                for name in flow_areas_grp.keys():
                    item = flow_areas_grp[name]
                    # Check if it's a group and has cell data
                    if isinstance(item, h5py.Group) and "Cells Center Coordinate" in item:
                        coords = np.array(item["Cells Center Coordinate"])
                        elevs = np.array(item.get("Cells Minimum Elevation", []))
                        
                        area_data = {
                            "cell_count": len(coords),
                            "x_min": float(np.min(coords[:, 0])),
                            "x_max": float(np.max(coords[:, 0])),
                            "y_min": float(np.min(coords[:, 1])),
                            "y_max": float(np.max(coords[:, 1])),
                            "elev_min": float(np.min(elevs)) if len(elevs) > 0 else 0,
                            "elev_max": float(np.max(elevs)) if len(elevs) > 0 else 0,
                            "elev_mean": float(np.mean(elevs)) if len(elevs) > 0 else 0,
                            "elev_std": float(np.std(elevs)) if len(elevs) > 0 else 0,
                            # Sample some specific cells for spot checking (first, middle, last)
                            "samples": []
                        }
                        
                        # Add samples for CSV verification
                        indices = [0, len(coords)//2, len(coords)-1]
                        for idx in indices:
                            if idx < len(coords):
                                area_data["samples"].append({
                                    "index": int(idx),
                                    "x": float(coords[idx, 0]),
                                    "y": float(coords[idx, 1]),
                                    "elev": float(elevs[idx]) if idx < len(elevs) else 0
                                })

                        gt["flow_areas"][name] = area_data
                        gt["total_cells"] += len(coords)
                        gt["area_names"].append(name)
                
                gt["success"] = True
            else:
                gt["error"] = "2D Flow Areas group not found"

except Exception as e:
    gt["error"] = str(e)

with open(output_path, "w") as f:
    json.dump(gt, f, indent=2)
PYEOF

# Run the python script
python3 /tmp/generate_ground_truth.py 2>/tmp/gt_error.log || echo "GT generation failed"

# --- 3. Take Final Screenshot ---
take_screenshot /tmp/task_final.png

# --- 4. Package Results ---
# We will create a metadata JSON, but the verifier will mostly look at the
# actual report/csv files and the ground truth json.

TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "report_exists": $REPORT_EXISTS,
    "report_fresh": $REPORT_FRESH,
    "report_size": $REPORT_SIZE,
    "csv_exists": $CSV_EXISTS,
    "csv_fresh": $CSV_FRESH,
    "csv_size": $CSV_SIZE,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location with proper permissions
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

# Also make the ground truth available for copy
chmod 666 /tmp/ground_truth.json 2>/dev/null || true

echo "Results exported."