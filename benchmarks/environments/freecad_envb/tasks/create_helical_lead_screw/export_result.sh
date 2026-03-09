#!/bin/bash
echo "=== Exporting create_helical_lead_screw result ==="

# Source utilities
source /workspace/scripts/task_utils.sh

TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
FCSTD_PATH="/home/ga/Documents/FreeCAD/lead_screw.FCStd"
STEP_PATH="/home/ga/Documents/FreeCAD/lead_screw.step"

# Capture final screenshot
take_screenshot /tmp/task_final.png

# Check file existence and timestamps
FCSTD_EXISTS="false"
STEP_EXISTS="false"
FCSTD_CREATED_DURING_TASK="false"

if [ -f "$FCSTD_PATH" ]; then
    FCSTD_EXISTS="true"
    MTIME=$(stat -c %Y "$FCSTD_PATH")
    if [ "$MTIME" -gt "$TASK_START" ]; then
        FCSTD_CREATED_DURING_TASK="true"
    fi
fi

if [ -f "$STEP_PATH" ]; then
    STEP_EXISTS="true"
fi

# ------------------------------------------------------------------
# GEOMETRIC ANALYSIS USING FREECADCMD (PYTHON)
# ------------------------------------------------------------------
# We run a python script INSIDE the container to inspect the model geometry
# This avoids needing FreeCAD installed on the verifier side.

ANALYSIS_JSON="/tmp/geometry_analysis.json"
echo "{}" > "$ANALYSIS_JSON"

if [ "$FCSTD_EXISTS" = "true" ]; then
    echo "Running geometric analysis on $FCSTD_PATH..."
    
    cat > /tmp/analyze_geometry.py << PYEOF
import FreeCAD
import sys
import json
import math

result = {
    "valid_file": False,
    "volume": 0.0,
    "bbox_x": 0.0,
    "bbox_y": 0.0,
    "bbox_z": 0.0,
    "has_helix": False,
    "has_cut": False,
    "error": ""
}

try:
    doc = FreeCAD.openDocument("$FCSTD_PATH")
    result["valid_file"] = True
    
    # Analyze objects
    total_volume = 0.0
    bbox = [0, 0, 0, 0, 0, 0] # minx, miny, minz, maxx, maxy, maxz
    initialized = False
    
    for obj in doc.Objects:
        # Check for Helix feature
        if "Helix" in obj.Name or (hasattr(obj, "TypeId") and "Helix" in obj.TypeId):
            result["has_helix"] = True
        
        # Check for boolean cut/subtraction
        if "Cut" in obj.Name or "Boolean" in obj.Name:
            result["has_cut"] = True
            
        # Sum volume of visible solids (usually the final result)
        # Note: In PartDesign, usually only the Tip is visible, or the last feature.
        # We'll look for solids.
        if hasattr(obj, "Shape") and obj.Shape.Solid:
            # We assume the largest solid is the final part
            vol = obj.Shape.Volume
            if vol > total_volume:
                total_volume = vol
                bb = obj.Shape.BoundBox
                result["bbox_x"] = bb.XLength
                result["bbox_y"] = bb.YLength
                result["bbox_z"] = bb.ZLength

    result["volume"] = total_volume

except Exception as e:
    result["error"] = str(e)

print(json.dumps(result))
PYEOF

    # Run the analysis using FreeCADCmd (headless)
    # We use 'su - ga' to ensure permissions match, but FreeCADCmd might need display logic or env vars
    # Using 'freecadcmd' directly usually works for non-GUI operations.
    # Note: FreeCAD outputs a lot of text to stdout/stderr. We need to filter for the JSON.
    
    ANALYSIS_OUTPUT=$(su - ga -c "freecadcmd /tmp/analyze_geometry.py" 2>&1 | grep "^{.*}" | tail -n 1 || echo "")
    
    if [ -n "$ANALYSIS_OUTPUT" ]; then
        echo "$ANALYSIS_OUTPUT" > "$ANALYSIS_JSON"
    fi
fi

# Combine all results into final JSON
cat > /tmp/task_result.json << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "fcstd_exists": $FCSTD_EXISTS,
    "step_exists": $STEP_EXISTS,
    "file_created_during_task": $FCSTD_CREATED_DURING_TASK,
    "geometry": $(cat "$ANALYSIS_JSON"),
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Ensure permissions
chmod 666 /tmp/task_result.json
echo "Export complete. Result:"
cat /tmp/task_result.json