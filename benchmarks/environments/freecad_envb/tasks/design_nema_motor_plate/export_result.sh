#!/bin/bash
echo "=== Exporting design_nema_motor_plate results ==="

# Source utilities (if available) or define minimal needed
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)
OUTPUT_FILE="/home/ga/Documents/FreeCAD/nema_plate.FCStd"

# 1. Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Check file existence and timestamp
FILE_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
FILE_SIZE="0"

if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$OUTPUT_FILE")
    FILE_MTIME=$(stat -c %Y "$OUTPUT_FILE")
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# 3. Analyze the FreeCAD file using FreeCAD's internal Python API
# We do this INSIDE the container because the host verification script 
# might not have the FreeCAD library installed.
GEOMETRY_ANALYSIS="{}"

if [ "$FILE_EXISTS" = "true" ]; then
    echo "Running internal geometry analysis..."
    
    # Create a temporary python script to analyze the file
    cat > /tmp/analyze_nema.py << 'PYEOF'
import FreeCAD
import Part
import json
import sys

result = {
    "valid_file": False,
    "volume": 0.0,
    "bbox": [0.0, 0.0, 0.0],
    "feature_types": [],
    "hole_properties": {}
}

try:
    doc = FreeCAD.openDocument('/home/ga/Documents/FreeCAD/nema_plate.FCStd')
    
    # Find the active body
    bodies = doc.findObjects(Type='PartDesign::Body')
    
    if bodies:
        body = bodies[0]
        # Ensure geometry is up to date
        doc.recompute()
        
        if body.Shape.isValid():
            result["valid_file"] = True
            result["volume"] = body.Shape.Volume
            bb = body.Shape.BoundBox
            result["bbox"] = [bb.XLength, bb.YLength, bb.ZLength]
            
            # Collect all feature types in the body
            for obj in body.Group:
                result["feature_types"].append(obj.TypeId)
                
                # If it is a Hole, get its properties
                if obj.TypeId == 'PartDesign::Hole':
                    props = {}
                    # Try to get relevant properties safely
                    try: props['ThreadSize'] = obj.ThreadSize
                    except: pass
                    try: props['HoleType'] = obj.HoleType
                    except: pass
                    try: props['Diameter'] = obj.Diameter.Value
                    except: pass
                    result["hole_properties"] = props
                    
except Exception as e:
    result["error"] = str(e)

print(json.dumps(result))
PYEOF

    # Run the script using freecadcmd (headless)
    # We use a timeout to prevent hanging if FreeCAD crashes
    GEOMETRY_ANALYSIS=$(timeout 30s su - ga -c "freecadcmd /tmp/analyze_nema.py" 2>/dev/null | grep -v "FreeCAD") || echo "{}"
    
    # Clean up output to ensure valid JSON (remove any startup logs that might have leaked)
    GEOMETRY_ANALYSIS=$(echo "$GEOMETRY_ANALYSIS" | grep "^{.*}$" | tail -n 1)
    if [ -z "$GEOMETRY_ANALYSIS" ]; then GEOMETRY_ANALYSIS="{}"; fi
fi

# 4. Check if app is running
APP_RUNNING=$(pgrep -f "FreeCAD" > /dev/null && echo "true" || echo "false")

# 5. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_exists": $FILE_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "output_size_bytes": $FILE_SIZE,
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png",
    "geometry_analysis": $GEOMETRY_ANALYSIS
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON" /tmp/analyze_nema.py

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="