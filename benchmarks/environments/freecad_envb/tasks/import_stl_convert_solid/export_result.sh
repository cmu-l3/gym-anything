#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Exporting import_stl_convert_solid results ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
OUTPUT_FILE="/home/ga/Documents/FreeCAD/bracket_solid.FCStd"
EXPECTED_VOLUME=$(cat /tmp/expected_volume.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Initialize result variables
OUTPUT_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
STL_IMPORTED="false"
HAS_SOLID="false"
SOLID_VALID="false"
SOLID_CLOSED="false"
ACTUAL_VOLUME="0.0"
HAS_PART_FEATURE="false"
OBJECT_TYPES="[]"

if [ -f "$OUTPUT_FILE" ]; then
    OUTPUT_EXISTS="true"
    
    # Check timestamp
    FILE_MTIME=$(stat -c %Y "$OUTPUT_FILE")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi

    # Inspect the document using FreeCAD headless
    echo "Inspecting FreeCAD file..."
    INSPECTION_JSON=$(su - ga -c 'freecadcmd /dev/stdin' <<PYEOF 2>/dev/null
import sys, json
import FreeCAD
import Part

result = {
    "stl_imported": False,
    "has_solid": False,
    "solid_valid": False,
    "solid_closed": False,
    "volume": 0.0,
    "has_part_feature": False,
    "object_types": []
}

try:
    doc = FreeCAD.openDocument("$OUTPUT_FILE")
    
    for obj in doc.Objects:
        type_id = obj.TypeId
        result["object_types"].append(type_id)
        
        # Check for mesh import evidence (Mesh::Feature)
        if "Mesh" in type_id:
            result["stl_imported"] = True
        
        # Check for Part::Feature (conversion evidence)
        # Part::Feature is the base for most geometric shapes
        if "Part" in type_id and "Mesh" not in type_id:
            result["has_part_feature"] = True
        
        # Check for solid shapes
        if hasattr(obj, 'Shape'):
            shape = obj.Shape
            if not shape.isNull():
                # We look for the largest solid in the file
                if shape.ShapeType == 'Solid' or len(shape.Solids) > 0:
                    # Update if this one is larger (assuming main part is largest)
                    if shape.Volume > result["volume"]:
                        result["has_solid"] = True
                        result["volume"] = shape.Volume
                        result["solid_valid"] = shape.isValid()
                        # isClosed check
                        try:
                            result["solid_closed"] = shape.isClosed()
                        except:
                            result["solid_closed"] = True # Assumption for valid solids
    
    # If we have a solid but no mesh object, the user might have deleted the mesh
    # This is acceptable, so we assume import happened if a solid exists
    if result["has_solid"]:
        result["stl_imported"] = True

except Exception as e:
    result["error"] = str(e)

print(json.dumps(result))
PYEOF
)
    
    # Extract values from JSON if valid
    if [ -n "$INSPECTION_JSON" ]; then
        STL_IMPORTED=$(echo "$INSPECTION_JSON" | python3 -c "import sys, json; print(json.load(sys.stdin).get('stl_imported', False))")
        HAS_SOLID=$(echo "$INSPECTION_JSON" | python3 -c "import sys, json; print(json.load(sys.stdin).get('has_solid', False))")
        SOLID_VALID=$(echo "$INSPECTION_JSON" | python3 -c "import sys, json; print(json.load(sys.stdin).get('solid_valid', False))")
        SOLID_CLOSED=$(echo "$INSPECTION_JSON" | python3 -c "import sys, json; print(json.load(sys.stdin).get('solid_closed', False))")
        ACTUAL_VOLUME=$(echo "$INSPECTION_JSON" | python3 -c "import sys, json; print(json.load(sys.stdin).get('volume', 0.0))")
        HAS_PART_FEATURE=$(echo "$INSPECTION_JSON" | python3 -c "import sys, json; print(json.load(sys.stdin).get('has_part_feature', False))")
        OBJECT_TYPES=$(echo "$INSPECTION_JSON" | python3 -c "import sys, json; print(json.load(sys.stdin).get('object_types', []))")
    fi
fi

# Create final result JSON
cat > /tmp/task_result.json <<EOF
{
    "output_exists": $OUTPUT_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "stl_imported": $STL_IMPORTED,
    "has_solid": $HAS_SOLID,
    "solid_valid": $SOLID_VALID,
    "solid_closed": $SOLID_CLOSED,
    "actual_volume": $ACTUAL_VOLUME,
    "expected_volume": $EXPECTED_VOLUME,
    "has_part_feature": $HAS_PART_FEATURE,
    "object_types": "$OBJECT_TYPES",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="