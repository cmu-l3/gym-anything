#!/bin/bash
echo "=== Exporting simplify_geometries_web_export result ==="

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

# 1. Capture final state
take_screenshot /tmp/task_end.png

# 2. Locate output file
EXPORT_DIR="/home/ga/GIS_Data/exports"
EXPECTED_FILE="$EXPORT_DIR/countries_simplified.geojson"
ALT_FILE="$EXPORT_DIR/countries_simplified.json"

FILE_PATH=""
if [ -f "$EXPECTED_FILE" ]; then
    FILE_PATH="$EXPECTED_FILE"
elif [ -f "$ALT_FILE" ]; then
    FILE_PATH="$ALT_FILE"
else
    # Look for any recent GeoJSON in the export folder
    RECENT=$(find "$EXPORT_DIR" -name "*.geojson" -mmin -15 2>/dev/null | head -1)
    if [ -n "$RECENT" ]; then
        FILE_PATH="$RECENT"
    fi
fi

# 3. Analyze result
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
INPUT_VERTEX_COUNT=$(cat /tmp/input_vertex_count.txt 2>/dev/null || echo "58000")

FILE_EXISTS="false"
FILE_SIZE=0
IS_NEW="false"
ANALYSIS="{}"

if [ -n "$FILE_PATH" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c%s "$FILE_PATH" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat -c%Y "$FILE_PATH" 2>/dev/null || echo "0")
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        IS_NEW="true"
    fi

    # Python script to analyze GeoJSON structure, features, and vertex count
    ANALYSIS=$(python3 << PYEOF
import json
import sys

try:
    with open("$FILE_PATH", 'r') as f:
        data = json.load(f)
    
    if data.get('type') != 'FeatureCollection':
        print(json.dumps({'valid': False, 'error': 'Not a FeatureCollection'}))
        sys.exit(0)
        
    features = data.get('features', [])
    feature_count = len(features)
    
    vertex_count = 0
    polygon_count = 0
    invalid_geoms = 0
    
    for feat in features:
        geom = feat.get('geometry')
        if not geom:
            continue
            
        g_type = geom.get('type')
        coords = geom.get('coordinates', [])
        
        if g_type == 'Polygon':
            polygon_count += 1
            for ring in coords:
                vertex_count += len(ring)
        elif g_type == 'MultiPolygon':
            polygon_count += 1
            for poly in coords:
                for ring in poly:
                    vertex_count += len(ring)
        else:
            invalid_geoms += 1
            
    print(json.dumps({
        'valid': True,
        'feature_count': feature_count,
        'vertex_count': vertex_count,
        'polygon_count': polygon_count,
        'invalid_geom_count': invalid_geoms
    }))
    
except Exception as e:
    print(json.dumps({'valid': False, 'error': str(e)}))
PYEOF
    )
fi

# 4. Close QGIS
if is_qgis_running; then
    su - ga -c "DISPLAY=:1 xdotool key ctrl+q" 2>/dev/null || true
    sleep 2
    kill_qgis ga 2>/dev/null || true
fi

# 5. Create result JSON
cat > /tmp/task_result.json << EOF
{
    "file_exists": $FILE_EXISTS,
    "file_path": "$FILE_PATH",
    "file_size_bytes": $FILE_SIZE,
    "is_new": $IS_NEW,
    "input_vertex_count": $INPUT_VERTEX_COUNT,
    "analysis": $ANALYSIS,
    "timestamp": "$(date -Iseconds)"
}
EOF

chmod 666 /tmp/task_result.json 2>/dev/null || true
echo "Result:"
cat /tmp/task_result.json
echo "=== Export Complete ==="