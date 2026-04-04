#!/bin/bash
echo "=== Exporting heatmap_kde_population result ==="

source /workspace/scripts/task_utils.sh

# Fallback definitions
if ! type take_screenshot &>/dev/null; then
    take_screenshot() { DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true; }
fi
if ! type kill_qgis &>/dev/null; then
    kill_qgis() { pkill -u "${1:-ga}" -f qgis 2>/dev/null || true; sleep 1; }
fi
if ! type is_qgis_running &>/dev/null; then
    is_qgis_running() { pgrep -f "qgis" > /dev/null; }
fi

take_screenshot /tmp/task_end.png

# Paths
RASTER_PATH="/home/ga/GIS_Data/exports/population_heatmap.tif"
PROJECT_QGZ="/home/ga/GIS_Data/projects/heatmap_project.qgz"
PROJECT_QGS="/home/ga/GIS_Data/projects/heatmap_project.qgs"

# 1. Analyze Raster Output
RASTER_EXISTS="false"
RASTER_SIZE=0
RASTER_ANALYSIS='{}'

if [ -f "$RASTER_PATH" ]; then
    RASTER_EXISTS="true"
    RASTER_SIZE=$(stat -c%s "$RASTER_PATH" 2>/dev/null || echo "0")
    
    # Use Python + GDAL (installed in env) to inspect the raster content
    # We check: Driver, Dimensions, and basic statistics (min/max) to ensure it's not empty/flat
    RASTER_ANALYSIS=$(python3 << 'PYEOF'
import json
import sys
try:
    from osgeo import gdal
    gdal.UseExceptions()
    
    ds = gdal.Open("/home/ga/GIS_Data/exports/population_heatmap.tif")
    if not ds:
        print(json.dumps({"valid": False, "error": "Could not open file"}))
        sys.exit(0)
        
    width = ds.RasterXSize
    height = ds.RasterYSize
    bands = ds.RasterCount
    driver = ds.GetDriver().ShortName
    
    # Check stats for first band
    band = ds.GetRasterBand(1)
    stats = band.GetStatistics(True, True) # min, max, mean, stddev
    minimum, maximum, mean, stddev = stats
    
    # Check geotransform for pixel size
    gt = ds.GetGeoTransform()
    pixel_size_x = gt[1]
    pixel_size_y = -gt[5] # Usually negative
    
    print(json.dumps({
        "valid": True,
        "driver": driver,
        "width": width,
        "height": height,
        "bands": bands,
        "min_value": minimum,
        "max_value": maximum,
        "mean_value": mean,
        "pixel_size_x": pixel_size_x,
        "pixel_size_y": pixel_size_y,
        "has_data": maximum > 0 # Should have some density
    }))
    
except Exception as e:
    print(json.dumps({"valid": False, "error": str(e)}))
PYEOF
    )
else
    # Check if user saved with different name
    ALT_FILE=$(find "/home/ga/GIS_Data/exports" -name "*heatmap*.tif" -mmin -10 2>/dev/null | head -1)
    if [ -n "$ALT_FILE" ]; then
        RASTER_EXISTS="true"
        RASTER_SIZE=$(stat -c%s "$ALT_FILE" 2>/dev/null || echo "0")
        RASTER_PATH="$ALT_FILE"
        RASTER_ANALYSIS='{"valid": true, "note": "alternative file found, content check skipped"}'
    else
        RASTER_ANALYSIS='{"valid": false}'
    fi
fi

# 2. Analyze Project File
PROJECT_EXISTS="false"
PROJECT_VALID="false"
PROJECT_PATH=""

if [ -f "$PROJECT_QGZ" ]; then
    PROJECT_EXISTS="true"
    PROJECT_PATH="$PROJECT_QGZ"
    if file "$PROJECT_QGZ" | grep -qi "zip"; then
        PROJECT_VALID="true"
    fi
elif [ -f "$PROJECT_QGS" ]; then
    PROJECT_EXISTS="true"
    PROJECT_PATH="$PROJECT_QGS"
    if head -1 "$PROJECT_QGS" | grep -q "xml"; then
        PROJECT_VALID="true"
    fi
fi

# 3. Check timestamps (Anti-gaming)
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
FILE_MTIME=$(stat -c %Y "$RASTER_PATH" 2>/dev/null || echo "0")
CREATED_DURING_TASK="false"
if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
    CREATED_DURING_TASK="true"
fi

# Close QGIS
if is_qgis_running; then
    su - ga -c "DISPLAY=:1 xdotool key ctrl+q" 2>/dev/null || true
    sleep 2
    kill_qgis ga 2>/dev/null || true
fi

# 4. Generate Result JSON
cat > /tmp/task_result.json << EOF
{
    "raster_exists": $RASTER_EXISTS,
    "raster_path": "$RASTER_PATH",
    "raster_size_bytes": $RASTER_SIZE,
    "raster_analysis": $RASTER_ANALYSIS,
    "project_exists": $PROJECT_EXISTS,
    "project_valid": $PROJECT_VALID,
    "created_during_task": $CREATED_DURING_TASK,
    "timestamp": "$(date -Iseconds)"
}
EOF

chmod 666 /tmp/task_result.json 2>/dev/null || true
echo "Result:"
cat /tmp/task_result.json
echo "=== Export Complete ==="