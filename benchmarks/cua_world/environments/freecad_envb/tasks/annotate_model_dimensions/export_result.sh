#!/bin/bash
echo "=== Exporting annotate_model_dimensions results ==="

source /workspace/scripts/task_utils.sh

# Record timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)
OUTPUT_FILE="/home/ga/Documents/FreeCAD/T8_annotated.FCStd"

# Take final screenshot
take_screenshot /tmp/task_final.png

# Check file existence
FILE_EXISTS="false"
FILE_SIZE="0"
if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$OUTPUT_FILE")
fi

# Run geometric analysis inside the container using FreeCAD's python
# We create a temporary python script to extract data about the dimensions
ANALYSIS_SCRIPT="/tmp/analyze_dimensions.py"

cat > "$ANALYSIS_SCRIPT" << 'PYEOF'
import FreeCAD
import json
import sys
import os

result = {
    "valid_doc": False,
    "dimensions": [],
    "solid_bbox": {},
    "solid_volume": 0,
    "error": None
}

try:
    file_path = "/home/ga/Documents/FreeCAD/T8_annotated.FCStd"
    if not os.path.exists(file_path):
        result["error"] = "File not found"
    else:
        doc = FreeCAD.open(file_path)
        result["valid_doc"] = True
        
        # 1. Analyze Geometry (Ground Truth)
        # Find the main solid (usually named T8_housing_bracket or similar, or just the biggest object)
        solid_obj = None
        max_vol = 0
        
        for obj in doc.Objects:
            if hasattr(obj, "Shape") and obj.Shape is not None:
                try:
                    vol = obj.Shape.Volume
                    if vol > max_vol:
                        max_vol = vol
                        solid_obj = obj
                except:
                    pass
        
        if solid_obj:
            bbox = solid_obj.Shape.BoundBox
            result["solid_bbox"] = {
                "XLength": bbox.XLength,
                "YLength": bbox.YLength,
                "ZLength": bbox.ZLength
            }
            result["solid_volume"] = max_vol

        # 2. Analyze Annotations
        # Look for objects of type 'Draft::Dimension' (or ViewDimension)
        for obj in doc.Objects:
            # Check for Draft Dimension proxy or type
            is_dim = False
            if hasattr(obj, "Proxy") and hasattr(obj.Proxy, "Type"):
                if "Dimension" in obj.Proxy.Type:
                    is_dim = True
            if "Dimension" in obj.TypeId:
                is_dim = True
            
            if is_dim:
                # Extract value
                value = 0.0
                if hasattr(obj, "Distance"):
                    value = obj.Distance.Value if hasattr(obj.Distance, "Value") else obj.Distance
                
                # Extract color
                color = (0.0, 0.0, 0.0)
                if hasattr(obj, "ViewObject") and hasattr(obj.ViewObject, "LineColor"):
                    # FreeCAD colors are often tuples (r,g,b) float 0-1 or similar
                    c = obj.ViewObject.LineColor
                    color = (c[0], c[1], c[2])
                
                dim_data = {
                    "Label": obj.Label,
                    "Value": float(value),
                    "Color": color
                }
                result["dimensions"].append(dim_data)

except Exception as e:
    result["error"] = str(e)

# Output result to JSON
with open("/tmp/analysis_result.json", "w") as f:
    json.dump(result, f)
PYEOF

# Run the analysis script headlessly
echo "Running geometry analysis..."
export PYTHONPATH="/usr/lib/freecad/lib" # Ensure path is set if needed
timeout 30s freecadcmd "$ANALYSIS_SCRIPT" > /tmp/analysis_log.txt 2>&1

# Read the analysis result
ANALYSIS_JSON="{}"
if [ -f "/tmp/analysis_result.json" ]; then
    ANALYSIS_JSON=$(cat "/tmp/analysis_result.json")
else
    echo "WARNING: Analysis script failed to produce JSON"
    cat /tmp/analysis_log.txt
fi

# Check if app is running
APP_RUNNING=$(pgrep -f "FreeCAD" > /dev/null && echo "true" || echo "false")

# Create final result JSON
cat > /tmp/task_result.json << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "file_exists": $FILE_EXISTS,
    "file_size": $FILE_SIZE,
    "app_was_running": $APP_RUNNING,
    "analysis": $ANALYSIS_JSON
}
EOF

# Clean up analysis script
rm -f "$ANALYSIS_SCRIPT" "/tmp/analysis_result.json"

echo "Result generated at /tmp/task_result.json"