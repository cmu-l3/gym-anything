#!/bin/bash
echo "=== Exporting graduated_symbology_map_export result ==="

source /workspace/scripts/task_utils.sh

# Capture final visual state
take_screenshot /tmp/task_end.png

# Paths
PROJECT_DIR="/home/ga/GIS_Data/projects"
EXPORT_DIR="/home/ga/GIS_Data/exports"
EXPECTED_QGZ="$PROJECT_DIR/world_population_map.qgz"
EXPECTED_QGS="$PROJECT_DIR/world_population_map.qgs"
EXPECTED_PNG="$EXPORT_DIR/world_population_map.png"

# Timing
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# --- 1. Analyze Project File ---
PROJECT_FOUND="false"
PROJECT_PATH=""
RENDERER_TYPE="unknown"
ATTR_FIELD="unknown"
CLASS_COUNT=0
LAYER_NAME="unknown"

# Helper to inspect QGS XML content
inspect_qgs() {
    local qgs_file="$1"
    # Use python to robustly parse XML
    python3 << PYEOF
import xml.etree.ElementTree as ET
import sys

try:
    tree = ET.parse("$qgs_file")
    root = tree.getroot()
    
    # Find the vector layer (likely the countries one)
    renderer_type = "none"
    attr_field = "none"
    class_count = 0
    layer_name = "none"
    
    # Look for maplayers
    for layer in root.findall(".//maplayer"):
        # Check if it looks like our target layer (by name or source)
        name = layer.find("layername")
        lname = name.text if name is not None else ""
        
        # Check if it has a renderer
        renderer = layer.find("renderer-v2")
        if renderer is not None:
            # If we find a graduated renderer, this is likely our target
            rtype = renderer.get("type")
            if rtype == "graduatedSymbol" or "ne_110m" in lname or "countries" in lname:
                renderer_type = rtype
                attr_field = renderer.get("attr", "none")
                layer_name = lname
                
                # Count classes (ranges)
                ranges = renderer.findall("ranges/range")
                class_count = len(ranges)
                break

    print(f"RENDERER_TYPE={renderer_type}")
    print(f"ATTR_FIELD={attr_field}")
    print(f"CLASS_COUNT={class_count}")
    print(f"LAYER_NAME={layer_name}")

except Exception as e:
    print("RENDERER_TYPE=error")
PYEOF
}

if [ -f "$EXPECTED_QGZ" ]; then
    PROJECT_FOUND="true"
    PROJECT_PATH="$EXPECTED_QGZ"
    # Unzip QGS from QGZ to temp
    TEMP_DIR=$(mktemp -d)
    unzip -q "$EXPECTED_QGZ" -d "$TEMP_DIR" 2>/dev/null
    QGS_FILE=$(find "$TEMP_DIR" -name "*.qgs" | head -n 1)
    if [ -n "$QGS_FILE" ]; then
        eval $(inspect_qgs "$QGS_FILE")
    fi
    rm -rf "$TEMP_DIR"
elif [ -f "$EXPECTED_QGS" ]; then
    PROJECT_FOUND="true"
    PROJECT_PATH="$EXPECTED_QGS"
    eval $(inspect_qgs "$EXPECTED_QGS")
fi

# --- 2. Analyze Exported Image ---
IMAGE_FOUND="false"
IMAGE_WIDTH=0
IMAGE_HEIGHT=0
IMAGE_SIZE_KB=0
COLOR_COUNT=0

if [ -f "$EXPECTED_PNG" ]; then
    IMAGE_MTIME=$(stat -c %Y "$EXPECTED_PNG")
    if [ "$IMAGE_MTIME" -gt "$TASK_START" ]; then
        IMAGE_FOUND="true"
        IMAGE_SIZE_KB=$(du -k "$EXPECTED_PNG" | cut -f1)
        
        # Analyze image properties
        eval $(python3 << PYEOF
from PIL import Image
import sys

try:
    img = Image.open("$EXPECTED_PNG")
    print(f"IMAGE_WIDTH={img.width}")
    print(f"IMAGE_HEIGHT={img.height}")
    
    # Count unique colors to verify it's not blank/solid
    # Resize for speed
    small = img.resize((100, 100))
    colors = len(small.getcolors(10000) or [])
    print(f"COLOR_COUNT={colors}")
except Exception:
    print("IMAGE_WIDTH=0")
    print("IMAGE_HEIGHT=0")
    print("COLOR_COUNT=0")
PYEOF
        )
    fi
fi

# --- 3. Clean Up ---
if is_qgis_running; then
    kill_qgis ga 2>/dev/null || true
fi

# --- 4. Generate Result JSON ---
cat > /tmp/task_result.json << EOF
{
    "project_found": $PROJECT_FOUND,
    "project_path": "$PROJECT_PATH",
    "layer_name": "$LAYER_NAME",
    "renderer_type": "$RENDERER_TYPE",
    "attribute_field": "$ATTR_FIELD",
    "class_count": $CLASS_COUNT,
    "image_found": $IMAGE_FOUND,
    "image_path": "$EXPECTED_PNG",
    "image_width": $IMAGE_WIDTH,
    "image_height": $IMAGE_HEIGHT,
    "image_size_kb": $IMAGE_SIZE_KB,
    "image_color_count": $COLOR_COUNT,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Ensure permissions
chmod 666 /tmp/task_result.json

echo "Result generated:"
cat /tmp/task_result.json
echo "=== Export Complete ==="