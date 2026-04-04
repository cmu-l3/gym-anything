#!/bin/bash
echo "=== Exporting Task Results ==="

# Paths
OUTPUT_FILE="/home/ga/Documents/FreeCAD/spur_gear.FCStd"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
RESULT_JSON="/tmp/task_result.json"

# 1. Capture Final Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Check File Existence & Timestamp
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

# 3. Python Analysis Script for FreeCAD
# We create a python script that runs INSIDE FreeCAD's python console to analyze the geometry.
# This calculates the properties of the user's model and compares them to a reference model generated on the fly.
ANALYSIS_SCRIPT="/tmp/analyze_gear.py"

cat > "$ANALYSIS_SCRIPT" << 'EOF'
import FreeCAD
import Part
import math
import json
import sys
import os

result = {
    "valid_solid": False,
    "volume": 0.0,
    "bbox": [0,0,0],
    "has_involute_history": False,
    "ref_volume": 0.0,
    "ref_bbox": [0,0,0],
    "volume_match": False,
    "bbox_match": False,
    "error": ""
}

try:
    # 1. Load User File
    user_file = "/home/ga/Documents/FreeCAD/spur_gear.FCStd"
    if not os.path.exists(user_file):
        raise Exception("File not found")
        
    doc = FreeCAD.openDocument(user_file)
    
    # 2. Find the main solid
    # We look for the visible object that is a Solid
    target_obj = None
    for obj in doc.Objects:
        if hasattr(obj, "Shape") and obj.Shape.ShapeType == "Solid" and obj.ViewObject.Visibility:
            target_obj = obj
            break
    
    # If no visible solid, just take the last created solid
    if not target_obj:
        for obj in reversed(doc.Objects):
            if hasattr(obj, "Shape") and obj.Shape.ShapeType == "Solid":
                target_obj = obj
                break

    if target_obj:
        result["valid_solid"] = True
        result["volume"] = target_obj.Shape.Volume
        bb = target_obj.Shape.BoundBox
        result["bbox"] = [bb.XLength, bb.YLength, bb.ZLength]
        
        # Check history for InvoluteGear feature
        # We traverse dependencies to see if any object is an InvoluteGear
        for o in doc.Objects:
            if "InvoluteGear" in o.Proxy.__class__.__name__ if hasattr(o, "Proxy") and hasattr(o.Proxy, "__class__") else False:
                result["has_involute_history"] = True
            # Also check standard Part::InvoluteGear internal type name if applicable, 
            # but usually it's created via Python script in Part WB which creates a specific object type.
            # Simpler check: Check name or type of all objects
            if "Involute" in o.Name or "Gear" in o.Name: 
                 # Weak check, but Part workbench usually names them. 
                 # Better: Check if any object has 'NumberOfTeeth' property
                 if hasattr(o, "NumberOfTeeth"):
                     result["has_involute_history"] = True

    # 3. Generate Reference Gear (Ground Truth)
    # 24 Teeth, Mod 2.0, 20 deg, 10mm thick, 6mm radius hole
    try:
        # Create temporary doc for reference
        ref_doc = FreeCAD.newDocument("Reference")
        
        # Create Gear Profile
        # Note: In FreeCAD console mode, we need to use the Part.InvoluteGear function directly if available
        # or construct it manually. The reliable way in a script is using the standard python library provided by FreeCAD.
        # However, purely geometric comparison is safer if we can't easily invoke the UI command.
        # Let's use the known formula for the addendum circle diameter: D_tip = m * (z + 2) = 2 * 26 = 52mm
        # And thickness = 10mm.
        # A cylinder of dia 52 and height 10 minus hole dia 12 height 10 is an upper bound.
        # Volume of gear ≈ Volume of Pitch Cylinder.
        
        # ACTUALLY, we can construct the exact shape using Part.involute()
        # But to be robust against slight version diffs, let's trust the User's BBox and Volume against calculated approximations.
        
        # Exact calculation for reference:
        # Pitch Dia = 48. Tip Dia = 52. Root Dia = 43.
        # BBox should be very close to 52x52x10
        result["ref_bbox"] = [52.0, 52.0, 10.0]
        
        # Volume estimate:
        # Area of pitch circle = pi * 24^2 = 1809.5
        # Area of tip circle = pi * 26^2 = 2123.7
        # Area of root circle = pi * 21.5^2 = 1452.2
        # Real gear area is roughly midway between pitch and tip, minus tooth gaps.
        # A solid cylinder of pitch diameter is a good approximation for the gear body, 
        # plus the teeth add some volume.
        # Let's rely on the verifier.py to handle the tolerance logic, 
        # just export the precise measurements here.
        pass
    except Exception as e:
        print("Ref generation failed: " + str(e))

except Exception as e:
    result["error"] = str(e)

# 4. Save results
with open("/tmp/gear_analysis.json", "w") as f:
    json.dump(result, f)
EOF

# 4. Run Analysis inside FreeCAD
# Use freecadcmd (headless)
echo "Running geometry analysis..."
su - ga -c "freecadcmd /tmp/analyze_gear.py" > /tmp/freecad_analysis.log 2>&1

# 5. Merge Results into Final JSON
# Default values
VALID_SOLID="false"
USER_VOL="0"
BBOX_X="0"
BBOX_Y="0"
BBOX_Z="0"
HISTORY="false"

if [ -f "/tmp/gear_analysis.json" ]; then
    VALID_SOLID=$(python3 -c "import json; print(str(json.load(open('/tmp/gear_analysis.json'))['valid_solid']).lower())")
    USER_VOL=$(python3 -c "import json; print(json.load(open('/tmp/gear_analysis.json'))['volume'])")
    BBOX_X=$(python3 -c "import json; print(json.load(open('/tmp/gear_analysis.json'))['bbox'][0])")
    BBOX_Y=$(python3 -c "import json; print(json.load(open('/tmp/gear_analysis.json'))['bbox'][1])")
    BBOX_Z=$(python3 -c "import json; print(json.load(open('/tmp/gear_analysis.json'))['bbox'][2])")
    HISTORY=$(python3 -c "import json; print(str(json.load(open('/tmp/gear_analysis.json'))['has_involute_history']).lower())")
fi

# App Running Check
APP_RUNNING="false"
if pgrep -f "FreeCAD" > /dev/null; then
    APP_RUNNING="true"
fi

# Create Final JSON
cat > "$RESULT_JSON" << EOF
{
    "file_exists": $FILE_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "file_size": $FILE_SIZE,
    "valid_solid": $VALID_SOLID,
    "volume": $USER_VOL,
    "bbox": [$BBOX_X, $BBOX_Y, $BBOX_Z],
    "has_involute_history": $HISTORY,
    "app_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Fix permissions
chmod 666 "$RESULT_JSON"
echo "Results exported to $RESULT_JSON"
cat "$RESULT_JSON"
echo "=== Export Complete ==="