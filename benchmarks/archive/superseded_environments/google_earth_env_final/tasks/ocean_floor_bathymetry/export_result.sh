#!/bin/bash
set -e
echo "=== Exporting Ocean Floor Bathymetry Task Result ==="

export DISPLAY=${DISPLAY:-:1}

# Take final screenshot FIRST (for VLM verification)
echo "Capturing final state..."
DISPLAY=:1 scrot /tmp/task_final_screenshot.png 2>/dev/null || true

# Get task timing
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# ================================================================
# CHECK SURFACE SCREENSHOT
# ================================================================
SURFACE_PATH="/home/ga/Documents/atlantic_surface.png"
SURFACE_EXISTS="false"
SURFACE_SIZE="0"
SURFACE_MTIME="0"
SURFACE_CREATED_DURING_TASK="false"

if [ -f "$SURFACE_PATH" ]; then
    SURFACE_EXISTS="true"
    SURFACE_SIZE=$(stat -c %s "$SURFACE_PATH" 2>/dev/null || echo "0")
    SURFACE_MTIME=$(stat -c %Y "$SURFACE_PATH" 2>/dev/null || echo "0")
    
    if [ "$SURFACE_MTIME" -gt "$TASK_START" ]; then
        SURFACE_CREATED_DURING_TASK="true"
    fi
    echo "Surface screenshot: exists=$SURFACE_EXISTS, size=$SURFACE_SIZE, created_during_task=$SURFACE_CREATED_DURING_TASK"
else
    echo "Surface screenshot: NOT FOUND"
fi

# ================================================================
# CHECK BATHYMETRY SCREENSHOT
# ================================================================
BATHY_PATH="/home/ga/Documents/atlantic_bathymetry.png"
BATHY_EXISTS="false"
BATHY_SIZE="0"
BATHY_MTIME="0"
BATHY_CREATED_DURING_TASK="false"

if [ -f "$BATHY_PATH" ]; then
    BATHY_EXISTS="true"
    BATHY_SIZE=$(stat -c %s "$BATHY_PATH" 2>/dev/null || echo "0")
    BATHY_MTIME=$(stat -c %Y "$BATHY_PATH" 2>/dev/null || echo "0")
    
    if [ "$BATHY_MTIME" -gt "$TASK_START" ]; then
        BATHY_CREATED_DURING_TASK="true"
    fi
    echo "Bathymetry screenshot: exists=$BATHY_EXISTS, size=$BATHY_SIZE, created_during_task=$BATHY_CREATED_DURING_TASK"
else
    echo "Bathymetry screenshot: NOT FOUND"
fi

# ================================================================
# COMPARE SCREENSHOTS (if both exist)
# ================================================================
SCREENSHOTS_DIFFERENT="false"
IMAGE_DIFFERENCE="0"

if [ "$SURFACE_EXISTS" = "true" ] && [ "$BATHY_EXISTS" = "true" ]; then
    # Use Python to calculate image difference
    IMAGE_DIFF_RESULT=$(python3 << 'PYEOF'
import sys
try:
    from PIL import Image
    import numpy as np
    
    img1 = Image.open("/home/ga/Documents/atlantic_surface.png").convert('RGB')
    img2 = Image.open("/home/ga/Documents/atlantic_bathymetry.png").convert('RGB')
    
    arr1 = np.array(img1, dtype=np.float32)
    arr2 = np.array(img2, dtype=np.float32)
    
    if arr1.shape == arr2.shape:
        diff = np.mean(np.abs(arr1 - arr2))
        print(f"{diff:.2f}")
    else:
        # Different dimensions = definitely different
        print("100.0")
except Exception as e:
    print("0")
    sys.stderr.write(f"Error: {e}\n")
PYEOF
)
    IMAGE_DIFFERENCE="$IMAGE_DIFF_RESULT"
    
    # Check if difference is significant (> 10 pixel difference on average)
    IS_DIFF=$(python3 -c "print('true' if float('$IMAGE_DIFFERENCE') > 10 else 'false')" 2>/dev/null || echo "false")
    SCREENSHOTS_DIFFERENT="$IS_DIFF"
    
    echo "Image difference: $IMAGE_DIFFERENCE (different=$SCREENSHOTS_DIFFERENT)"
