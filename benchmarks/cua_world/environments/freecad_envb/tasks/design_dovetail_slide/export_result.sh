#!/bin/bash
set -e
echo "=== Exporting design_dovetail_slide results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
OUTPUT_PATH="/home/ga/Documents/FreeCAD/dovetail_slide.FCStd"

# Take final screenshot
take_screenshot /tmp/task_final.png

# Check if file exists and was modified during task
OUTPUT_EXISTS="false"
FILE_MODIFIED="false"
FILE_SIZE="0"

if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$OUTPUT_PATH")
    FILE_MTIME=$(stat -c %Y "$OUTPUT_PATH")
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED="true"
    fi
fi

# Application state
APP_RUNNING=$(pgrep -f "freecad" > /dev/null && echo "true" || echo "false")

# ---------------------------------------------------------
# GEOMETRY ANALYSIS
# Run a headless FreeCAD script to inspect the internal geometry
# ---------------------------------------------------------
ANALYSIS_JSON="/tmp/geometry_analysis.json"
echo "{}" > "$ANALYSIS_JSON"

if [ "$OUTPUT_EXISTS" = "true" ]; then
    echo "Running headless geometry analysis..."
    
    cat > /tmp/analyze_dovetail.py << 'EOF'
import FreeCAD
import json
import sys
import os

result = {
    "valid_file": False,
    "body_count": 0,
    "bodies": [],
    "total_volume": 0.0,
    "error": None
}

try:
    filepath = "/home/ga/Documents/FreeCAD/dovetail_slide.FCStd"
    if not os.path.exists(filepath):
        raise Exception("File not found")
        
    doc = FreeCAD.open(filepath)
    result["valid_file"] = True
    
    # Count bodies and measure volumes
    for obj in doc.Objects:
        # Check for PartDesign::Body
        if obj.TypeId == "PartDesign::Body":
            result["body_count"] += 1
            
            # Find the solid shape (Tip)
            if hasattr(obj, "Shape") and obj.Shape.isValid():
                vol = obj.Shape.Volume
                result["bodies"].append({
                    "label": obj.Label,
                    "volume": vol,
                    "center_of_mass": list(obj.Shape.CenterOfMass)
                })
                result["total_volume"] += vol
                
except Exception as e:
    result["error"] = str(e)

with open("/tmp/geometry_analysis.json", "w") as f:
    json.dump(result, f)
EOF

    # Execute with freecadcmd (headless)
    # We use sudo -u ga to run as user, but freecadcmd might need env vars
    su - ga -c "export DISPLAY=:1; freecadcmd /tmp/analyze_dovetail.py" || echo "Analysis script failed"
fi

# Read analysis result
ANALYSIS_CONTENT=$(cat "$ANALYSIS_JSON")
if [ -z "$ANALYSIS_CONTENT" ]; then ANALYSIS_CONTENT="{}"; fi

# Assemble final JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_exists": $OUTPUT_EXISTS,
    "file_modified": $FILE_MODIFIED,
    "file_size": $FILE_SIZE,
    "app_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png",
    "geometry_analysis": $ANALYSIS_CONTENT
}
EOF

# Move to standard location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="