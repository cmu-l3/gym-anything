#!/bin/bash
set -euo pipefail

echo "=== Exporting Giza Plateau Survey task result ==="

export DISPLAY=${DISPLAY:-:1}

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

echo "Task start time: $TASK_START"
echo "Task end time: $TASK_END"
echo "Duration: $((TASK_END - TASK_START)) seconds"

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final_screenshot.png 2>/dev/null || true
echo "Final screenshot captured"

# ================================================================
# Check KML output file
# ================================================================
KML_PATH="/home/ga/Documents/giza_plateau_survey.kml"
KML_EXISTS="false"
KML_SIZE="0"
KML_MTIME="0"
KML_CREATED_DURING_TASK="false"
KML_CONTENT=""
KML_HAS_FOLDER="false"
KML_FOLDER_NAME=""
KML_PLACEMARK_COUNT="0"
KML_PATH_COUNT="0"
KML_PLACEMARK_NAMES=""

if [ -f "$KML_PATH" ]; then
    KML_EXISTS="true"
    KML_SIZE=$(stat -c %s "$KML_PATH" 2>/dev/null || echo "0")
    KML_MTIME=$(stat -c %Y "$KML_PATH" 2>/dev/null || echo "0")

    # Check if created during task
    if [ "$KML_MTIME" -gt "$TASK_START" ]; then
        KML_CREATED_DURING_TASK="true"
    fi

    # Read KML content (first 10000 chars for JSON safety)
    KML_CONTENT=$(head -c 10000 "$KML_PATH" 2>/dev/null | tr '\n' ' ' | tr '"' "'" || echo "")

    # Check for folder
    if grep -qi "Giza Plateau Survey" "$KML_PATH" 2>/dev/null; then
        KML_HAS_FOLDER="true"
        KML_FOLDER_NAME=$(grep -oP '(?<=<name>)[^<]*[Gg]iza[^<]*' "$KML_PATH" 2>/dev/null | head -1 || echo "")
    fi

    # Count placemarks
    KML_PLACEMARK_COUNT=$(grep -c "<Placemark" "$KML_PATH" 2>/dev/null || echo "0")

    # Count paths (LineString elements)
    KML_PATH_COUNT=$(grep -c "<LineString" "$KML_PATH" 2>/dev/null || echo "0")

    # Extract placemark names
    NAMES_RAW=$(grep -oP '(?<=<name>)[^<]+' "$KML_PATH" 2>/dev/null | head -20 | tr '\n' '|' || echo "")
    KML_PLACEMARK_NAMES="$NAMES_RAW"

    echo "KML file found: $KML_PATH"
    echo "  Size: $KML_SIZE bytes"
    echo "  Modified: $KML_MTIME"
    echo "  Created during task: $KML_CREATED_DURING_TASK"
    echo "  Has Giza folder: $KML_HAS_FOLDER"
    echo "  Placemark count: $KML_PLACEMARK_COUNT"
    echo "  Path count: $KML_PATH_COUNT"
    echo "  Names: $KML_PLACEMARK_NAMES"
else
    echo "KML file NOT found at $KML_PATH"
fi

# ================================================================
# Check screenshot output file
# ================================================================
PNG_PATH="/home/ga/Documents/giza_overview.png"
PNG_EXISTS="false"
PNG_SIZE="0"
PNG_MTIME="0"
PNG_CREATED_DURING_TASK="false"
IMAGE_WIDTH="0"
IMAGE_HEIGHT="0"

