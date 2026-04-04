#!/bin/bash
echo "=== Exporting georeference_map_with_saved_gcps result ==="

source /workspace/scripts/task_utils.sh

# Fallback definitions
if ! type take_screenshot &>/dev/null; then
    take_screenshot() { DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true; }
fi
if ! type is_qgis_running &>/dev/null; then
    is_qgis_running() { pgrep -f "qgis" > /dev/null; }
fi
if ! type kill_qgis &>/dev/null; then
    kill_qgis() { pkill -u "${1:-ga}" -f qgis 2>/dev/null || true; sleep 1; }
fi

# 1. Take Final Screenshot
take_screenshot /tmp/task_end.png

# 2. Define Paths
OUTPUT_PATH="/home/ga/GIS_Data/exports/historical_map_georeferenced.tif"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
CURRENT_TIME=$(date +%s)

# 3. Analyze Output File
FILE_EXISTS="false"
FILE_SIZE=0
FILE_CREATED_DURING_TASK="false"
METADATA_JSON='{}'

if [ -f "$OUTPUT_PATH" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c%s "$OUTPUT_PATH" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat -c%Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi

    # Extract GeoTIFF Metadata using Python/GDAL
    # We use a python script to be robust against missing gdalinfo binary, though environment should have it.
    METADATA_JSON=$(python3 << 'PYEOF'
import json
import os
import sys

try:
    from osgeo import gdal, osr
    gdal.UseExceptions()
    
    ds = gdal.Open("/home/ga/GIS_Data/exports/historical_map_georeferenced.tif")
    if not ds:
        raise Exception("Could not open dataset")
        
    # Get CRS
    proj = osr.SpatialReference(wkt=ds.GetProjection())
    crs_auth = "Unknown"
    if proj.IsProjected():
        crs_auth = f"{proj.GetAuthorityName(None)}:{proj.GetAuthorityCode(None)}"
    elif proj.IsGeographic():
        crs_auth = f"{proj.GetAuthorityName(None)}:{proj.GetAuthorityCode(None)}"
        
    # Get Geotransform
    gt = ds.GetGeoTransform()
    # gt[0] = top left x
    # gt[1] = w-e pixel resolution
    # gt[2] = 0
    # gt[3] = top left y
    # gt[4] = 0
    # gt[5] = n-s pixel resolution (negative)
    
    width = ds.RasterXSize
    height = ds.RasterYSize
    
    print(json.dumps({
        "valid_tiff": True,
        "crs": crs_auth,
        "origin_x": gt[0],
        "origin_y": gt[3],
        "pixel_size_x": gt[1],
        "pixel_size_y": gt[5],
        "width": width,
        "height": height,
        "projection_wkt": ds.GetProjection()
    }))
    
except Exception as e:
    # Fallback if GDAL fails or not installed
    print(json.dumps({
        "valid_tiff": False,
        "error": str(e)
    }))
PYEOF
    )
else
    # Check for alternative filename just in case
    ALT_FILE=$(find /home/ga/GIS_Data/exports -name "*.tif" -mmin -10 2>/dev/null | head -1)
    if [ -n "$ALT_FILE" ]; then
        METADATA_JSON="{\"valid_tiff\": false, \"note\": \"Alternative file found: $ALT_FILE\", \"alt_path\": \"$ALT_FILE\"}"
    else
        METADATA_JSON='{"valid_tiff": false, "error": "File not found"}'
    fi
fi

# 4. Check if QGIS is running
APP_RUNNING=$(is_qgis_running && echo "true" || echo "false")

# 5. Clean up QGIS
if [ "$APP_RUNNING" = "true" ]; then
    su - ga -c "DISPLAY=:1 xdotool key ctrl+q" 2>/dev/null || true
    sleep 2
    kill_qgis ga 2>/dev/null || true
fi

# 6. Save Result
cat > /tmp/task_result.json << EOF
{
    "task_start": $TASK_START,
    "task_end": $CURRENT_TIME,
    "file_exists": $FILE_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "file_size_bytes": $FILE_SIZE,
    "app_was_running": $APP_RUNNING,
    "metadata": $METADATA_JSON
}
EOF

# Ensure permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result:"
cat /tmp/task_result.json
echo "=== Export Complete ==="