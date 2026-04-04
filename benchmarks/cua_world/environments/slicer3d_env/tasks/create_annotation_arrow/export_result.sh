#!/bin/bash
echo "=== Exporting Create Annotation Arrow Result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

SCREENSHOT_DIR="/home/ga/Documents/SlicerData/Screenshots"
EXPECTED_SCREENSHOT="$SCREENSHOT_DIR/ventricle_annotation.png"

# Take final screenshot of Slicer state
echo "Capturing final screenshot..."
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# Check if Slicer is running
SLICER_RUNNING="false"
SLICER_PID=""
if pgrep -f "Slicer" > /dev/null 2>&1; then
    SLICER_RUNNING="true"
    SLICER_PID=$(pgrep -f "Slicer" | head -1)
fi

# ============================================================
# Export markup data from Slicer
# ============================================================
MARKUPS_JSON="/tmp/slicer_markups_export.json"
rm -f "$MARKUPS_JSON" 2>/dev/null || true

if [ "$SLICER_RUNNING" = "true" ]; then
    echo "Exporting markups from Slicer..."
    
    cat > /tmp/export_markups.py << 'PYEOF'
import slicer
import json
import os
import math

output_path = "/tmp/slicer_markups_export.json"
result = {
    "arrow_nodes": [],
    "line_nodes": [],
    "fiducial_nodes": [],
    "all_markups": [],
    "volume_loaded": False,
    "volume_name": ""
}

# Check if volume is loaded
volume_nodes = slicer.util.getNodesByClass("vtkMRMLScalarVolumeNode")
if volume_nodes and volume_nodes.GetNumberOfItems() > 0:
    result["volume_loaded"] = True
    vol = volume_nodes.GetItemAsObject(0)
    result["volume_name"] = vol.GetName() if vol else ""

# Get all markup nodes
for node_class in ["vtkMRMLMarkupsLineNode", "vtkMRMLMarkupsFiducialNode", "vtkMRMLMarkupsROINode"]:
    nodes = slicer.util.getNodesByClass(node_class)
    if nodes:
        for i in range(nodes.GetNumberOfItems()):
            node = nodes.GetItemAsObject(i)
            if node:
                markup_info = {
                    "name": node.GetName(),
                    "class": node_class,
                    "n_control_points": node.GetNumberOfControlPoints(),
                    "control_points": [],
                    "labels": []
                }
                
                # Get control points
                for j in range(node.GetNumberOfControlPoints()):
                    pos = [0.0, 0.0, 0.0]
                    node.GetNthControlPointPosition(j, pos)
                    label = node.GetNthControlPointLabel(j)
                    markup_info["control_points"].append(pos)
                    markup_info["labels"].append(label)
                
                # Calculate length for line nodes
                if node_class == "vtkMRMLMarkupsLineNode" and len(markup_info["control_points"]) >= 2:
                    p1 = markup_info["control_points"][0]
                    p2 = markup_info["control_points"][1]
                    length = math.sqrt(sum((a-b)**2 for a,b in zip(p1, p2)))
                    markup_info["length_mm"] = length
                    
                    # Check if it might be an arrow (line nodes can be arrows)
                    result["line_nodes"].append(markup_info)
                    
                    # Also add to arrow_nodes if name suggests arrow
                    name_lower = node.GetName().lower()
                    if "arrow" in name_lower or "ventricle" in name_lower or "lateral" in name_lower:
                        result["arrow_nodes"].append(markup_info)
                
                elif node_class == "vtkMRMLMarkupsFiducialNode":
                    result["fiducial_nodes"].append(markup_info)
                
                result["all_markups"].append(markup_info)

# Also check for any markup with "ventricle" in name
for markup in result["all_markups"]:
    name_lower = markup.get("name", "").lower()
    if "ventricle" in name_lower or "lateral" in name_lower:
        if markup not in result["arrow_nodes"]:
            result["arrow_nodes"].append(markup)

with open(output_path, "w") as f:
    json.dump(result, f, indent=2)

