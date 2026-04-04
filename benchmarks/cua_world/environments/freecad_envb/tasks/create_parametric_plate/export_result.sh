#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Exporting parametric_plate task result ==="

OUTPUT_FILE="/home/ga/Documents/FreeCAD/parametric_plate.FCStd"
TASK_START_FILE="/tmp/task_start_time.txt"
RESULT_JSON="/tmp/task_result.json"

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Check basic file attributes
FILE_EXISTS="false"
FILE_SIZE=0
IS_NEW_FILE="false"
START_TIME=$(cat "$TASK_START_FILE" 2>/dev/null || echo "0")

if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c%s "$OUTPUT_FILE")
    FILE_MTIME=$(stat -c%Y "$OUTPUT_FILE")
    
    if [ "$FILE_MTIME" -gt "$START_TIME" ]; then
        IS_NEW_FILE="true"
    fi
fi

# 3. Run internal inspection using FreeCAD's Python API
# We create a temporary python script to run inside FreeCAD's environment
cat > /tmp/inspect_plate.py << 'PYEOF'
import FreeCAD
import json
import sys
import os

output_path = "/home/ga/Documents/FreeCAD/parametric_plate.FCStd"
result = {
    "doc_open_success": False,
    "spreadsheet_found": False,
    "aliases_found": {},
    "body_found": False,
    "pad_found": False,
    "pocket_or_hole_found": False,
    "fillet_found": False,
    "volume": 0.0,
    "bbox": [],
    "expression_count": 0,
    "spreadsheet_references": 0
}

if os.path.exists(output_path):
    try:
        # Open the document
        doc = FreeCAD.openDocument(output_path)
        result["doc_open_success"] = True
        
        # 1. Inspect Spreadsheet
        for obj in doc.Objects:
            if obj.TypeId == "Spreadsheet::Sheet":
                result["spreadsheet_found"] = True
                # Check specific aliases
                targets = ["plate_width", "plate_height", "plate_thickness", 
                           "hole_diameter", "hole_edge_offset", "corner_fillet"]
                for t in targets:
                    try:
                        # In FreeCAD spreadsheet, get alias value
                        # Usually accessed via property if alias is set correctly
                        if hasattr(obj, t):
                            val = getattr(obj, t)
                            # Handle Quantity objects
                            if hasattr(val, "Value"):
                                result["aliases_found"][t] = float(val.Value)
                            else:
                                result["aliases_found"][t] = float(val)
                    except:
                        pass
        
        # 2. Inspect Geometry and Features
        for obj in doc.Objects:
            # Check for Body
            if obj.TypeId == "PartDesign::Body":
                result["body_found"] = True
            
            # Check for Features
            if "Pad" in obj.TypeId:
                result["pad_found"] = True
            if "Pocket" in obj.TypeId or "Hole" in obj.TypeId:
                result["pocket_or_hole_found"] = True
            if "Fillet" in obj.TypeId:
                result["fillet_found"] = True
                
            # Check Expressions (Parametric Binding)
            # Expressions are stored in ExpressionEngine property
            if hasattr(obj, "ExpressionEngine"):
                exprs = obj.ExpressionEngine
                # exprs is a list of tuples (path, expression)
                for path, expr in exprs:
                    result["expression_count"] += 1
                    if "spreadsheet" in expr.lower() or "ss" in expr.lower() or "calc" in expr.lower():
                        # Simple heuristic: if expression mentions spreadsheet name (usually 'Spreadsheet')
                        # We assume the user kept default name or similar. 
                        # Better check: if it references the spreadsheet object name
                        result["spreadsheet_references"] += 1

        # 3. Calculate Final Geometry Volume and BBox
        # Find the visible solid in the body (usually the Tip)
        for obj in doc.Objects:
            if obj.TypeId == "PartDesign::Body" and obj.Tip:
                shape = obj.Tip.Shape
                if shape and not shape.isNull():
                    result["volume"] = shape.Volume
                    bb = shape.BoundBox
                    result["bbox"] = [bb.XLength, bb.YLength, bb.ZLength]
                    break

    except Exception as e:
        result["error"] = str(e)
else:
    result["error"] = "File not found"

print("JSON_START")
print(json.dumps(result))
print("JSON_END")
PYEOF

# Run the inspection script using system python (FreeCAD libs are in path)
# Note: In this env, we might need to use 'freecadcmd' or setup python path
# Using freecadcmd is safer to ensure environment is correct
INSPECTION_OUTPUT=$(freecadcmd /tmp/inspect_plate.py 2>&1 || true)

# Extract JSON from output
JSON_CONTENT=$(echo "$INSPECTION_OUTPUT" | sed -n '/JSON_START/,/JSON_END/p' | sed '1d;$d')

# If extraction failed, provide a fallback JSON
if [ -z "$JSON_CONTENT" ]; then
    JSON_CONTENT="{ \"error\": \"Failed to run inspection script\", \"raw_output\": \"$(echo $INSPECTION_OUTPUT | head -c 200)\" }"
fi

# 4. Construct final result
cat > "$RESULT_JSON" << EOF
{
    "file_exists": $FILE_EXISTS,
    "file_size": $FILE_SIZE,
    "is_new_file": $IS_NEW_FILE,
    "inspection": $JSON_CONTENT,
    "timestamp": $(date +%s)
}
EOF

# Ensure permissions
chmod 666 "$RESULT_JSON"

echo "Result exported to $RESULT_JSON"
cat "$RESULT_JSON"
echo "=== Export complete ==="