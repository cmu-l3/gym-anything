#!/bin/bash
echo "=== Exporting idw_interpolation_earthquake_raster result ==="

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

# 1. Capture Final State
take_screenshot /tmp/task_final.png

OUTPUT_FILE="/home/ga/GIS_Data/exports/earthquake_magnitude_surface.tif"
PROJECT_FILE_QGZ="/home/ga/GIS_Data/projects/earthquake_interpolation.qgz"
PROJECT_FILE_QGS="/home/ga/GIS_Data/projects/earthquake_interpolation.qgs"

TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "0")

# 2. Analyze Output Raster using gdalinfo
FILE_EXISTS="false"
FILE_SIZE=0
IS_VALID_TIFF="false"
GDAL_INFO_JSON="{}"
FILE_CREATED_DURING_TASK="false"

if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c%s "$OUTPUT_FILE")
    FILE_MTIME=$(stat -c%Y "$OUTPUT_FILE")
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi

    # Check validity with gdalinfo
    if command -v gdalinfo &> /dev/null; then
        # Capture full JSON info
        if gdalinfo -json "$OUTPUT_FILE" > /tmp/gdal_info.json 2>/dev/null; then
            IS_VALID_TIFF="true"
            # Read relevant parts into a simplified variable if needed, or just keep file
        else
            # Fallback for older GDAL without -json or if it fails
            gdalinfo "$OUTPUT_FILE" > /tmp/gdal_info.txt
            if grep -q "Driver: GTiff" /tmp/gdal_info.txt; then
                IS_VALID_TIFF="true"
                # Construct basic JSON manually
                X_SIZE=$(grep "Size is" /tmp/gdal_info.txt | grep -o "[0-9]*, [0-9]*" | cut -d, -f1)
                Y_SIZE=$(grep "Size is" /tmp/gdal_info.txt | grep -o "[0-9]*, [0-9]*" | cut -d, -f2 | tr -d ' ')
                cat > /tmp/gdal_info.json << EOF
{
  "driverShortName": "GTiff",
  "size": [$X_SIZE, $Y_SIZE],
  "bands": [{"metadata": {}}]
}
EOF
            fi
        fi
    else
        # Fallback if gdalinfo missing (unlikely in this env)
        if head -c 4 "$OUTPUT_FILE" | grep -q "II\|MM"; then
             IS_VALID_TIFF="true"
             echo '{"driverShortName": "GTiff"}' > /tmp/gdal_info.json
        fi
    fi
else
    echo "{}" > /tmp/gdal_info.json
fi

# 3. Check Project File
PROJECT_EXISTS="false"
if [ -f "$PROJECT_FILE_QGZ" ] || [ -f "$PROJECT_FILE_QGS" ]; then
    PROJECT_EXISTS="true"
fi

# 4. Cleanup
if is_qgis_running; then
    su - ga -c "DISPLAY=:1 xdotool key ctrl+q" 2>/dev/null || true
    sleep 2
    kill_qgis ga 2>/dev/null || true
fi

# 5. Create Result JSON
# Read the gdal info content safely
GDAL_CONTENT=$(cat /tmp/gdal_info.json 2>/dev/null || echo "{}")

# Use python to construct valid JSON
python3 -c "
import json
import os

try:
    gdal_info = json.loads('''$GDAL_CONTENT''')
except:
    gdal_info = {}

result = {
    'file_exists': $FILE_EXISTS,
    'file_size_bytes': $FILE_SIZE,
    'file_created_during_task': $FILE_CREATED_DURING_TASK,
    'is_valid_tiff': $IS_VALID_TIFF,
    'project_exists': $PROJECT_EXISTS,
    'gdal_info': gdal_info,
    'timestamp': '$(date -Iseconds)'
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
"

# Move to standard location with permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="