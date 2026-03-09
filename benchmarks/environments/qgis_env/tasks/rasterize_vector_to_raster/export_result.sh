#!/bin/bash
set -e
echo "=== Exporting rasterize task results ==="

source /workspace/scripts/task_utils.sh

# 1. Capture Final State
take_screenshot /tmp/task_final.png

# 2. Gather Environment Info
TASK_START=0
if [ -f /tmp/task_start_time.txt ]; then
    TASK_START=$(cat /tmp/task_start_time.txt)
fi

RESULT_FILE="/tmp/task_result.json"
RASTER_PATH="/home/ga/GIS_Data/exports/polygon_raster.tif"
PROJECT_PATH_QGS="/home/ga/GIS_Data/projects/rasterize_project.qgs"
PROJECT_PATH_QGZ="/home/ga/GIS_Data/projects/rasterize_project.qgz"

# Check for alternative raster file if exact match missing
if [ ! -f "$RASTER_PATH" ]; then
    ALT_RASTER=$(find /home/ga/GIS_Data/exports -name "*.tif" -type f -newermt "@$TASK_START" | head -n 1)
    if [ -n "$ALT_RASTER" ]; then
        echo "Found alternative raster: $ALT_RASTER"
        RASTER_PATH="$ALT_RASTER"
    fi
fi

# 3. Python Analysis Script (GDAL)
# We use python3-gdal which is installed in the env to inspect the raster
python3 << PYEOF
import json
import os
import sys
import glob

# Result dictionary structure
result = {
    "task_start_time": int("$TASK_START"),
    "raster_exists": False,
    "raster_path": "$RASTER_PATH",
    "raster_valid": False,
    "raster_width": 0,
    "raster_height": 0,
    "raster_crs_valid": False,
    "raster_geotransform": [],
    "raster_extent": {},
    "unique_values": [],
    "has_expected_values": False,
    "nodata_value": None,
    "project_exists": False,
    "project_path": "",
    "file_created_during_task": False
}

# 1. Check Project File
qgs_path = "$PROJECT_PATH_QGS"
qgz_path = "$PROJECT_PATH_QGZ"
if os.path.exists(qgs_path):
    result["project_exists"] = True
    result["project_path"] = qgs_path
elif os.path.exists(qgz_path):
    result["project_exists"] = True
    result["project_path"] = qgz_path
else:
    # Look for any recent project
    projects = glob.glob("/home/ga/GIS_Data/projects/*.qg*")
    if projects:
        # Sort by modification time
        projects.sort(key=os.path.getmtime, reverse=True)
        if os.path.getmtime(projects[0]) > result["task_start_time"]:
            result["project_exists"] = True
            result["project_path"] = projects[0]

# 2. Check Raster File
if os.path.exists(result["raster_path"]):
    result["raster_exists"] = True
    
    # Check modification time
    mtime = os.path.getmtime(result["raster_path"])
    if mtime > result["task_start_time"]:
        result["file_created_during_task"] = True

    try:
        from osgeo import gdal
        import numpy as np
        
        gdal.UseExceptions()
        ds = gdal.Open(result["raster_path"])
        
        if ds:
            result["raster_valid"] = True
            result["raster_width"] = ds.RasterXSize
            result["raster_height"] = ds.RasterYSize
            
            # Check CRS
            proj = ds.GetProjection()
            if proj and ("WGS 84" in proj or "4326" in proj or "CRS84" in proj):
                result["raster_crs_valid"] = True
                
            # Check Geotransform & Extent
            gt = ds.GetGeoTransform()
            if gt:
                result["raster_geotransform"] = list(gt)
                # gt[0] = xmin, gt[3] = ymax, gt[1] = pixel width, gt[5] = pixel height (negative)
                xmin = gt[0]
                ymax = gt[3]
                xmax = xmin + (gt[1] * ds.RasterXSize)
                ymin = ymax + (gt[5] * ds.RasterYSize)
                result["raster_extent"] = {"xmin": xmin, "ymin": ymin, "xmax": xmax, "ymax": ymax}

            # Check Values
            band = ds.GetRasterBand(1)
            if band:
                result["nodata_value"] = band.GetNoDataValue()
                
                # Read data to find unique values
                data = band.ReadAsArray()
                
                # Mask nodata if present
                if result["nodata_value"] is not None:
                    mask = np.isclose(data, result["nodata_value"])
                    valid_data = data[~mask]
                else:
                    valid_data = data[data != -9999] # Fallback assumption
                
                if valid_data.size > 0:
                    uniques = np.unique(valid_data)
                    # Convert to standard python floats for JSON
                    result["unique_values"] = [float(x) for x in uniques[:50]]
                    
                    # Check for expected values 10.5 and 8.2 (with tolerance)
                    has_10_5 = any(abs(x - 10.5) < 0.01 for x in uniques)
                    has_8_2 = any(abs(x - 8.2) < 0.01 for x in uniques)
                    result["has_expected_values"] = has_10_5 and has_8_2

            ds = None
    except Exception as e:
        print(f"Error inspecting raster: {e}", file=sys.stderr)

# Write result
with open("$RESULT_FILE", "w") as f:
    json.dump(result, f, indent=2)
PYEOF

# 4. Final Cleanup & Export
chmod 666 "$RESULT_FILE" 2>/dev/null || true
echo "Result saved to $RESULT_FILE"
cat "$RESULT_FILE"
echo "=== Export complete ==="