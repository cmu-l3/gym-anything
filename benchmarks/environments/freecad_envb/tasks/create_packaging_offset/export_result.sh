#!/bin/bash
set -e
echo "=== Exporting create_packaging_offset results ==="

# Source utilities
if [ -f /workspace/scripts/task_utils.sh ]; then
    source /workspace/scripts/task_utils.sh
else
    take_screenshot() { DISPLAY=:1 scrot "$1" 2>/dev/null || true; }
fi

# 1. Final Screenshot
take_screenshot /tmp/task_final.png

# 2. Gather File Info
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
OUTPUT_FILE="/home/ga/Documents/FreeCAD/packaging_clearance.FCStd"
INPUT_FILE="/home/ga/Documents/FreeCAD/T8_housing_bracket.FCStd"

FILE_EXISTS="false"
FILE_SIZE="0"
IS_NEW_FILE="false"

if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c%s "$OUTPUT_FILE")
    FILE_MTIME=$(stat -c%Y "$OUTPUT_FILE")
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        IS_NEW_FILE="true"
    fi
fi

# 3. Internal Geometry Verification (Run inside container via FreeCADCmd)
# We create a temporary python script to run inside FreeCAD
PYTHON_CHECK_SCRIPT=$(mktemp /tmp/check_geometry.XXXXXX.py)

cat > "$PYTHON_CHECK_SCRIPT" << EOF
import FreeCAD
import Part
import sys
import json
import os

result = {
    "valid_geometry": False,
    "object_found": False,
    "is_solid": False,
    "volume": 0.0,
    "ground_truth_volume": 0.0,
    "volume_match": False,
    "error": ""
}

try:
    # 1. Calculate Ground Truth from Input File
    input_path = "$INPUT_FILE"
    if not os.path.exists(input_path):
        raise Exception(f"Input file not found: {input_path}")
        
    doc_ref = FreeCAD.openDocument(input_path)
    base_shape = None
    
    # Find the main solid in the input file
    for obj in doc_ref.Objects:
        if hasattr(obj, 'Shape') and obj.Shape.Volume > 1000: # Filter out tiny helper objects
            base_shape = obj.Shape
            break
            
    if not base_shape:
        raise Exception("Could not find base shape in input file")
        
    # Generate 2mm Offset
    # join=0 (Arc), fill=True, isSolid=True
    gt_offset = base_shape.makeOffsetShape(2.0, 1e-6, fill=True)
    result["ground_truth_volume"] = gt_offset.Volume
    
    FreeCAD.closeDocument(doc_ref.Name)
    
    # 2. Check User Output
    output_path = "$OUTPUT_FILE"
    if not os.path.exists(output_path):
        result["error"] = "Output file does not exist"
    else:
        doc_usr = FreeCAD.openDocument(output_path)
        
        # Look for "ClearanceBody" or candidate objects
        candidate = None
        
        # Priority 1: Named "ClearanceBody"
        if "ClearanceBody" in doc_usr.Objects:
             candidate = doc_usr.Objects["ClearanceBody"]
        # Priority 2: Any object with "Offset" in type or name that is big enough
        else:
            for obj in doc_usr.Objects:
                if "Offset" in obj.TypeId or "Offset" in obj.Name:
                    candidate = obj
                    break
        
        if candidate:
            result["object_found"] = True
            
            # Check if it has a shape
            if hasattr(candidate, 'Shape') and not candidate.Shape.isNull():
                result["valid_geometry"] = True
                result["volume"] = candidate.Shape.Volume
                result["is_solid"] = candidate.Shape.Solid
                
                # Check volume match (1% tolerance)
                diff = abs(result["volume"] - result["ground_truth_volume"])
                avg = (result["volume"] + result["ground_truth_volume"]) / 2.0
                if avg > 0 and (diff / avg) < 0.01:
                    result["volume_match"] = True
            else:
                result["error"] = "Object has no valid shape"
        else:
            result["error"] = "ClearanceBody object not found"

except Exception as e:
    result["error"] = str(e)

# Write result to stdout as JSON
print("JSON_RESULT_START")
print(json.dumps(result))
print("JSON_RESULT_END")
EOF

# Run the python script with FreeCADCmd
# We filter stdout to extract just the JSON part because FreeCAD prints startup logs
FREECAD_OUTPUT=$(freecadcmd "$PYTHON_CHECK_SCRIPT" 2>&1 || true)
JSON_RESULT=$(echo "$FREECAD_OUTPUT" | sed -n '/JSON_RESULT_START/,/JSON_RESULT_END/p' | sed '1d;$d')

# If extraction failed, provide fallback
if [ -z "$JSON_RESULT" ]; then
    JSON_RESULT='{"error": "Failed to run FreeCAD verification script", "raw_output": "See logs"}'
fi

# 4. Create Final JSON Report
REPORT_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$REPORT_JSON" << EOF
{
    "task_start": $TASK_START,
    "file_exists": $FILE_EXISTS,
    "file_size": $FILE_SIZE,
    "is_new_file": $IS_NEW_FILE,
    "geometry_check": $JSON_RESULT
}
EOF

# Move to standard export location
mv "$REPORT_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

# Cleanup
rm -f "$PYTHON_CHECK_SCRIPT"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="