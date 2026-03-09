#!/bin/bash
echo "=== Exporting Casting Mold Result ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
OUTPUT_FILE="/home/ga/Documents/FreeCAD/mold_cavity.FCStd"
REF_FILE="/home/ga/Documents/FreeCAD/T8_housing_bracket.FCStd"
ANALYSIS_JSON="/tmp/geometry_analysis.json"

# Capture final screenshot
take_screenshot /tmp/task_final.png

# Check file metadata
OUTPUT_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
FILE_SIZE="0"

if [ -f "$OUTPUT_FILE" ]; then
    OUTPUT_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$OUTPUT_FILE")
    FILE_MTIME=$(stat -c %Y "$OUTPUT_FILE")
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# ==============================================================================
# GEOMETRY ANALYSIS
# Run a headless FreeCAD Python script to analyze the submitted model
# ==============================================================================

cat > /tmp/analyze_mold.py << PYEOF
import FreeCAD
import json
import sys
import math

result = {
    "valid_solid": False,
    "mold_volume": 0.0,
    "mold_bbox": None,
    "mold_center": None,
    "bracket_volume": 0.0,
    "bracket_bbox": None,
    "bracket_center": None,
    "transparency": 0,
    "error": None
}

try:
    # 1. Load Reference (Bracket)
    # We open the original file to get ground truth values
    try:
        doc_ref = FreeCAD.open("$REF_FILE")
        # Find the main body/solid (usually the largest object)
        bracket_obj = None
        max_vol = 0
        for obj in doc_ref.Objects:
            if hasattr(obj, "Shape") and obj.Shape.Volume > max_vol:
                max_vol = obj.Shape.Volume
                bracket_obj = obj
        
        if bracket_obj:
            bb = bracket_obj.Shape.BoundBox
            result["bracket_volume"] = bracket_obj.Shape.Volume
            result["bracket_bbox"] = [bb.XLength, bb.YLength, bb.ZLength]
            result["bracket_center"] = [bb.Center.x, bb.Center.y, bb.Center.z]
        else:
            result["error"] = "Reference bracket not found in file"
        FreeCAD.closeDocument(doc_ref.Name)
    except Exception as e:
        result["error"] = f"Failed to load reference: {str(e)}"

    # 2. Load Submission (Mold)
    if "$OUTPUT_EXISTS" == "true":
        try:
            doc_sub = FreeCAD.open("$OUTPUT_FILE")
            # Find the result object (should be a Cut or a Box)
            # We look for the visible object
            mold_obj = None
            for obj in doc_sub.Objects:
                if obj.ViewObject.Visibility and hasattr(obj, "Shape"):
                    # Use this one
                    mold_obj = obj
                    break # Take the first visible shape
            
            if not mold_obj and len(doc_sub.Objects) > 0:
                # Fallback: take the last object
                mold_obj = doc_sub.Objects[-1]

            if mold_obj and hasattr(mold_obj, "Shape") and mold_obj.Shape.Volume > 0:
                bb = mold_obj.Shape.BoundBox
                result["valid_solid"] = True
                result["mold_volume"] = mold_obj.Shape.Volume
                result["mold_bbox"] = [bb.XLength, bb.YLength, bb.ZLength]
                result["mold_center"] = [bb.Center.x, bb.Center.y, bb.Center.z]
                
                # Check visual property
                if hasattr(mold_obj, "ViewObject") and hasattr(mold_obj.ViewObject, "Transparency"):
                    result["transparency"] = mold_obj.ViewObject.Transparency
            
            FreeCAD.closeDocument(doc_sub.Name)
        except Exception as e:
            result["error"] = f"Failed to load submission: {str(e)}"

except Exception as e:
    result["error"] = str(e)

with open("$ANALYSIS_JSON", "w") as f:
    json.dump(result, f)
PYEOF

# Run analysis inside container environment
if [ "$OUTPUT_EXISTS" == "true" ]; then
    echo "Running geometry analysis..."
    # We use freecadcmd for headless execution
    # Using ' || true' to ensure script continues even if FreeCAD errors (verification handles the error)
    DISPLAY=:1 freecadcmd /tmp/analyze_mold.py > /tmp/freecad_analysis.log 2>&1 || true
else
    # Create empty result if file missing
    echo '{"valid_solid": false, "error": "Output file missing"}' > "$ANALYSIS_JSON"
fi

# ==============================================================================
# JSON EXPORT
# ==============================================================================

# Merge analysis with file stats
# Use Python to safely merge JSONs
python3 -c "
import json
try:
    with open('$ANALYSIS_JSON') as f:
        analysis = json.load(f)
except:
    analysis = {}

result = {
    'output_exists': '$OUTPUT_EXISTS' == 'true',
    'file_created_during_task': '$FILE_CREATED_DURING_TASK' == 'true',
    'file_size_bytes': int('$FILE_SIZE'),
    'geometry_analysis': analysis,
    'screenshot_path': '/tmp/task_final.png',
    'task_id': 'create_casting_mold'
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
"

# Handle permissions
chmod 666 /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="