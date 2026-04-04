#!/bin/bash
echo "=== Exporting Terrain Analysis Result ==="

source /workspace/scripts/task_utils.sh

# 1. Setup paths
EXPORT_DIR="/home/ga/GIS_Data/exports"
PROJECT_DIR="/home/ga/GIS_Data/projects"
HILLSHADE_PATH="$EXPORT_DIR/hillshade.tif"
SLOPE_PATH="$EXPORT_DIR/slope.tif"
PROJECT_PATH_QGZ="$PROJECT_DIR/terrain_analysis.qgz"
PROJECT_PATH_QGS="$PROJECT_DIR/terrain_analysis.qgs"

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 2. Analyze Output Files
echo "Analyzing outputs..."

python3 << PYEOF
import json
import os
import sys
import time
from osgeo import gdal

results = {
    "hillshade_exists": False,
    "hillshade_valid": False,
    "hillshade_stats": {},
    "slope_exists": False,
    "slope_valid": False,
    "slope_stats": {},
    "project_exists": False,
    "project_path": "",
    "timestamp_valid": False
}

def analyze_raster(path, type_name):
    if not os.path.exists(path):
        return False, False, {}
    
    # Check timestamp
    mtime = os.path.getmtime(path)
    task_start = $TASK_START
    if mtime > task_start:
        results["timestamp_valid"] = True

    try:
        ds = gdal.Open(path)
        if ds is None:
            return True, False, {}
        
        band = ds.GetRasterBand(1)
        stats = band.GetStatistics(True, True)
        
        # Check if projection is set
        proj = ds.GetProjection()
        
        info = {
            "min": stats[0],
            "max": stats[1],
            "mean": stats[2],
            "std_dev": stats[3],
            "has_proj": len(proj) > 0,
            "width": ds.RasterXSize,
            "height": ds.RasterYSize
        }
        return True, True, info
    except Exception as e:
        return True, False, {"error": str(e)}

# Analyze Hillshade
hs_exists, hs_valid, hs_stats = analyze_raster("$HILLSHADE_PATH", "hillshade")
results["hillshade_exists"] = hs_exists
results["hillshade_valid"] = hs_valid
results["hillshade_stats"] = hs_stats

# Analyze Slope
sl_exists, sl_valid, sl_stats = analyze_raster("$SLOPE_PATH", "slope")
results["slope_exists"] = sl_exists
results["slope_valid"] = sl_valid
results["slope_stats"] = sl_stats

# Analyze Project
if os.path.exists("$PROJECT_PATH_QGZ"):
    results["project_exists"] = True
    results["project_path"] = "$PROJECT_PATH_QGZ"
elif os.path.exists("$PROJECT_PATH_QGS"):
    results["project_exists"] = True
    results["project_path"] = "$PROJECT_PATH_QGS"

# Write results
with open("/tmp/task_result.json", "w") as f:
    json.dump(results, f, indent=4)

PYEOF

# 3. Take Final Screenshot
take_screenshot /tmp/task_final.png

# 4. Handle Permissions for Result
chmod 666 /tmp/task_result.json 2>/dev/null || true
echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json

# 5. Cleanup QGIS
if is_qgis_running; then
    su - ga -c "DISPLAY=:1 xdotool key ctrl+q" 2>/dev/null || true
    sleep 2
    kill_qgis ga 2>/dev/null || true
fi

echo "=== Export Complete ==="