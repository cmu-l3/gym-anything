#!/bin/bash
echo "=== Exporting Crime Scene Sketch Result ==="

OUTPUT_FILE="/home/ga/Documents/LibreCAD/crime_scene.dxf"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Capture Final Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Check File Metadata
FILE_EXISTS="false"
FILE_SIZE="0"
CREATED_DURING_TASK="false"

if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c%s "$OUTPUT_FILE")
    FILE_MTIME=$(stat -c%Y "$OUTPUT_FILE")
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        CREATED_DURING_TASK="true"
    fi
fi

# 3. Run Internal DXF Verification using ezdxf
# We run this inside the container because ezdxf is installed there.
# It outputs a detailed JSON analysis.

PYTHON_VERIFIER_SCRIPT="/tmp/verify_dxf_internal.py"
cat > "$PYTHON_VERIFIER_SCRIPT" << 'EOF'
import sys
import json
import ezdxf
import math

result = {
    "valid_dxf": False,
    "layers_found": [],
    "evidence_items": [],
    "measurement_lines": [],
    "text_labels": [],
    "floorplan_preserved": False
}

try:
    doc = ezdxf.readfile("/home/ga/Documents/LibreCAD/crime_scene.dxf")
    result["valid_dxf"] = True
    msp = doc.modelspace()

    # Check Layers
    expected_layers = ["EVIDENCE", "MEASUREMENTS"]
    for layer in doc.layers:
        result["layers_found"].append(layer.dxf.name)

    # Check Evidence Geometry (Layer: EVIDENCE)
    # Looking for Circle at (4500, 2500) r=50
    # Looking for Line (5000, 3000) -> (5600, 3200)
    for entity in msp.query('CIRCLE[layer=="EVIDENCE"]'):
        result["evidence_items"].append({
            "type": "CIRCLE",
            "center": list(entity.dxf.center)[:2],
            "radius": entity.dxf.radius
        })
    
    for entity in msp.query('LINE[layer=="EVIDENCE"]'):
        result["evidence_items"].append({
            "type": "LINE",
            "start": list(entity.dxf.start)[:2],
            "end": list(entity.dxf.end)[:2]
        })

    # Check Measurement Geometry (Layer: MEASUREMENTS)
    # Looking for lines connecting (4500, 2500) to (0,0) and (6000,0)
    for entity in msp.query('LINE[layer=="MEASUREMENTS"]'):
        result["measurement_lines"].append({
            "start": list(entity.dxf.start)[:2],
            "end": list(entity.dxf.end)[:2]
        })

    # Check Text
    for entity in msp.query('TEXT MTEXT'):
        if entity.dxf.layer == "EVIDENCE":
            # Handle MTEXT text attribute vs TEXT text attribute
            text_content = ""
            if entity.dxftype() == 'TEXT':
                text_content = entity.dxf.text
            elif entity.dxftype() == 'MTEXT':
                text_content = entity.text
            
            result["text_labels"].append(text_content)

    # Check Context Preservation
    # Original floorplan has > 100 entities. If we only have < 20, they deleted the floorplan.
    entity_count = len(list(msp))
    if entity_count > 50:
        result["floorplan_preserved"] = True
    result["entity_count"] = entity_count

except Exception as e:
    result["error"] = str(e)

with open("/tmp/dxf_analysis.json", "w") as f:
    json.dump(result, f)
EOF

# Execute the internal verifier
if [ "$FILE_EXISTS" = "true" ]; then
    python3 "$PYTHON_VERIFIER_SCRIPT" 2>/dev/null || echo '{"error": "Script failed"}' > /tmp/dxf_analysis.json
else
    echo '{"valid_dxf": false}' > /tmp/dxf_analysis.json
fi

# 4. Construct Final Result JSON
# Merge shell metadata with python analysis
# We use jq if available, or python to merge. Given environment, python is safer.

cat > /tmp/merge_results.py << EOF
import json
import os

try:
    with open('/tmp/dxf_analysis.json', 'r') as f:
        analysis = json.load(f)
except:
    analysis = {}

metadata = {
    "task_start": $TASK_START,
    "file_exists": $FILE_EXISTS,
    "file_size": $FILE_SIZE,
    "created_during_task": $CREATED_DURING_TASK,
    "screenshot_path": "/tmp/task_final.png"
}

final_result = {**metadata, **analysis}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(final_result, f)
EOF

python3 /tmp/merge_results.py

# 5. Permissions and Cleanup
chmod 666 /tmp/task_result.json
echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="