#!/bin/bash
echo "=== Exporting create_parametric_standoff results ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
OUTPUT_FILE="/home/ga/Documents/FreeCAD/parametric_standoff.FCStd"

# 1. Check file existence and timestamp
FILE_EXISTS="false"
FILE_CREATED_DURING="false"
FILE_SIZE="0"

if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$OUTPUT_FILE")
    FILE_MTIME=$(stat -c %Y "$OUTPUT_FILE")
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING="true"
    fi
fi

# 2. Run INTERNAL verification script using FreeCAD's python interpreter (freecadcmd)
# We create a python script that imports the document and inspects objects/expressions
# This runs INSIDE the container to access the FreeCAD API.

cat > /tmp/verify_internal.py << 'PYEOF'
import FreeCAD
import sys
import json
import os

result = {
    "valid_doc": False,
    "spreadsheet_found": False,
    "aliases_found": [],
    "aliases_correct": [],
    "expression_count": 0,
    "body_found": False,
    "bbox_height": 0.0,
    "bbox_max_dim": 0.0,
    "has_through_hole": False
}

file_path = "/home/ga/Documents/FreeCAD/parametric_standoff.FCStd"

try:
    if not os.path.exists(file_path):
        print(json.dumps(result))
        sys.exit(0)

    # Open document
    doc = FreeCAD.openDocument(file_path)
    result["valid_doc"] = True

    # 1. Check Spreadsheet
    sheets = doc.findObjects("Spreadsheet::Sheet")
    if sheets:
        sheet = sheets[0]
        result["spreadsheet_found"] = True
        
        # Check aliases
        required = {
            "outer_diameter": 8.0,
            "inner_diameter": 3.2,
            "height": 10.0,
            "flange_diameter": 12.0,
            "flange_height": 1.5
        }
        
        for alias, expected in required.items():
            # In FreeCAD Spreadsheet, get(alias) returns the value
            # check if alias exists
            try:
                val = sheet.get(alias)
                # If alias doesn't exist, get might return None or raise error depending on version
                # Checking if the cell has the alias
                if val is not None:
                    result["aliases_found"].append(alias)
                    # Allow small float tolerance
                    if abs(float(val) - expected) < 0.01:
                        result["aliases_correct"].append(alias)
            except:
                pass

    # 2. Check Expressions (Parametric Links)
    # Iterate all objects and their properties to find expression bindings
    expr_count = 0
    for obj in doc.Objects:
        for prop_name in obj.PropertiesList:
            try:
                # getExpression returns the expression string (e.g. "Spreadsheet.width")
                expr = obj.getExpression(prop_name)
                if expr and "Spreadsheet" in str(expr):
                    expr_count += 1
            except:
                pass
    result["expression_count"] = expr_count

    # 3. Check Geometry (Body)
    bodies = doc.findObjects("PartDesign::Body")
    if bodies:
        body = bodies[0]
        if body.Shape and body.Shape.isValid():
            result["body_found"] = True
            bbox = body.Shape.BoundBox
            result["bbox_height"] = bbox.ZLength
            # Max XY dimension
            result["bbox_max_dim"] = max(bbox.XLength, bbox.YLength)
            
            # Simple topological check for through hole:
            # Check for cylindrical faces with radius ~1.6mm (3.2mm diam)
            for face in body.Shape.Faces:
                surf = face.Surface
                if "Cylinder" in str(type(surf)):
                    if abs(surf.Radius - 1.6) < 0.1:
                        result["has_through_hole"] = True
                        break

except Exception as e:
    result["error"] = str(e)

print(json.dumps(result))
PYEOF

# Run the python script using freecadcmd
# We use 'su - ga' to ensure permissions match, though freecadcmd usually runs fine as root if env is set.
# Using standard python with FreeCAD lib path appended is safer if freecadcmd is finicky with headless X.
# But freecadcmd is the standard CLI.
INTERNAL_JSON="{}"
if [ "$FILE_EXISTS" = "true" ]; then
    # We need to make sure the script can run. 
    # Often freecadcmd prints startup text, so we need to filter for the JSON output (last line).
    RAW_OUTPUT=$(su - ga -c "DISPLAY=:1 freecadcmd /tmp/verify_internal.py" 2>&1)
    INTERNAL_JSON=$(echo "$RAW_OUTPUT" | tail -n 1)
    
    # Validate if it's JSON
    if ! echo "$INTERNAL_JSON" | jq . >/dev/null 2>&1; then
        INTERNAL_JSON="{}"
    fi
fi

# 3. Take Final Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 4. Construct Final Result JSON
# We merge the shell-checked generic stats with the python-checked specific stats
cat > /tmp/task_result.json << EOF
{
    "task_start": $TASK_START,
    "file_exists": $FILE_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING,
    "file_size": $FILE_SIZE,
    "internal_analysis": $INTERNAL_JSON,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="