if [ -f "$PNG_PATH" ]; then
    PNG_EXISTS="true"
    PNG_SIZE=$(stat -c %s "$PNG_PATH" 2>/dev/null || echo "0")
    PNG_MTIME=$(stat -c %Y "$PNG_PATH" 2>/dev/null || echo "0")

    if [ "$PNG_MTIME" -gt "$TASK_START" ]; then
        PNG_CREATED_DURING_TASK="true"
    fi

    # Get image dimensions using Python/PIL
    DIMENSIONS=$(python3 << 'PYEOF'
import json
try:
    from PIL import Image
    img = Image.open("/home/ga/Documents/giza_overview.png")
    print(json.dumps({"width": img.width, "height": img.height}))
except Exception as e:
    print(json.dumps({"width": 0, "height": 0}))
PYEOF
)
    IMAGE_WIDTH=$(echo "$DIMENSIONS" | python3 -c "import json, sys; print(json.load(sys.stdin).get('width', 0))" 2>/dev/null || echo "0")
    IMAGE_HEIGHT=$(echo "$DIMENSIONS" | python3 -c "import json, sys; print(json.load(sys.stdin).get('height', 0))" 2>/dev/null || echo "0")

    echo "Screenshot found: $PNG_PATH"
    echo "  Size: $PNG_SIZE bytes, Dimensions: ${IMAGE_WIDTH}x${IMAGE_HEIGHT}"
    echo "  Created during task: $PNG_CREATED_DURING_TASK"
else
    echo "Screenshot NOT found at $PNG_PATH"
fi

# ================================================================
# Check myplaces.kml for survey content
# ================================================================
MYPLACES_FILE="/home/ga/.googleearth/myplaces.kml"
MYPLACES_EXISTS="false"
MYPLACES_MODIFIED="false"
MYPLACES_MTIME="0"
CURRENT_PLACEMARK_COUNT="0"
MYPLACES_HAS_GIZA="false"
MYPLACES_HAS_KHUFU="false"
MYPLACES_HAS_KHAFRE="false"
MYPLACES_HAS_MENKAURE="false"
MYPLACES_HAS_SPHINX="false"
MYPLACES_HAS_CAUSEWAY="false"

if [ -f "$MYPLACES_FILE" ]; then
    MYPLACES_EXISTS="true"
    CURRENT_PLACEMARK_COUNT=$(grep -c "<Placemark" "$MYPLACES_FILE" 2>/dev/null || echo "0")
    MYPLACES_MTIME=$(stat -c %Y "$MYPLACES_FILE" 2>/dev/null || echo "0")

    INITIAL_MTIME=$(cat /tmp/myplaces_initial_mtime.txt 2>/dev/null || echo "0")
    if [ "$MYPLACES_MTIME" -gt "$INITIAL_MTIME" ] && [ "$MYPLACES_MTIME" -gt "$TASK_START" ]; then
        MYPLACES_MODIFIED="true"
    fi

    # Check for key content
    grep -qi "giza" "$MYPLACES_FILE" 2>/dev/null && MYPLACES_HAS_GIZA="true"
    grep -qi "khufu" "$MYPLACES_FILE" 2>/dev/null && MYPLACES_HAS_KHUFU="true"
    grep -qi "khafre" "$MYPLACES_FILE" 2>/dev/null && MYPLACES_HAS_KHAFRE="true"
    grep -qi "menkaure" "$MYPLACES_FILE" 2>/dev/null && MYPLACES_HAS_MENKAURE="true"
    grep -qi "sphinx" "$MYPLACES_FILE" 2>/dev/null && MYPLACES_HAS_SPHINX="true"
    grep -qi "causeway" "$MYPLACES_FILE" 2>/dev/null && MYPLACES_HAS_CAUSEWAY="true"

    # Copy for verification
    cp "$MYPLACES_FILE" /tmp/myplaces_final.kml 2>/dev/null || true
fi

INITIAL_PLACEMARK_COUNT=$(cat /tmp/initial_placemark_count.txt 2>/dev/null || echo "0")
NEW_PLACEMARKS=$((CURRENT_PLACEMARK_COUNT - INITIAL_PLACEMARK_COUNT))

echo "My Places - Initial: $INITIAL_PLACEMARK_COUNT, Current: $CURRENT_PLACEMARK_COUNT, New: $NEW_PLACEMARKS"

# ================================================================
# Check CSV file access (evidence of import attempt)
# ================================================================
CSV_FILE="/home/ga/Documents/giza_reference_points.csv"
CSV_ACCESSED="false"

if [ -f "$CSV_FILE" ]; then
    CURRENT_ATIME=$(stat -c %X "$CSV_FILE" 2>/dev/null || echo "0")
    INITIAL_ATIME=$(cat /tmp/csv_initial_atime.txt 2>/dev/null || echo "0")

    if [ "$CURRENT_ATIME" -gt "$INITIAL_ATIME" ]; then
        CSV_ACCESSED="true"
    fi