print(f"Exported {len(result['all_markups'])} markups to {output_path}")
print(f"Arrow/ventricle markups: {len(result['arrow_nodes'])}")
print(f"Line nodes: {len(result['line_nodes'])}")
PYEOF

    # Run the export script via Slicer
    sudo -u ga DISPLAY=:1 timeout 30 /opt/Slicer/Slicer --no-main-window --python-script /tmp/export_markups.py > /tmp/slicer_export.log 2>&1 || true
    sleep 3
fi

# ============================================================
# Check for expected screenshot
# ============================================================
SCREENSHOT_EXISTS="false"
SCREENSHOT_SIZE_KB=0
SCREENSHOT_CREATED_DURING_TASK="false"

if [ -f "$EXPECTED_SCREENSHOT" ]; then
    SCREENSHOT_EXISTS="true"
    SCREENSHOT_SIZE_KB=$(du -k "$EXPECTED_SCREENSHOT" 2>/dev/null | cut -f1 || echo "0")
    
    # Check if created during task
    SCREENSHOT_MTIME=$(stat -c%Y "$EXPECTED_SCREENSHOT" 2>/dev/null || echo "0")
    if [ "$SCREENSHOT_MTIME" -gt "$TASK_START" ]; then
        SCREENSHOT_CREATED_DURING_TASK="true"
    fi
    echo "Found expected screenshot: $EXPECTED_SCREENSHOT (${SCREENSHOT_SIZE_KB}KB)"
fi

