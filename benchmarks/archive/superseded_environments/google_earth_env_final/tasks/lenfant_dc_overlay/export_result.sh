#!/bin/bash
set -e
echo "=== Exporting L'Enfant Overlay Task Result ==="

export DISPLAY=${DISPLAY:-:1}

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
echo "Capturing final state..."
scrot /tmp/task_final_state.png 2>/dev/null || \
    import -window root /tmp/task_final_state.png 2>/dev/null || true

SCREENSHOT_EXISTS="false"
SCREENSHOT_SIZE=0
if [ -f /tmp/task_final_state.png ]; then
    SCREENSHOT_EXISTS="true"
    SCREENSHOT_SIZE=$(stat -c %s /tmp/task_final_state.png 2>/dev/null || echo "0")
    echo "Final screenshot captured: ${SCREENSHOT_SIZE} bytes"
fi

# Check if Google Earth is still running
GE_RUNNING="false"
if pgrep -f google-earth-pro > /dev/null 2>&1; then
    GE_RUNNING="true"
fi

# Get window title
WINDOW_TITLE=$(xdotool getactivewindow getwindowname 2>/dev/null || echo "unknown")

# Check My Places KML files for ground overlays
MYPLACES="/home/ga/.googleearth/myplaces.kml"
MYPLACES_ALT="/home/ga/.config/Google/GoogleEarthPro/myplaces.kml"

MYPLACES_FILE=""
if [ -f "$MYPLACES" ]; then
    MYPLACES_FILE="$MYPLACES"
elif [ -f "$MYPLACES_ALT" ]; then
    MYPLACES_FILE="$MYPLACES_ALT"
fi

# Count ground overlays
OVERLAY_COUNT=0
INITIAL_COUNT=$(cat /tmp/initial_overlay_count.txt 2>/dev/null || echo "0")
OVERLAY_ADDED="false"
OVERLAY_NAME_FOUND=""
OVERLAY_HREF_FOUND=""
HAS_LENFANT_OVERLAY="false"
OVERLAY_BOUNDS=""

if [ -n "$MYPLACES_FILE" ] && [ -f "$MYPLACES_FILE" ]; then
    OVERLAY_COUNT=$(grep -c "<GroundOverlay>" "$MYPLACES_FILE" 2>/dev/null || echo "0")
    
    if [ "$OVERLAY_COUNT" -gt "$INITIAL_COUNT" ]; then
        OVERLAY_ADDED="true"
    fi
    
    # Extract overlay details using Python for reliable parsing
    python3 << 'PYEOF' > /tmp/overlay_details.json 2>/dev/null || echo '{}' > /tmp/overlay_details.json
import xml.etree.ElementTree as ET
import json
import re

myplaces_files = [
    "/home/ga/.googleearth/myplaces.kml",
    "/home/ga/.config/Google/GoogleEarthPro/myplaces.kml"
]

overlays = []
for kml_path in myplaces_files:
    try:
        # Read and clean the file (handle potential XML issues)
        with open(kml_path, 'r', encoding='utf-8', errors='ignore') as f:
            content = f.read()
        
        # Try to parse
        root = ET.fromstring(content)
        
        # Find all GroundOverlay elements (handle namespaces)
        for elem in root.iter():
            if 'GroundOverlay' in elem.tag:
                overlay = {
                    'name': '',
                    'href': '',
                    'color': 'ffffffff',
                    'north': None,
                    'south': None,
                    'east': None,
                    'west': None
                }
                
                for child in elem.iter():
                    tag = child.tag.split('}')[-1] if '}' in child.tag else child.tag
                    
                    if tag == 'name' and child.text:
                        overlay['name'] = child.text.strip()
                    elif tag == 'href' and child.text:
                        overlay['href'] = child.text.strip()
                    elif tag == 'color' and child.text:
                        overlay['color'] = child.text.strip()
                    elif tag == 'north' and child.text:
                        try:
                            overlay['north'] = float(child.text)
                        except:
                            pass
                    elif tag == 'south' and child.text:
                        try:
                            overlay['south'] = float(child.text)
                        except:
                            pass
                    elif tag == 'east' and child.text:
                        try:
                            overlay['east'] = float(child.text)
                        except:
                            pass
                    elif tag == 'west' and child.text:
                        try:
                            overlay['west'] = float(child.text)
                        except:
                            pass
                
                if overlay['name'] or overlay['href']:
                    overlays.append(overlay)
        
        if overlays:
            break  # Found overlays, stop searching
            
    except Exception as e:
        continue

# Find L'Enfant-related overlay
lenfant_overlay = None
patterns = ['lenfant', "l'enfant", '1791', 'plan']

for ov in overlays:
    name_lower = ov.get('name', '').lower()
    href_lower = ov.get('href', '').lower()
    
    for pattern in patterns:
        if pattern in name_lower or pattern in href_lower:
            lenfant_overlay = ov
            break
    if lenfant_overlay:
        break

result = {
    'total_overlays': len(overlays),
    'all_overlays': overlays,
    'lenfant_overlay': lenfant_overlay
}

print(json.dumps(result, indent=2))
PYEOF

    # Parse the overlay details
    if [ -f /tmp/overlay_details.json ]; then
        OVERLAY_DETAILS=$(cat /tmp/overlay_details.json)
        
        # Check if L'Enfant overlay was found
        HAS_LENFANT=$(echo "$OVERLAY_DETAILS" | python3 -c "import sys, json; d=json.load(sys.stdin); print('true' if d.get('lenfant_overlay') else 'false')" 2>/dev/null || echo "false")
        
        if [ "$HAS_LENFANT" = "true" ]; then
            HAS_LENFANT_OVERLAY="true"
            OVERLAY_NAME_FOUND=$(echo "$OVERLAY_DETAILS" | python3 -c "import sys, json; d=json.load(sys.stdin); print(d.get('lenfant_overlay', {}).get('name', ''))" 2>/dev/null || echo "")
            OVERLAY_HREF_FOUND=$(echo "$OVERLAY_DETAILS" | python3 -c "import sys, json; d=json.load(sys.stdin); print(d.get('lenfant_overlay', {}).get('href', ''))" 2>/dev/null || echo "")
        fi
    fi
fi

# Check if expected image file exists
IMAGE_PATH="/home/ga/Documents/HistoricalMaps/lenfant_plan_1791.jpg"
IMAGE_EXISTS="false"
if [ -f "$IMAGE_PATH" ]; then
    IMAGE_EXISTS="true"
fi

# Copy My Places KML for verifier
if [ -n "$MYPLACES_FILE" ] && [ -f "$MYPLACES_FILE" ]; then
    cp "$MYPLACES_FILE" /tmp/myplaces_final.kml 2>/dev/null || true
fi

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "task_duration_seconds": $((TASK_END - TASK_START)),
    "google_earth_running": $GE_RUNNING,
    "window_title": "$WINDOW_TITLE",
    "screenshot_exists": $SCREENSHOT_EXISTS,
    "screenshot_size": $SCREENSHOT_SIZE,
    "initial_overlay_count": $INITIAL_COUNT,
    "final_overlay_count": $OVERLAY_COUNT,
    "overlay_added": $OVERLAY_ADDED,
    "has_lenfant_overlay": $HAS_LENFANT_OVERLAY,
    "overlay_name_found": "$OVERLAY_NAME_FOUND",
    "overlay_href_found": "$OVERLAY_HREF_FOUND",
    "image_file_exists": $IMAGE_EXISTS,
    "myplaces_path": "$MYPLACES_FILE",
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "=== Export Results ==="
cat /tmp/task_result.json
echo ""
echo "=== Export complete ==="