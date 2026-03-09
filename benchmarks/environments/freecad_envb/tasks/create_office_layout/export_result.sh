#!/bin/bash
echo "=== Exporting create_office_layout results ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
FCSTD_PATH="/home/ga/Documents/FreeCAD/office_layout.FCStd"
DXF_PATH="/home/ga/Documents/FreeCAD/office_layout.dxf"

# Capture final screenshot
take_screenshot /tmp/task_final.png

# 1. Check Output Files Existence & Timestamps
FCSTD_EXISTS="false"
FCSTD_CREATED_DURING="false"
if [ -f "$FCSTD_PATH" ]; then
    FCSTD_EXISTS="true"
    MTIME=$(stat -c %Y "$FCSTD_PATH")
    if [ "$MTIME" -gt "$TASK_START" ]; then
        FCSTD_CREATED_DURING="true"
    fi
fi

DXF_EXISTS="false"
DXF_CREATED_DURING="false"
if [ -f "$DXF_PATH" ]; then
    DXF_EXISTS="true"
    MTIME=$(stat -c %Y "$DXF_PATH")
    if [ "$MTIME" -gt "$TASK_START" ]; then
        DXF_CREATED_DURING="true"
    fi
fi

# 2. Run Geometric Analysis inside Container
# We create a python script and run it with freecadcmd
cat > /tmp/analyze_layout.py << 'PYEOF'
import FreeCAD
import sys
import json
import math

result = {
    "room_found": False,
    "room_dims": [0, 0],
    "table_found": False,
    "table_center": [0, 0],
    "dimension_found": False,
    "object_count": 0,
    "error": None
}

try:
    if not sys.argv[1:]:
        raise ValueError("No file path provided")
    
    file_path = sys.argv[1]
    doc = FreeCAD.openDocument(file_path)
    result["object_count"] = len(doc.Objects)
    
    for obj in doc.Objects:
        if not hasattr(obj, "Shape") or obj.Shape.isNull():
            continue
            
        bbox = obj.Shape.BoundBox
        width = bbox.XMax - bbox.XMin
        height = bbox.YMax - bbox.YMin
        
        # Check for Room (Rectangle 5000x4000)
        # Allow small tolerance
        if abs(width - 5000) < 50 and abs(height - 4000) < 50:
            result["room_found"] = True
            result["room_dims"] = [width, height]
            
        # Check for Table (Hexagon, radius 600)
        # Hexagon width (flat-to-flat) = sqrt(3) * radius ~= 1.732 * 600 = 1039.2
        # Hexagon height (point-to-point) = 2 * radius = 1200
        # OR vice versa depending on rotation.
        # Check edges count = 6
        is_hexagon = False
        try:
            if len(obj.Shape.Edges) == 6:
                is_hexagon = True
        except:
            pass
            
        if is_hexagon:
            # Check center
            center = bbox.Center
            if abs(center.x - 2500) < 100 and abs(center.y - 2000) < 100:
                result["table_found"] = True
                result["table_center"] = [center.x, center.y]
                
        # Check for Dimension
        # TypeId usually contains "Dimension" for Draft dimensions
        if "Dimension" in obj.TypeId or "Dimension" in obj.Label:
            result["dimension_found"] = True

except Exception as e:
    result["error"] = str(e)

with open("/tmp/geometry_analysis.json", "w") as f:
    json.dump(result, f)
PYEOF

# Execute the analysis script if file exists
if [ "$FCSTD_EXISTS" = "true" ]; then
    echo "Running geometry analysis..."
    # We use 'freecadcmd' which is the command line version of FreeCAD
    # We need to set setup environment variables if needed, but usually it's in path
    su - ga -c "freecadcmd /tmp/analyze_layout.py '$FCSTD_PATH' > /dev/null 2>&1" || true
else
    # Create empty result if file missing
    echo '{"error": "File not found"}' > /tmp/geometry_analysis.json
fi

# 3. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "fcstd_exists": $FCSTD_EXISTS,
    "fcstd_created_during": $FCSTD_CREATED_DURING,
    "dxf_exists": $DXF_EXISTS,
    "dxf_created_during": $DXF_CREATED_DURING,
    "screenshot_path": "/tmp/task_final.png",
    "analysis_file": "/tmp/geometry_analysis.json"
}
EOF

# Safe copy to task_result.json
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "=== Export complete ==="
cat /tmp/task_result.json