#!/bin/bash
echo "=== Exporting mosaic_elevation_tiles_merge result ==="

source /workspace/scripts/task_utils.sh

# Fallback utility definitions
if ! type take_screenshot &>/dev/null; then
    take_screenshot() { DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true; }
fi
if ! type is_qgis_running &>/dev/null; then
    is_qgis_running() { pgrep -f "qgis" > /dev/null; }
fi
if ! type kill_qgis &>/dev/null; then
    kill_qgis() { pkill -u "${1:-ga}" -f qgis 2>/dev/null || true; sleep 1; }
fi

# 1. Capture Final State
take_screenshot /tmp/task_end.png
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
EXPORT_PATH="/home/ga/GIS_Data/exports/merged_dem.tif"

# 2. Analyze Output File using Python (GDAL)
# We perform the heavy lifting of verification here to avoid dependency issues in verifier.py
ANALYSIS_JSON='{}'

if [ -f "$EXPORT_PATH" ]; then
    FILE_SIZE=$(stat -c%s "$EXPORT_PATH" 2>/dev/null || echo "0")
    
    # Run Python script to inspect raster properties
    ANALYSIS_JSON=$(python3 << 'PYEOF'
import json
import sys
try:
    from osgeo import gdal
except ImportError:
    # Fallback if gdal python bindings missing (unlikely in QGIS env)
    print(json.dumps({"error": "gdal_missing"}))
    sys.exit(0)

path = "/home/ga/GIS_Data/exports/merged_dem.tif"
result = {
    "exists": True,
    "valid_geotiff": False,
    "bbox": [0,0,0,0],
    "band_count": 0,
    "min_val": 0,
    "max_val": 0,
    "crs_auth": "unknown"
}

try:
    ds = gdal.Open(path)
    if ds:
        driver = ds.GetDriver().ShortName
        result["valid_geotiff"] = (driver == "GTiff")
        
        # Get Extent
        # GeoTransform: [top_left_x, w_e_res, rot, top_left_y, rot, n_s_res]
        gt = ds.GetGeoTransform()
        cols = ds.RasterXSize
        rows = ds.RasterYSize
        
        min_x = gt[0]
        max_y = gt[3]
        max_x = min_x + (cols * gt[1])
        min_y = max_y + (rows * gt[5])
        
        result["bbox"] = [min_x, min_y, max_x, max_y]
        result["band_count"] = ds.RasterCount
        
        # Get Stats
        band = ds.GetRasterBand(1)
        stats = band.GetStatistics(True, True)
        result["min_val"] = stats[0]
        result["max_val"] = stats[1]
        
        # Get CRS
        proj = ds.GetProjectionRef()
        if "4326" in proj or "WGS 84" in proj:
            result["crs_auth"] = "EPSG:4326"
            
        ds = None
except Exception as e:
    result["error"] = str(e)

print(json.dumps(result))
PYEOF
    )
    
    # Check modification time
    FILE_MTIME=$(stat -c %Y "$EXPORT_PATH" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_NEW="true"
    else
        FILE_NEW="false"
    fi
else
    FILE_SIZE=0
    FILE_NEW="false"
    ANALYSIS_JSON='{"exists": false}'
fi

# 3. Cleanup QGIS
if is_qgis_running; then
    su - ga -c "DISPLAY=:1 xdotool key ctrl+q" 2>/dev/null || true
    sleep 2
    kill_qgis ga 2>/dev/null || true
fi

# 4. Save Result
cat > /tmp/task_result.json << EOF
{
    "file_exists": $([ -f "$EXPORT_PATH" ] && echo "true" || echo "false"),
    "file_path": "$EXPORT_PATH",
    "file_size_bytes": $FILE_SIZE,
    "file_created_during_task": $FILE_NEW,
    "analysis": $ANALYSIS_JSON,
    "timestamp": "$(date -Iseconds)"
}
EOF

chmod 666 /tmp/task_result.json 2>/dev/null || true
echo "Result:"
cat /tmp/task_result.json
echo "=== Export Complete ==="