#!/bin/bash
echo "=== Exporting create_polar_pattern results ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
OUTPUT_PATH="/home/ga/Documents/FreeCAD/nema23_motor_flange.FCStd"
ANALYSIS_JSON="/tmp/fc_analysis.json"

# 1. Capture Final Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Check File Existence and Timestamps
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

# 3. Analyze FreeCAD File Geometry using FreeCADCMD (Python)
# We create a temporary python script to run inside FreeCAD's environment
cat > /tmp/analyze_geometry.py << EOF
import FreeCAD
import Part
import json
import sys
import os

result = {
    "valid_doc": False,
    "has_body": False,
    "has_pad": False,
    "has_pocket": False,
    "has_polar_pattern": False,
    "feature_count": 0,
    "bbox": [0, 0, 0],
    "volume": 0,
    "error": ""
}

file_path = "$OUTPUT_PATH"

try:
    if os.path.exists(file_path):
        doc = FreeCAD.open(file_path)
        result["valid_doc"] = True
        
        # Check for Body
        bodies = [obj for obj in doc.Objects if obj.TypeId == 'PartDesign::Body']
        if bodies:
            result["has_body"] = True
            body = bodies[0]
            
            # Check features inside Body (using Group property or OutList)
            # Note: PartDesign features are usually linked in the Group
            for obj in doc.Objects:
                if obj.TypeId == 'PartDesign::Pad':
                    result["has_pad"] = True
                elif obj.TypeId == 'PartDesign::Pocket':
                    result["has_pocket"] = True
                elif obj.TypeId == 'PartDesign::PolarPattern':
                    result["has_polar_pattern"] = True
            
            result["feature_count"] = len(doc.Objects)
            
            # Analyze Shape Geometry
            if body.Shape.isValid():
                bbox = body.Shape.BoundBox
                result["bbox"] = [bbox.XLength, bbox.YLength, bbox.ZLength]
                result["volume"] = body.Shape.Volume
            else:
                # Fallback: check the Tip of the body
                if hasattr(body, 'Tip') and body.Tip and body.Tip.Shape.isValid():
                    bbox = body.Tip.Shape.BoundBox
                    result["bbox"] = [bbox.XLength, bbox.YLength, bbox.ZLength]
                    result["volume"] = body.Tip.Shape.Volume

except Exception as e:
    result["error"] = str(e)

with open("$ANALYSIS_JSON", "w") as f:
    json.dump(result, f)
EOF

# Run the analysis script if the file exists
if [ "$OUTPUT_EXISTS" = "true" ]; then
    echo "Running geometry analysis..."
    # We use freecadcmd which is the headless version
    freecadcmd /tmp/analyze_geometry.py > /tmp/analysis.log 2>&1
else
    echo "{}" > "$ANALYSIS_JSON"
fi

# 4. Consolidate Results into task_result.json
# We read the analysis json content
ANALYSIS_CONTENT=$(cat "$ANALYSIS_JSON" 2>/dev/null || echo "{}")

# Create the final JSON structure using python to ensure valid JSON format
python3 -c "
import json
import sys

try:
    analysis = json.loads('''$ANALYSIS_CONTENT''')
except:
    analysis = {}

result = {
    'task_start': $TASK_START,
    'output_exists': $OUTPUT_EXISTS,
    'file_created_during_task': $FILE_CREATED_DURING_TASK,
    'file_size_bytes': $FILE_SIZE,
    'geometry_analysis': analysis,
    'screenshot_path': '/tmp/task_final.png'
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
"

# Cleanup
rm -f /tmp/analyze_geometry.py /tmp/fc_analysis.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="