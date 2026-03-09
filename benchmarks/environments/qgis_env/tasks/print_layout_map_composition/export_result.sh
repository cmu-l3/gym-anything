#!/bin/bash
echo "=== Exporting Print Layout Map Composition result ==="

source /workspace/scripts/task_utils.sh

# 1. Take final screenshot
take_screenshot /tmp/task_end.png

# 2. Locate files
PROJECT_DIR="/home/ga/GIS_Data/projects"
EXPORT_DIR="/home/ga/GIS_Data/exports"
PROJECT_FILE=""
EXPORT_FILE=""

# Find project file (QGZ or QGS)
if [ -f "$PROJECT_DIR/bay_area_map.qgz" ]; then
    PROJECT_FILE="$PROJECT_DIR/bay_area_map.qgz"
elif [ -f "$PROJECT_DIR/bay_area_map.qgs" ]; then
    PROJECT_FILE="$PROJECT_DIR/bay_area_map.qgs"
else
    # Search for any recent project file if exact name not found
    PROJECT_FILE=$(find "$PROJECT_DIR" -maxdepth 1 \( -name "*.qgz" -o -name "*.qgs" \) -mmin -15 2>/dev/null | head -1)
fi

# Find export file (PNG)
if [ -f "$EXPORT_DIR/bay_area_map.png" ]; then
    EXPORT_FILE="$EXPORT_DIR/bay_area_map.png"
else
    # Search for any recent PNG
    EXPORT_FILE=$(find "$EXPORT_DIR" -maxdepth 1 -name "*.png" -mmin -15 2>/dev/null | head -1)
fi

# 3. Parse Project XML with Python
# We embedding Python here to handle the QGZ (zip) extraction and XML parsing
# This runs INSIDE the container, so it has access to the files.
ANALYSIS_JSON=$(python3 << PYEOF
import json
import os
import zipfile
import xml.etree.ElementTree as ET
import sys

project_path = "$PROJECT_FILE"
export_path = "$EXPORT_FILE"
result = {
    "project_found": False,
    "project_path": project_path,
    "valid_xml": False,
    "layer_count": 0,
    "layout_found": False,
    "layout_items": [],
    "export_found": False,
    "export_size_kb": 0
}

# Check Export
if export_path and os.path.exists(export_path):
    result["export_found"] = True
    result["export_size_kb"] = os.path.getsize(export_path) / 1024

# Check Project
if project_path and os.path.exists(project_path):
    result["project_found"] = True
    
    xml_content = None
    try:
        if project_path.endswith('.qgz'):
            with zipfile.ZipFile(project_path, 'r') as z:
                # Find .qgs file inside zip
                qgs_files = [f for f in z.namelist() if f.endswith('.qgs')]
                if qgs_files:
                    with z.open(qgs_files[0]) as f:
                        xml_content = f.read()
        else:
            with open(project_path, 'rb') as f:
                xml_content = f.read()
                
        if xml_content:
            root = ET.fromstring(xml_content)
            result["valid_xml"] = True
            
            # Count Layers
            layers = root.findall(".//maplayer")
            result["layer_count"] = len(layers)
            
            # Check Layouts
            # Layouts can be under <Layouts> or directly in root depending on version
            layouts = root.findall(".//Layout")
            if not layouts:
                # Try finding via LayoutManager (older versions)
                layouts = root.findall(".//Composer")
            
            if layouts:
                result["layout_found"] = True
                # Analyze items in the first layout found
                layout = layouts[0]
                
                # Check for item types
                # QGIS XML usually has items with 'type' attribute or class
                # We'll look for specific keywords in the XML tags or attributes
                # Common classes: QgsLayoutItemMap, QgsLayoutItemLabel, QgsLayoutItemLegend, QgsLayoutItemScaleBar
                
                # Convert layout tree to string to search easily or iterate items
                items_found = set()
                
                # Recursive search for items
                for elem in layout.iter():
                    type_attr = elem.get('type')
                    cls_attr = elem.get('class')
                    
                    # Check Map
                    if 'Map' in str(type_attr) or 'Map' in str(cls_attr) or elem.tag.endswith('ItemMap'):
                        items_found.add('Map')
                    
                    # Check Label
                    if 'Label' in str(type_attr) or 'Label' in str(cls_attr) or elem.tag.endswith('ItemLabel'):
                        # Distinguish title from other labels if possible, but presence is good enough
                        items_found.add('Label')
                        
                    # Check Legend
                    if 'Legend' in str(type_attr) or 'Legend' in str(cls_attr) or elem.tag.endswith('ItemLegend'):
                        items_found.add('Legend')
                        
                    # Check ScaleBar
                    if 'ScaleBar' in str(type_attr) or 'ScaleBar' in str(cls_attr) or elem.tag.endswith('ItemScaleBar'):
                        items_found.add('ScaleBar')
                        
                result["layout_items"] = list(items_found)

    except Exception as e:
        result["error"] = str(e)

print(json.dumps(result))
PYEOF
)

# 4. Save result
cat > /tmp/task_result.json << EOF
{
    "timestamp": "$(date -Iseconds)",
    "analysis": $ANALYSIS_JSON
}
EOF

chmod 666 /tmp/task_result.json 2>/dev/null || true
echo "Result:"
cat /tmp/task_result.json

# 5. Cleanup QGIS
if is_qgis_running; then
    su - ga -c "DISPLAY=:1 xdotool key ctrl+q" 2>/dev/null || true
    sleep 2
    kill_qgis ga 2>/dev/null || true
fi

echo "=== Export Complete ==="