fi

# ================================================================
# Check terrain exaggeration config
# ================================================================
EXAGGERATION_VALUE="unknown"
EXAGGERATION_FOUND="false"

CONFIG_PATHS="/home/ga/.config/Google/GoogleEarthPro.conf /home/ga/.googleearth/GoogleEarthPro.conf /home/ga/.googleearth/Registry/google.earth"

for config_path in $CONFIG_PATHS; do
    if [ -f "$config_path" ]; then
        EXTRACTED=$(grep -oiE 'elevationExaggeration[=:][[:space:]]*[0-9.]+' "$config_path" 2>/dev/null | grep -oE '[0-9.]+' | tail -1 || echo "")
        if [ -n "$EXTRACTED" ]; then
            EXAGGERATION_VALUE="$EXTRACTED"
            EXAGGERATION_FOUND="true"
            break
        fi
        EXTRACTED=$(grep -oiE 'terrainExaggeration[=:][[:space:]]*[0-9.]+' "$config_path" 2>/dev/null | grep -oE '[0-9.]+' | tail -1 || echo "")
        if [ -n "$EXTRACTED" ]; then
            EXAGGERATION_VALUE="$EXTRACTED"
            EXAGGERATION_FOUND="true"
            break
        fi
    fi
done

# ================================================================
# Check Google Earth state
# ================================================================
GE_RUNNING="false"
GE_WINDOW_TITLE=""

if pgrep -f google-earth-pro > /dev/null 2>&1; then
    GE_RUNNING="true"
fi

GE_WINDOWS=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "Google Earth" || echo "")
if [ -n "$GE_WINDOWS" ]; then
    GE_WINDOW_TITLE=$(echo "$GE_WINDOWS" | head -1 | cut -d' ' -f5-)
fi

# ================================================================
# Create JSON result
# ================================================================
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "duration_seconds": $((TASK_END - TASK_START)),
    "kml": {
        "exists": $KML_EXISTS,
        "size_bytes": $KML_SIZE,
        "mtime": $KML_MTIME,
        "created_during_task": $KML_CREATED_DURING_TASK,
        "has_giza_folder": $KML_HAS_FOLDER,
        "folder_name": "$KML_FOLDER_NAME",
        "placemark_count": $KML_PLACEMARK_COUNT,
        "path_count": $KML_PATH_COUNT,
        "placemark_names": "$KML_PLACEMARK_NAMES"
    },
    "screenshot": {
        "exists": $PNG_EXISTS,
        "size_bytes": $PNG_SIZE,
        "mtime": $PNG_MTIME,
        "created_during_task": $PNG_CREATED_DURING_TASK,
        "image_width": $IMAGE_WIDTH,
        "image_height": $IMAGE_HEIGHT
    },
    "myplaces": {
        "exists": $MYPLACES_EXISTS,
        "modified": $MYPLACES_MODIFIED,
        "initial_placemark_count": $INITIAL_PLACEMARK_COUNT,
        "current_placemark_count": $CURRENT_PLACEMARK_COUNT,
        "new_placemarks_added": $NEW_PLACEMARKS,
        "has_giza": $MYPLACES_HAS_GIZA,
        "has_khufu": $MYPLACES_HAS_KHUFU,
        "has_khafre": $MYPLACES_HAS_KHAFRE,
        "has_menkaure": $MYPLACES_HAS_MENKAURE,
        "has_sphinx": $MYPLACES_HAS_SPHINX,
        "has_causeway": $MYPLACES_HAS_CAUSEWAY
    },
    "csv_file_accessed": $CSV_ACCESSED,
    "terrain": {
        "exaggeration_found": $EXAGGERATION_FOUND,
        "exaggeration_value": "$EXAGGERATION_VALUE"
    },
    "google_earth": {
        "running": $GE_RUNNING,
        "window_title": "$GE_WINDOW_TITLE"
    },
    "final_screenshot_path": "/tmp/task_final_screenshot.png",
    "myplaces_final_path": "/tmp/myplaces_final.kml"
}
EOF

# Move to final location with proper permissions
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "=== Export complete ==="
echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