fi

# ================================================================
# CHECK PLACEMARKS
# ================================================================
PLACEMARK_COUNT="0"
INITIAL_COUNT=$(cat /tmp/initial_placemark_count.txt 2>/dev/null || echo "0")
NEW_PLACEMARKS="false"
PLACEMARK_DATA=""

if [ -f /home/ga/.googleearth/myplaces.kml ]; then
    PLACEMARK_COUNT=$(grep -c "<Placemark>" /home/ga/.googleearth/myplaces.kml 2>/dev/null || echo "0")
    
    if [ "$PLACEMARK_COUNT" -gt "$INITIAL_COUNT" ]; then
        NEW_PLACEMARKS="true"
    fi
    
    # Extract placemark data (names and coordinates)
    PLACEMARK_DATA=$(python3 << 'PYEOF'
import xml.etree.ElementTree as ET
import json

try:
    tree = ET.parse('/home/ga/.googleearth/myplaces.kml')
    root = tree.getroot()
    
    ns = {'kml': 'http://www.opengis.net/kml/2.2'}
    placemarks = []
    
    # Try with namespace
    for pm in root.findall('.//kml:Placemark', ns):
        name_elem = pm.find('kml:name', ns)
        coords_elem = pm.find('.//kml:coordinates', ns)
        
        if name_elem is not None:
            name = name_elem.text or ""
            coords = ""
            if coords_elem is not None and coords_elem.text:
                coords = coords_elem.text.strip()
            placemarks.append({"name": name, "coords": coords})
    
    # Try without namespace if nothing found
    if not placemarks:
        for pm in root.findall('.//Placemark'):
            name_elem = pm.find('name')
            coords_elem = pm.find('.//coordinates')
            
            if name_elem is not None:
                name = name_elem.text or ""
                coords = ""
                if coords_elem is not None and coords_elem.text:
                    coords = coords_elem.text.strip()
                placemarks.append({"name": name, "coords": coords})
    
    print(json.dumps(placemarks))
except Exception as e:
    print("[]")
PYEOF
)
fi

echo "Placemarks: initial=$INITIAL_COUNT, current=$PLACEMARK_COUNT, new=$NEW_PLACEMARKS"

# ================================================================
# CHECK GOOGLE EARTH STATE
# ================================================================
GE_RUNNING="false"
if pgrep -f "google-earth" > /dev/null 2>&1; then
    GE_RUNNING="true"
fi

WINDOW_TITLE=$(DISPLAY=:1 xdotool getactivewindow getwindowname 2>/dev/null || echo "unknown")

# ================================================================
# CREATE RESULT JSON
# ================================================================
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)

cat > "$TEMP_JSON" << EOF
{
    "task_start_time": $TASK_START,
    "task_end_time": $TASK_END,
    "google_earth_running": $GE_RUNNING,
    "window_title": "$WINDOW_TITLE",
    "surface_screenshot": {
        "exists": $SURFACE_EXISTS,
        "size_bytes": $SURFACE_SIZE,
        "mtime": $SURFACE_MTIME,
        "created_during_task": $SURFACE_CREATED_DURING_TASK
    },
    "bathymetry_screenshot": {
        "exists": $BATHY_EXISTS,
        "size_bytes": $BATHY_SIZE,
        "mtime": $BATHY_MTIME,
        "created_during_task": $BATHY_CREATED_DURING_TASK
    },
    "screenshots_different": $SCREENSHOTS_DIFFERENT,
    "image_difference": $IMAGE_DIFFERENCE,
    "placemarks": {
        "initial_count": $INITIAL_COUNT,
        "current_count": $PLACEMARK_COUNT,
        "new_placemarks_created": $NEW_PLACEMARKS,
        "data": $PLACEMARK_DATA
    },
    "final_screenshot_path": "/tmp/task_final_screenshot.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "=== Export complete ==="
echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json