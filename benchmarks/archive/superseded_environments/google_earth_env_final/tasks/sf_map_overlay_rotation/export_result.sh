#!/bin/bash
echo "=== Exporting SF Map Overlay Rotation task result ==="

export DISPLAY=${DISPLAY:-:1}

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

echo "Task timing: Start=$TASK_START, End=$TASK_END"

# =============================================================
# CAPTURE FINAL SCREENSHOT
# =============================================================
echo "Capturing final screenshot..."
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

SCREENSHOT_EXISTS="false"
if [ -f /tmp/task_final.png ]; then
    SCREENSHOT_SIZE=$(stat -c %s /tmp/task_final.png 2>/dev/null || echo "0")
    if [ "$SCREENSHOT_SIZE" -gt 1000 ]; then
        SCREENSHOT_EXISTS="true"
        echo "Final screenshot captured: $SCREENSHOT_SIZE bytes"
    fi
fi

# =============================================================
# CHECK KMZ OUTPUT FILE
# =============================================================
KMZ_PATH="/home/ga/Documents/sf_overlay.kmz"
KMZ_EXISTS="false"
KMZ_SIZE="0"
KMZ_MTIME="0"
FILE_CREATED_DURING_TASK="false"

if [ -f "$KMZ_PATH" ]; then
    KMZ_EXISTS="true"
    KMZ_SIZE=$(stat -c %s "$KMZ_PATH" 2>/dev/null || echo "0")
    KMZ_MTIME=$(stat -c %Y "$KMZ_PATH" 2>/dev/null || echo "0")
    
    # Check if file was created during the task
    if [ "$KMZ_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
        echo "KMZ file created during task: $KMZ_SIZE bytes"
    else
        echo "WARNING: KMZ file exists but was not created during task"
    fi
else
    echo "KMZ output file not found at $KMZ_PATH"
fi

# =============================================================
# EXTRACT AND ANALYZE KML FROM KMZ
# =============================================================
KML_CONTENT=""
HAS_GROUND_OVERLAY="false"
OVERLAY_NAME=""
ROTATION_VALUE=""
OPACITY_VALUE=""
NORTH_BOUND=""
SOUTH_BOUND=""
EAST_BOUND=""
WEST_BOUND=""
HAS_IMAGE_REF="false"

if [ "$KMZ_EXISTS" = "true" ] && [ "$KMZ_SIZE" -gt 100 ]; then
    echo "Analyzing KMZ file contents..."
    
    # Create temp directory for extraction
    TEMP_DIR=$(mktemp -d)
    
    # Extract KMZ (it's a ZIP file)
    unzip -q "$KMZ_PATH" -d "$TEMP_DIR" 2>/dev/null || true
    
    # Find the KML file
    KML_FILE=$(find "$TEMP_DIR" -name "*.kml" -type f 2>/dev/null | head -1)
    
    if [ -n "$KML_FILE" ] && [ -f "$KML_FILE" ]; then
        KML_CONTENT=$(cat "$KML_FILE" 2>/dev/null || echo "")
        
        # Check for GroundOverlay element
        if echo "$KML_CONTENT" | grep -qi "GroundOverlay"; then
            HAS_GROUND_OVERLAY="true"
        fi
        
        # Extract overlay name
        OVERLAY_NAME=$(echo "$KML_CONTENT" | grep -oP '(?<=<name>)[^<]+(?=</name>)' | head -1 || echo "")
        
        # Extract rotation value
        ROTATION_VALUE=$(echo "$KML_CONTENT" | grep -oP '(?<=<rotation>)[^<]+(?=</rotation>)' | head -1 || echo "")
        
        # Extract color/opacity (format: aabbggrr where aa is alpha)
        COLOR_VALUE=$(echo "$KML_CONTENT" | grep -oP '(?<=<color>)[^<]+(?=</color>)' | head -1 || echo "")
        if [ -n "$COLOR_VALUE" ] && [ ${#COLOR_VALUE} -ge 2 ]; then
            ALPHA_HEX="${COLOR_VALUE:0:2}"
            # Convert hex alpha to decimal opacity (0-1)
            OPACITY_VALUE=$(python3 -c "print(round(int('$ALPHA_HEX', 16) / 255.0, 3))" 2>/dev/null || echo "")
        fi
        
        # Extract bounds
        NORTH_BOUND=$(echo "$KML_CONTENT" | grep -oP '(?<=<north>)[^<]+(?=</north>)' | head -1 || echo "")
        SOUTH_BOUND=$(echo "$KML_CONTENT" | grep -oP '(?<=<south>)[^<]+(?=</south>)' | head -1 || echo "")
        EAST_BOUND=$(echo "$KML_CONTENT" | grep -oP '(?<=<east>)[^<]+(?=</east>)' | head -1 || echo "")
        WEST_BOUND=$(echo "$KML_CONTENT" | grep -oP '(?<=<west>)[^<]+(?=</west>)' | head -1 || echo "")
        
        # Check for image reference
        if echo "$KML_CONTENT" | grep -qiE "(href|Icon).*\.(png|jpg|jpeg)"; then
            HAS_IMAGE_REF="true"
        fi
        
        # Also check for images in the extracted KMZ
        IMAGE_COUNT=$(find "$TEMP_DIR" -type f \( -name "*.png" -o -name "*.jpg" -o -name "*.jpeg" \) 2>/dev/null | wc -l)
        if [ "$IMAGE_COUNT" -gt 0 ]; then
            HAS_IMAGE_REF="true"
        fi
        
        echo "KML Analysis:"
        echo "  GroundOverlay: $HAS_GROUND_OVERLAY"
        echo "  Name: $OVERLAY_NAME"
        echo "  Rotation: $ROTATION_VALUE"
        echo "  Opacity: $OPACITY_VALUE"
        echo "  Bounds: N=$NORTH_BOUND S=$SOUTH_BOUND E=$EAST_BOUND W=$WEST_BOUND"
        echo "  Has Image: $HAS_IMAGE_REF"
    else
        echo "No KML file found in KMZ"
    fi
    
    # Save full KML for verifier
    if [ -n "$KML_CONTENT" ]; then
        echo "$KML_CONTENT" > /tmp/extracted_kml.xml
    fi
    
    # Cleanup
    rm -rf "$TEMP_DIR"
fi

# =============================================================
# CHECK GOOGLE EARTH STATE
# =============================================================
GE_RUNNING="false"
GE_WINDOW_TITLE=""

if pgrep -f "google-earth-pro" > /dev/null 2>&1; then
    GE_RUNNING="true"
fi

GE_WINDOWS=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "Google Earth" || echo "")
if [ -n "$GE_WINDOWS" ]; then
    GE_WINDOW_TITLE=$(echo "$GE_WINDOWS" | head -1 | cut -d' ' -f5-)
fi

# Check My Places for saved overlay
MYPLACES_FILE="/home/ga/.googleearth/myplaces.kml"
OVERLAY_IN_MYPLACES="false"
if [ -f "$MYPLACES_FILE" ]; then
    if grep -qi "SF 1906\|1906 Historical\|Historical Map" "$MYPLACES_FILE" 2>/dev/null; then
        OVERLAY_IN_MYPLACES="true"
    fi
fi

# =============================================================
# CREATE RESULT JSON
# =============================================================
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)

cat > "$TEMP_JSON" << EOF
{
    "task_start_time": $TASK_START,
    "task_end_time": $TASK_END,
    "kmz_exists": $KMZ_EXISTS,
    "kmz_size_bytes": $KMZ_SIZE,
    "kmz_mtime": $KMZ_MTIME,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "has_ground_overlay": $HAS_GROUND_OVERLAY,
    "overlay_name": "$OVERLAY_NAME",
    "rotation_value": "$ROTATION_VALUE",
    "opacity_value": "$OPACITY_VALUE",
    "north_bound": "$NORTH_BOUND",
    "south_bound": "$SOUTH_BOUND",
    "east_bound": "$EAST_BOUND",
    "west_bound": "$WEST_BOUND",
    "has_image_reference": $HAS_IMAGE_REF,
    "google_earth_running": $GE_RUNNING,
    "google_earth_window_title": "$GE_WINDOW_TITLE",
    "overlay_in_myplaces": $OVERLAY_IN_MYPLACES,
    "screenshot_captured": $SCREENSHOT_EXISTS
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "=== Export Result ==="
cat /tmp/task_result.json
echo ""
echo "=== Export complete ==="