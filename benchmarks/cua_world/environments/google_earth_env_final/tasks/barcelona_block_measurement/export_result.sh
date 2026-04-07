#!/bin/bash
set -e
echo "=== Exporting Barcelona Block Measurement task result ==="

export DISPLAY=${DISPLAY:-:1}

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
echo "Task duration: $((TASK_END - TASK_START)) seconds"

# Capture final screenshot BEFORE any cleanup
echo "Capturing final state screenshot..."
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

if [ -f /tmp/task_final.png ]; then
    SCREENSHOT_SIZE=$(stat -c %s /tmp/task_final.png 2>/dev/null || echo "0")
    echo "Final screenshot captured: ${SCREENSHOT_SIZE} bytes"
    SCREENSHOT_EXISTS="true"
else
    echo "WARNING: Could not capture final screenshot"
    SCREENSHOT_EXISTS="false"
fi

# Check output KML file
OUTPUT_PATH="/home/ga/Documents/barcelona_block.kml"
ALT_OUTPUT_PATH="/home/ga/Documents/barcelona_block.kmz"

OUTPUT_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
OUTPUT_SIZE="0"
OUTPUT_MTIME="0"
OUTPUT_FORMAT="none"
ACTUAL_OUTPUT_PATH=""

# Check for KML file first
if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c %s "$OUTPUT_PATH" 2>/dev/null || echo "0")
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    OUTPUT_FORMAT="kml"
    ACTUAL_OUTPUT_PATH="$OUTPUT_PATH"
    
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
    echo "Found KML file: $OUTPUT_PATH ($OUTPUT_SIZE bytes)"
# Check for KMZ file as alternative
elif [ -f "$ALT_OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c %s "$ALT_OUTPUT_PATH" 2>/dev/null || echo "0")
    OUTPUT_MTIME=$(stat -c %Y "$ALT_OUTPUT_PATH" 2>/dev/null || echo "0")
    OUTPUT_FORMAT="kmz"
    ACTUAL_OUTPUT_PATH="$ALT_OUTPUT_PATH"
    
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
    echo "Found KMZ file: $ALT_OUTPUT_PATH ($OUTPUT_SIZE bytes)"
else
    echo "No output file found at $OUTPUT_PATH or $ALT_OUTPUT_PATH"
fi

# Check if Google Earth is still running
GE_RUNNING="false"
if pgrep -f "google-earth" > /dev/null 2>&1; then
    GE_RUNNING="true"
fi
echo "Google Earth running: $GE_RUNNING"

# Get window information
WINDOW_INFO=""
if DISPLAY=:1 wmctrl -l | grep -qi "Google Earth"; then
    WINDOW_INFO=$(DISPLAY=:1 wmctrl -l | grep -i "Google Earth" | head -1)
fi

# Try to extract polygon data from KML if it exists
POLYGON_DATA=""
COORD_COUNT="0"
CENTROID_LAT="0"
CENTROID_LON="0"

if [ "$OUTPUT_EXISTS" = "true" ] && [ "$OUTPUT_FORMAT" = "kml" ]; then
    echo "Parsing KML file for polygon data..."
    
    # Extract coordinates using Python
    POLYGON_DATA=$(python3 << 'PYEOF'
import xml.etree.ElementTree as ET
import json
import sys

try:
    tree = ET.parse("/home/ga/Documents/barcelona_block.kml")
    root = tree.getroot()
    
    # Handle KML namespace
    ns = {'kml': 'http://www.opengis.net/kml/2.2'}
    
    # Try with namespace first
    coords_elem = root.find('.//kml:coordinates', ns)
    if coords_elem is None:
        # Try without namespace
        coords_elem = root.find('.//coordinates')
    
    if coords_elem is not None and coords_elem.text:
        coords_text = coords_elem.text.strip()
        coords = []
        for point in coords_text.split():
            parts = point.split(',')
            if len(parts) >= 2:
                lon = float(parts[0])
                lat = float(parts[1])
                coords.append({"lon": lon, "lat": lat})
        
        if coords:
            centroid_lon = sum(c["lon"] for c in coords) / len(coords)
            centroid_lat = sum(c["lat"] for c in coords) / len(coords)
            print(json.dumps({
                "success": True,
                "coord_count": len(coords),
                "centroid_lat": centroid_lat,
                "centroid_lon": centroid_lon,
                "coordinates": coords
            }))
        else:
            print(json.dumps({"success": False, "error": "No coordinates parsed"}))
    else:
        print(json.dumps({"success": False, "error": "No coordinates element found"}))
        
except Exception as e:
    print(json.dumps({"success": False, "error": str(e)}))
PYEOF
)
    
    echo "Polygon data: $POLYGON_DATA"
    
    # Extract values from parsed data
    if echo "$POLYGON_DATA" | python3 -c "import json,sys; d=json.load(sys.stdin); sys.exit(0 if d.get('success') else 1)" 2>/dev/null; then
        COORD_COUNT=$(echo "$POLYGON_DATA" | python3 -c "import json,sys; print(json.load(sys.stdin).get('coord_count', 0))")
        CENTROID_LAT=$(echo "$POLYGON_DATA" | python3 -c "import json,sys; print(json.load(sys.stdin).get('centroid_lat', 0))")
        CENTROID_LON=$(echo "$POLYGON_DATA" | python3 -c "import json,sys; print(json.load(sys.stdin).get('centroid_lon', 0))")
    fi
fi

# Handle KMZ file (compressed KML)
if [ "$OUTPUT_EXISTS" = "true" ] && [ "$OUTPUT_FORMAT" = "kmz" ]; then
    echo "Extracting KML from KMZ file..."
    TEMP_DIR=$(mktemp -d)
    unzip -q "$ALT_OUTPUT_PATH" -d "$TEMP_DIR" 2>/dev/null || true
    
    # Find and copy doc.kml
    if [ -f "$TEMP_DIR/doc.kml" ]; then
        cp "$TEMP_DIR/doc.kml" "/tmp/extracted_doc.kml"
        echo "Extracted doc.kml from KMZ"
    fi
    rm -rf "$TEMP_DIR"
fi

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "task_duration_seconds": $((TASK_END - TASK_START)),
    "output_exists": $OUTPUT_EXISTS,
    "output_path": "$ACTUAL_OUTPUT_PATH",
    "output_format": "$OUTPUT_FORMAT",
    "output_size_bytes": $OUTPUT_SIZE,
    "output_mtime": $OUTPUT_MTIME,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "google_earth_running": $GE_RUNNING,
    "screenshot_exists": $SCREENSHOT_EXISTS,
    "screenshot_path": "/tmp/task_final.png",
    "polygon_coord_count": $COORD_COUNT,
    "centroid_lat": $CENTROID_LAT,
    "centroid_lon": $CENTROID_LON,
    "window_info": "$WINDOW_INFO"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

# Also copy the KML file to /tmp for easier access by verifier
if [ -f "$OUTPUT_PATH" ]; then
    cp "$OUTPUT_PATH" /tmp/barcelona_block.kml 2>/dev/null || true
    chmod 666 /tmp/barcelona_block.kml 2>/dev/null || true
fi

echo ""
echo "=== Export complete ==="
echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json