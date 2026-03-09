#!/bin/bash
echo "=== Exporting atlas_map_generation_brazil result ==="

source /workspace/scripts/task_utils.sh

# 1. Take final screenshot
take_screenshot /tmp/task_end.png

# 2. Define paths
PROJECT_PATH="/home/ga/GIS_Data/projects/atlas_project.qgz"
PDF_PATH="/home/ga/GIS_Data/exports/brazil_atlas_map.pdf"

# 3. Check PDF Output
PDF_EXISTS="false"
PDF_SIZE=0
if [ -f "$PDF_PATH" ]; then
    PDF_EXISTS="true"
    PDF_SIZE=$(stat -c%s "$PDF_PATH" 2>/dev/null || echo "0")
fi

# 4. Check Project File
PROJECT_EXISTS="false"
PROJECT_VALID="false"

if [ -f "$PROJECT_PATH" ]; then
    PROJECT_EXISTS="true"
    if file "$PROJECT_PATH" | grep -qi "zip"; then
        PROJECT_VALID="true"
    fi
fi

# 5. Analyze Project XML for Atlas Configuration
# We extract the .qgs from the .qgz and parse it with Python
ATLAS_ANALYSIS='{"has_layout": false, "atlas_enabled": false, "coverage_layer_set": false, "filter_on": false, "filter_brazil": false, "controlled_by_atlas": false}'

if [ "$PROJECT_VALID" = "true" ]; then
    TEMP_DIR=$(mktemp -d)
    unzip -q -o "$PROJECT_PATH" -d "$TEMP_DIR"
    QGS_FILE=$(find "$TEMP_DIR" -name "*.qgs" | head -n 1)

    if [ -f "$QGS_FILE" ]; then
        ATLAS_ANALYSIS=$(python3 << PYEOF
import xml.etree.ElementTree as ET
import json
import sys

try:
    tree = ET.parse("$QGS_FILE")
    root = tree.getroot()
    
    # Find Layouts
    layouts = root.findall(".//Layout")
    has_layout = len(layouts) > 0
    
    atlas_enabled = False
    coverage_layer_set = False
    filter_on = False
    filter_brazil = False
    controlled_by_atlas = False
    
    for layout in layouts:
        # Check Atlas element
        atlas = layout.find("Atlas")
        if atlas is not None:
            if atlas.get("enabled") == "1":
                atlas_enabled = True
            
            # Check coverage layer
            if atlas.get("coverageLayer"):
                coverage_layer_set = True
            
            # Check filter
            if atlas.get("filterFeatures") == "1":
                filter_on = True
                expr = atlas.get("filterExpression", "")
                # Flexible check for "Brazil" in expression
                if "Brazil" in expr or "brazil" in expr:
                    filter_brazil = True
        
        # Check map items for "follow atlas"
        # LayoutItem-Map usually has 'followAtlas' or similar property
        # In XML it is often under <AtlasMap scalingMode="..." ... />
        atlas_maps = layout.findall(".//AtlasMap")
        for am in atlas_maps:
            # If AtlasMap element exists inside a LayoutItem, it generally means it's controlled
            # We specifically look if it's active.
            # Usually presence of <AtlasMap> implies "Controlled by Atlas" is checked
            if am.get("scalingMode") != "0": # 0 might be fixed, but presence usually indicates intent
                controlled_by_atlas = True
            # Alternative: check 'margin' or properties
            controlled_by_atlas = True # Presence is strong indicator

    print(json.dumps({
        "has_layout": has_layout,
        "atlas_enabled": atlas_enabled,
        "coverage_layer_set": coverage_layer_set,
        "filter_on": filter_on,
        "filter_brazil": filter_brazil,
        "controlled_by_atlas": controlled_by_atlas
    }))

except Exception as e:
    # print(e, file=sys.stderr)
    print(json.dumps({
        "has_layout": False, 
        "error": str(e)
    }))
PYEOF
        )
    fi
    rm -rf "$TEMP_DIR"
fi

# 6. Close QGIS
if is_qgis_running; then
    su - ga -c "DISPLAY=:1 xdotool key ctrl+q" 2>/dev/null || true
    sleep 2
    kill_qgis ga 2>/dev/null || true
fi

# 7. Write Result JSON
cat > /tmp/task_result.json << EOF
{
    "pdf_exists": $PDF_EXISTS,
    "pdf_size_bytes": $PDF_SIZE,
    "project_exists": $PROJECT_EXISTS,
    "project_path": "$PROJECT_PATH",
    "atlas_analysis": $ATLAS_ANALYSIS,
    "timestamp": "$(date -Iseconds)"
}
EOF

chmod 666 /tmp/task_result.json 2>/dev/null || true
echo "Result:"
cat /tmp/task_result.json
echo "=== Export Complete ==="