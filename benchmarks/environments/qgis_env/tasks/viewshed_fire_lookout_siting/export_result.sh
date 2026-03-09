#!/bin/bash
echo "=== Exporting Viewshed Analysis Result ==="

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

take_screenshot /tmp/task_end.png

EXPORT_DIR="/home/ga/GIS_Data/exports"
RASTER_DIR="/home/ga/GIS_Data/rasters"
EXPECTED_FILE="$EXPORT_DIR/fire_lookout_viewshed.tif"
REPROJECTED_FILE="$RASTER_DIR/dem_reprojected.tif"

INITIAL_COUNT=$(cat /tmp/initial_export_count 2>/dev/null || echo "0")
CURRENT_COUNT=$(ls -1 "$EXPORT_DIR"/*.tif 2>/dev/null | wc -l || echo "0")

FILE_EXISTS="false"
FILE_SIZE=0
REPROJECTED_EXISTS="false"

# Check reprojected file (intermediate artifact)
if [ -f "$REPROJECTED_FILE" ]; then
    REPROJECTED_EXISTS="true"
fi

# Analyze Output Raster
ANALYSIS_JSON='{}'

if [ -f "$EXPECTED_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c%s "$EXPECTED_FILE" 2>/dev/null || echo "0")

    # Use Python/GDAL to analyze the raster content
    ANALYSIS_JSON=$(python3 << 'PYEOF'
import json
import sys
import numpy as np
try:
    from osgeo import gdal, osr
except ImportError:
    # If gdal not available in system python, try qgis python
    print(json.dumps({"error": "gdal_not_found"}))
    sys.exit(0)

def analyze_raster(path):
    try:
        ds = gdal.Open(path)
        if not ds:
            return {"valid": False, "error": "Could not open file"}
        
        # Check CRS
        proj = ds.GetProjection()
        srs = osr.SpatialReference(wkt=proj)
        # Handle different GDAL versions and auth names
        auth_name = srs.GetAuthorityName(None)
        auth_code = srs.GetAuthorityCode(None)
        
        is_utm_34s = False
        if auth_code == "32734":
            is_utm_34s = True
        
        # Check dimensions
        width = ds.RasterXSize
        height = ds.RasterYSize
        
        # Check band stats (is it binary?)
        band = ds.GetRasterBand(1)
        stats = band.GetStatistics(True, True)
        min_val, max_val = stats[0], stats[1]
        
        # Sample data to check for binary-ness
        # Read a small block
        data = band.ReadAsArray()
        unique_vals = np.unique(data)
        
        is_binary = False
        if len(unique_vals) <= 3: # 0, 1, and maybe nodata
             is_binary = True
        
        # Calculate visible area percentage
        # Assuming 1 or 255 is visible
        visible_pixels = np.sum((data == 1) | (data == 255))
        total_pixels = data.size
        visible_ratio = float(visible_pixels) / float(total_pixels)

        return {
            "valid": True,
            "crs_auth": str(auth_code),
            "is_utm_34s": is_utm_34s,
            "width": width,
            "height": height,
            "min_val": min_val,
            "max_val": max_val,
            "unique_count": int(len(unique_vals)),
            "is_binary": is_binary,
            "visible_ratio": visible_ratio
        }
    except Exception as e:
        return {"valid": False, "error": str(e)}

print(json.dumps(analyze_raster("/home/ga/GIS_Data/exports/fire_lookout_viewshed.tif")))
PYEOF
    )
else
    ANALYSIS_JSON='{"valid": false, "file_not_found": true}'
fi

# Close QGIS
if is_qgis_running; then
    su - ga -c "DISPLAY=:1 xdotool key ctrl+q" 2>/dev/null || true
    sleep 2
    kill_qgis ga 2>/dev/null || true
fi

cat > /tmp/task_result.json << EOF
{
    "initial_export_count": $INITIAL_COUNT,
    "current_export_count": $CURRENT_COUNT,
    "file_exists": $FILE_EXISTS,
    "reprojected_exists": $REPROJECTED_EXISTS,
    "file_path": "$EXPECTED_FILE",
    "file_size_bytes": $FILE_SIZE,
    "analysis": $ANALYSIS_JSON,
    "timestamp": "$(date -Iseconds)"
}
EOF

chmod 666 /tmp/task_result.json 2>/dev/null || true
echo "Result:"
cat /tmp/task_result.json
echo "=== Export Complete ==="