# Check for any new screenshots
INITIAL_COUNT=$(cat /tmp/initial_screenshot_count.txt 2>/dev/null || echo "0")
FINAL_COUNT=$(ls -1 "$SCREENSHOT_DIR"/*.png 2>/dev/null | wc -l || echo "0")
NEW_SCREENSHOTS=$((FINAL_COUNT - INITIAL_COUNT))

# Find newest screenshot if expected one doesn't exist
NEWEST_SCREENSHOT=""
NEWEST_SCREENSHOT_SIZE=0
if [ "$NEW_SCREENSHOTS" -gt 0 ]; then
    NEWEST_SCREENSHOT=$(ls -t "$SCREENSHOT_DIR"/*.png 2>/dev/null | head -1)
    if [ -n "$NEWEST_SCREENSHOT" ] && [ -f "$NEWEST_SCREENSHOT" ]; then
        NEWEST_SCREENSHOT_SIZE=$(du -k "$NEWEST_SCREENSHOT" 2>/dev/null | cut -f1 || echo "0")
        # Copy to expected location if expected doesn't exist
        if [ "$SCREENSHOT_EXISTS" = "false" ]; then
            cp "$NEWEST_SCREENSHOT" "$EXPECTED_SCREENSHOT" 2>/dev/null || true
            SCREENSHOT_EXISTS="true"
            SCREENSHOT_SIZE_KB=$NEWEST_SCREENSHOT_SIZE
            SCREENSHOT_CREATED_DURING_TASK="true"
        fi
    fi
fi

# Also check common screenshot locations
for alt_path in "/home/ga/Desktop/Screenshot"*.png "/home/ga/"*screenshot*.png "/tmp/slicer"*".png"; do
    for f in $alt_path; do
        if [ -f "$f" ] && [ "$SCREENSHOT_EXISTS" = "false" ]; then
            ALT_MTIME=$(stat -c%Y "$f" 2>/dev/null || echo "0")
            if [ "$ALT_MTIME" -gt "$TASK_START" ]; then
                echo "Found alternate screenshot: $f"
                cp "$f" "$EXPECTED_SCREENSHOT" 2>/dev/null || true
                SCREENSHOT_EXISTS="true"
                SCREENSHOT_SIZE_KB=$(du -k "$f" 2>/dev/null | cut -f1 || echo "0")
                SCREENSHOT_CREATED_DURING_TASK="true"
                break 2
            fi
        fi
    done
done

# ============================================================
# Parse markup export data
# ============================================================
ARROW_EXISTS="false"
ARROW_LABEL=""
ARROW_POSITION=""
VOLUME_LOADED="false"
NUM_ARROWS=0
NUM_ALL_MARKUPS=0

if [ -f "$MARKUPS_JSON" ]; then
    echo "Parsing markup export..."
    
    PARSED=$(python3 << PYEOF
import json
import sys

try:
    with open("$MARKUPS_JSON") as f:
        data = json.load(f)
    
    volume_loaded = data.get("volume_loaded", False)
    arrow_nodes = data.get("arrow_nodes", [])
    line_nodes = data.get("line_nodes", [])
    all_markups = data.get("all_markups", [])
    
    # Find arrow with ventricle-related label
    best_arrow = None
    for arrow in arrow_nodes + line_nodes:
        name = arrow.get("name", "").lower()
        labels = [l.lower() for l in arrow.get("labels", [])]
        all_text = name + " " + " ".join(labels)
        
        if "ventricle" in all_text or "lateral" in all_text:
            best_arrow = arrow
            break
    
    # If no ventricle label, use any arrow/line
    if not best_arrow and (arrow_nodes or line_nodes):
        best_arrow = (arrow_nodes + line_nodes)[0]
    
    result = {
        "arrow_exists": best_arrow is not None,
        "arrow_label": best_arrow.get("name", "") if best_arrow else "",
        "arrow_position": best_arrow.get("control_points", [[0,0,0]])[0] if best_arrow else [0,0,0],
        "volume_loaded": volume_loaded,
        "num_arrows": len(arrow_nodes) + len(line_nodes),
        "num_all_markups": len(all_markups)
    }
    
    print(json.dumps(result))
except Exception as e:
    print(json.dumps({"error": str(e), "arrow_exists": False}))
PYEOF
)
    
    ARROW_EXISTS=$(echo "$PARSED" | python3 -c "import json,sys; print('true' if json.load(sys.stdin).get('arrow_exists') else 'false')" 2>/dev/null || echo "false")
    ARROW_LABEL=$(echo "$PARSED" | python3 -c "import json,sys; print(json.load(sys.stdin).get('arrow_label', ''))" 2>/dev/null || echo "")
    ARROW_POSITION=$(echo "$PARSED" | python3 -c "import json,sys; print(json.load(sys.stdin).get('arrow_position', [0,0,0]))" 2>/dev/null || echo "[0,0,0]")
    VOLUME_LOADED=$(echo "$PARSED" | python3 -c "import json,sys; print('true' if json.load(sys.stdin).get('volume_loaded') else 'false')" 2>/dev/null || echo "false")
    NUM_ARROWS=$(echo "$PARSED" | python3 -c "import json,sys; print(json.load(sys.stdin).get('num_arrows', 0))" 2>/dev/null || echo "0")
    NUM_ALL_MARKUPS=$(echo "$PARSED" | python3 -c "import json,sys; print(json.load(sys.stdin).get('num_all_markups', 0))" 2>/dev/null || echo "0")
fi

# ============================================================
# Create result JSON
# ============================================================
echo "Creating result JSON..."

TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "slicer_was_running": $SLICER_RUNNING,
    "volume_loaded": $VOLUME_LOADED,
    "arrow_exists": $ARROW_EXISTS,
    "arrow_label": "$ARROW_LABEL",
    "arrow_position": $ARROW_POSITION,
    "num_arrows": $NUM_ARROWS,
    "num_all_markups": $NUM_ALL_MARKUPS,
    "screenshot_exists": $SCREENSHOT_EXISTS,
    "screenshot_size_kb": $SCREENSHOT_SIZE_KB,
    "screenshot_created_during_task": $SCREENSHOT_CREATED_DURING_TASK,
    "new_screenshots_count": $NEW_SCREENSHOTS,
    "expected_screenshot_path": "$EXPECTED_SCREENSHOT",
    "final_screenshot_path": "/tmp/task_final.png",
    "markups_export_path": "$MARKUPS_JSON"
}
EOF

# Move to final location
rm -f /tmp/annotation_task_result.json 2>/dev/null || sudo rm -f /tmp/annotation_task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/annotation_task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/annotation_task_result.json
chmod 666 /tmp/annotation_task_result.json 2>/dev/null || sudo chmod 666 /tmp/annotation_task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

# Copy screenshots for verification
if [ -f "$EXPECTED_SCREENSHOT" ]; then
    cp "$EXPECTED_SCREENSHOT" /tmp/ventricle_annotation.png 2>/dev/null || true
fi

echo ""
echo "=== Export Result ==="
cat /tmp/annotation_task_result.json
echo ""
echo "=== Export Complete ==="