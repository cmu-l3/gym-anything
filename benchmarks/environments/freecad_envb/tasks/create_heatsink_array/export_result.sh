#!/bin/bash
echo "=== Exporting create_heatsink_array results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Check output file details
OUTPUT_PATH="/home/ga/Documents/FreeCAD/heatsink.FCStd"
OUTPUT_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
FILE_SIZE="0"

if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$OUTPUT_PATH")
    FILE_MTIME=$(stat -c %Y "$OUTPUT_PATH")
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# 3. Analyze Geometry using FreeCAD internal python (run inside container)
# We generate a python script that FreeCADCmd will execute to inspect the file
echo "Generating analysis script..."
cat > /tmp/analyze_heatsink.py << 'PYEOF'
import FreeCAD
import sys
import json
import os

result = {
    "valid_file": False,
    "bbox": [0, 0, 0],
    "volume": 0,
    "has_linear_pattern": False,
    "feature_count": 0,
    "solid_count": 0,
    "error": ""
}

file_path = "/home/ga/Documents/FreeCAD/heatsink.FCStd"

try:
    if os.path.exists(file_path):
        # Open document non-graphically
        doc = FreeCAD.openDocument(file_path)
        result["valid_file"] = True
        
        # Find the main body/shape
        # We look for the visible Tip of the active body or the last feature
        solid_obj = None
        
        # Search for PartDesign::Body
        bodies = doc.findObjects(Type="PartDesign::Body")
        if bodies:
            body = bodies[0]
            if body.Tip and hasattr(body.Tip, "Shape"):
                solid_obj = body.Tip
        
        # If no Body, check for Part features
        if not solid_obj:
            # Look for the object with the largest volume
            max_vol = 0
            for obj in doc.Objects:
                if hasattr(obj, "Shape") and obj.Shape.Volume > max_vol:
                    max_vol = obj.Shape.Volume
                    solid_obj = obj

        # Analyze Geometry
        if solid_obj and hasattr(solid_obj, "Shape"):
            shape = solid_obj.Shape
            bbox = shape.BoundBox
            result["bbox"] = [bbox.XLength, bbox.YLength, bbox.ZLength]
            result["volume"] = shape.Volume
            result["solid_count"] = len(shape.Solids)
        
        # Analyze Features (Tree)
        for obj in doc.Objects:
            result["feature_count"] += 1
            # Check for LinearPattern (PartDesign) or Array (Draft/Part)
            if "LinearPattern" in obj.TypeId or "LinearPattern" in obj.Name:
                result["has_linear_pattern"] = True
            # Also check label/type for variations
            if "Pattern" in obj.TypeId:
                result["has_linear_pattern"] = True

    else:
        result["error"] = "File not found"

except Exception as e:
    result["error"] = str(e)

# Output JSON
with open("/tmp/geometry_report.json", "w") as f:
    json.dump(result, f)

print("Analysis complete.")
PYEOF

# Run the analysis script using FreeCADCmd (headless)
if [ "$OUTPUT_EXISTS" = "true" ]; then
    echo "Running geometry analysis..."
    # We use 'su - ga' to run as user, but FreeCADCmd might need display unset or handled
    # Using 'freecadcmd' directly. Note: on some systems it's 'freecad-python3' or 'FreeCADCmd'
    
    CMD="freecadcmd"
    if ! command -v freecadcmd &> /dev/null; then
        CMD="FreeCADCmd"
    fi
    
    # Run analysis
    $CMD /tmp/analyze_heatsink.py > /tmp/analysis.log 2>&1 || true
fi

# 4. Check if App was running
APP_RUNNING=$(pgrep -f "FreeCAD" > /dev/null && echo "true" || echo "false")

# 5. Create final result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_exists": $OUTPUT_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "output_size_bytes": $FILE_SIZE,
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move results to final locations
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
chmod 666 /tmp/geometry_report.json 2>/dev/null || true

echo "=== Export complete ==="