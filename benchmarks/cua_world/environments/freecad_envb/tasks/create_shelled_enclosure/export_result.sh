#!/bin/bash
echo "=== Exporting create_shelled_enclosure results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
EXPECTED_PATH="/home/ga/Documents/FreeCAD/enclosure.FCStd"

# Take final screenshot
take_screenshot /tmp/task_final.png

# 1. Basic File Checks
FILE_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
FILE_SIZE="0"
IS_VALID_ZIP="false"

if [ -f "$EXPECTED_PATH" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$EXPECTED_PATH")
    FILE_MTIME=$(stat -c %Y "$EXPECTED_PATH")
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
    
    # Check if it's a valid zip (FCStd is a zip)
    if python3 -c "import zipfile; print(zipfile.is_zipfile('$EXPECTED_PATH'))" | grep -q "True"; then
        IS_VALID_ZIP="true"
    fi
fi

# 2. Advanced Geometry Analysis (Python inside container)
# We run this inside the container to access FreeCAD libraries
GEOMETRY_JSON="{}"

if [ "$IS_VALID_ZIP" = "true" ]; then
    echo "Running FreeCAD geometry analysis..."
    GEOMETRY_JSON=$(python3 << 'PYEOF'
import sys, json, os

# Setup FreeCAD path
sys.path.append('/usr/lib/freecad/lib')
sys.path.append('/usr/lib/freecad-python3/lib')

result = {
    "has_pad": False,
    "has_shell": False,
    "bbox": [0, 0, 0],
    "volume": 0,
    "faces": 0,
    "error": None
}

try:
    import FreeCAD
    
    # Open document
    doc_path = "/home/ga/Documents/FreeCAD/enclosure.FCStd"
    doc = FreeCAD.openDocument(doc_path)
    
    # Inspect Feature Tree
    for obj in doc.Objects:
        type_id = getattr(obj, "TypeId", "")
        name = getattr(obj, "Name", "").lower()
        
        # Check for Pad
        if "PartDesign::Pad" in type_id or "pad" in name:
            result["has_pad"] = True
            
        # Check for Thickness/Shell
        if "PartDesign::Thickness" in type_id or "thickness" in name or "shell" in name:
            result["has_shell"] = True
            
        # Get Shape stats from the visible/final object
        # Usually the last feature in the tree or the Tip
        if hasattr(obj, "Shape") and obj.Shape.Volume > 1000:
            # We track the last valid shape we see, which is usually the result
            # Or specifically look for the Body's Tip
            pass

    # Find the Body and its Tip
    body = None
    for obj in doc.Objects:
        if "PartDesign::Body" in obj.TypeId:
            body = obj
            break
            
    final_shape = None
    if body and hasattr(body, "Tip") and body.Tip and hasattr(body.Tip, "Shape"):
        final_shape = body.Tip.Shape
    else:
        # Fallback: check all objects for the most likely candidate
        for obj in doc.Objects:
            if hasattr(obj, "Shape") and obj.Shape.Volume > 0:
                final_shape = obj.Shape
                
    if final_shape:
        bb = final_shape.BoundBox
        result["bbox"] = [bb.XLength, bb.YLength, bb.ZLength]
        result["volume"] = final_shape.Volume
        result["faces"] = len(final_shape.Faces)

    FreeCAD.closeDocument(doc.Name)

except Exception as e:
    result["error"] = str(e)

print(json.dumps(result))
PYEOF
)
fi

# 3. Compile Final Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "file_exists": $FILE_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "file_size": $FILE_SIZE,
    "is_valid_fcstd": $IS_VALID_ZIP,
    "geometry_analysis": $GEOMETRY_JSON,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location with permissions
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="