#!/bin/bash
echo "=== Exporting Annotate Findings Report Results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
echo "Task duration: $((TASK_END - TASK_START)) seconds"

# Take final screenshot of Slicer state
echo "Capturing final screenshot..."
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

SCREENSHOT_DIR="/home/ga/Documents/SlicerData/Screenshots"
EXPECTED_SCREENSHOT="$SCREENSHOT_DIR/annotated_cc_report.png"

# Check if Slicer is running
SLICER_RUNNING="false"
if pgrep -f "Slicer" > /dev/null 2>&1; then
    SLICER_RUNNING="true"
    echo "Slicer is running"
fi

# Initialize result variables
RULER_EXISTS="false"
RULER_LENGTH_MM="0"
RULER_POINT1="[0,0,0]"
RULER_POINT2="[0,0,0]"
RULER_Z_COORD="0"
TEXT_EXISTS="false"
TEXT_CONTENT=""
TEXT_POSITION="[0,0,0]"
FIDUCIAL_COUNT="0"
SCREENSHOT_EXISTS="false"
SCREENSHOT_SIZE_KB="0"
SCREENSHOT_CREATED_DURING_TASK="false"
DATA_LOADED="false"

# Query Slicer for markup information using Python script
if [ "$SLICER_RUNNING" = "true" ]; then
    echo "Extracting markup data from Slicer..."
    
    cat > /tmp/extract_annotations.py << 'PYEOF'
import slicer
import json
import os
import math

result = {
    "data_loaded": False,
    "volume_name": "",
    "ruler_exists": False,
    "ruler_count": 0,
    "ruler_length_mm": 0,
    "ruler_p1": [0, 0, 0],
    "ruler_p2": [0, 0, 0],
    "ruler_z_coord": 0,
    "text_exists": False,
    "text_count": 0,
    "text_content": "",
    "text_position": [0, 0, 0],
    "fiducial_count": 0,
    "all_markups": []
}

# Check for loaded volumes
volume_nodes = slicer.util.getNodesByClass("vtkMRMLScalarVolumeNode")
if volume_nodes:
    result["data_loaded"] = True
    result["volume_name"] = volume_nodes[0].GetName() if volume_nodes else ""
    print(f"Loaded volume: {result['volume_name']}")

# Check for line/ruler markups
line_nodes = slicer.util.getNodesByClass("vtkMRMLMarkupsLineNode")
result["ruler_count"] = len(line_nodes)
print(f"Found {len(line_nodes)} line/ruler markup(s)")

if line_nodes:
    result["ruler_exists"] = True
    # Get the first ruler with 2 points
    for node in line_nodes:
        if node.GetNumberOfControlPoints() >= 2:
            p1 = [0.0, 0.0, 0.0]
            p2 = [0.0, 0.0, 0.0]
            node.GetNthControlPointPosition(0, p1)
            node.GetNthControlPointPosition(1, p2)
            length = math.sqrt(sum((a-b)**2 for a, b in zip(p1, p2)))
            result["ruler_length_mm"] = round(length, 2)
            result["ruler_p1"] = [round(x, 2) for x in p1]
            result["ruler_p2"] = [round(x, 2) for x in p2]
            result["ruler_z_coord"] = round((p1[2] + p2[2]) / 2, 2)
            result["all_markups"].append({
                "type": "line",
                "name": node.GetName(),
                "length_mm": result["ruler_length_mm"],
                "p1": result["ruler_p1"],
                "p2": result["ruler_p2"]
            })
            print(f"  Ruler '{node.GetName()}': {length:.2f} mm")
            break

# Check for text markups (using MarkupsNode with text or fiducial with label)
# In Slicer 5.x, text annotations can be MarkupsFiducialNode with text property
# or dedicated text annotation

# First try dedicated text nodes if available
try:
    text_nodes = slicer.util.getNodesByClass("vtkMRMLMarkupsTextNode")
    result["text_count"] = len(text_nodes)
    if text_nodes:
        result["text_exists"] = True
        node = text_nodes[0]
        result["text_content"] = node.GetText() if hasattr(node, 'GetText') else node.GetName()
        if node.GetNumberOfControlPoints() > 0:
            pos = [0.0, 0.0, 0.0]
            node.GetNthControlPointPosition(0, pos)
            result["text_position"] = [round(x, 2) for x in pos]
        result["all_markups"].append({
            "type": "text",
            "name": node.GetName(),
            "content": result["text_content"],
            "position": result["text_position"]
        })
        print(f"  Text annotation: '{result['text_content']}'")
except:
    pass

# Also check fiducial nodes (often used for labeled annotations)
fiducial_nodes = slicer.util.getNodesByClass("vtkMRMLMarkupsFiducialNode")
result["fiducial_count"] = len(fiducial_nodes)
print(f"Found {len(fiducial_nodes)} fiducial markup(s)")

# If no dedicated text node, check fiducials for text-like labels
if not result["text_exists"] and fiducial_nodes:
    for node in fiducial_nodes:
        name = node.GetName().lower()
        # Check if this looks like a text annotation
        if "corpus" in name or "callosum" in name or "text" in name or "normal" in name:
            result["text_exists"] = True
            result["text_content"] = node.GetName()
            if node.GetNumberOfControlPoints() > 0:
                pos = [0.0, 0.0, 0.0]
                node.GetNthControlPointPosition(0, pos)
                result["text_position"] = [round(x, 2) for x in pos]
            result["all_markups"].append({
                "type": "fiducial_as_text",
                "name": node.GetName(),
                "content": result["text_content"],
                "position": result["text_position"]
            })
            print(f"  Fiducial as text: '{result['text_content']}'")
            break
        # Also check individual point labels
        for i in range(node.GetNumberOfControlPoints()):
            label = node.GetNthControlPointLabel(i)
            if label and ("corpus" in label.lower() or "callosum" in label.lower() or "normal" in label.lower()):
                result["text_exists"] = True
                result["text_content"] = label
                pos = [0.0, 0.0, 0.0]
                node.GetNthControlPointPosition(i, pos)
                result["text_position"] = [round(x, 2) for x in pos]
                result["all_markups"].append({
                    "type": "fiducial_label",
                    "name": node.GetName(),
                    "content": label,
                    "position": result["text_position"]
                })
                print(f"  Fiducial label: '{label}'")
                break
        if result["text_exists"]:
            break

# Save result
output_path = "/tmp/slicer_annotation_data.json"
with open(output_path, "w") as f:
    json.dump(result, f, indent=2)

print(f"\nAnnotation data saved to {output_path}")
print(json.dumps(result, indent=2))
PYEOF

    # Run the extraction script in Slicer
    DISPLAY=:1 /opt/Slicer/Slicer --no-splash --python-script /tmp/extract_annotations.py > /tmp/slicer_extract.log 2>&1 &
    EXTRACT_PID=$!
    sleep 8
    
    # Kill the extraction process if still running
    kill $EXTRACT_PID 2>/dev/null || true
    
    # Read the extracted data
    if [ -f /tmp/slicer_annotation_data.json ]; then
        echo "Reading extracted annotation data..."
        SLICER_DATA=$(cat /tmp/slicer_annotation_data.json)
        
        DATA_LOADED=$(echo "$SLICER_DATA" | python3 -c "import json,sys; d=json.load(sys.stdin); print('true' if d.get('data_loaded') else 'false')" 2>/dev/null || echo "false")
        RULER_EXISTS=$(echo "$SLICER_DATA" | python3 -c "import json,sys; d=json.load(sys.stdin); print('true' if d.get('ruler_exists') else 'false')" 2>/dev/null || echo "false")
        RULER_LENGTH_MM=$(echo "$SLICER_DATA" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('ruler_length_mm', 0))" 2>/dev/null || echo "0")
        TEXT_EXISTS=$(echo "$SLICER_DATA" | python3 -c "import json,sys; d=json.load(sys.stdin); print('true' if d.get('text_exists') else 'false')" 2>/dev/null || echo "false")
        TEXT_CONTENT=$(echo "$SLICER_DATA" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('text_content', ''))" 2>/dev/null || echo "")
        FIDUCIAL_COUNT=$(echo "$SLICER_DATA" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('fiducial_count', 0))" 2>/dev/null || echo "0")
    fi
fi

# Check for the expected screenshot file
if [ -f "$EXPECTED_SCREENSHOT" ]; then
    SCREENSHOT_EXISTS="true"
    SCREENSHOT_SIZE_KB=$(du -k "$EXPECTED_SCREENSHOT" 2>/dev/null | cut -f1 || echo "0")
    SCREENSHOT_MTIME=$(stat -c %Y "$EXPECTED_SCREENSHOT" 2>/dev/null || echo "0")
    
    # Check if screenshot was created during task
    if [ "$SCREENSHOT_MTIME" -gt "$TASK_START" ]; then
        SCREENSHOT_CREATED_DURING_TASK="true"
    fi
    echo "Found expected screenshot: ${SCREENSHOT_SIZE_KB}KB"
fi

# Also check for any new screenshots in the directory
INITIAL_COUNT=$(cat /tmp/initial_screenshot_count.txt 2>/dev/null || echo "0")
CURRENT_COUNT=$(ls -1 "$SCREENSHOT_DIR"/*.png 2>/dev/null | wc -l || echo "0")
NEW_SCREENSHOTS=$((CURRENT_COUNT - INITIAL_COUNT))

# Get the latest screenshot if expected one doesn't exist
LATEST_SCREENSHOT=""
if [ "$NEW_SCREENSHOTS" -gt 0 ]; then
    LATEST_SCREENSHOT=$(ls -t "$SCREENSHOT_DIR"/*.png 2>/dev/null | head -1)
    if [ -n "$LATEST_SCREENSHOT" ] && [ "$SCREENSHOT_EXISTS" = "false" ]; then
        # Use the latest screenshot instead
        SCREENSHOT_EXISTS="true"
        SCREENSHOT_SIZE_KB=$(du -k "$LATEST_SCREENSHOT" 2>/dev/null | cut -f1 || echo "0")
        SCREENSHOT_MTIME=$(stat -c %Y "$LATEST_SCREENSHOT" 2>/dev/null || echo "0")
        if [ "$SCREENSHOT_MTIME" -gt "$TASK_START" ]; then
            SCREENSHOT_CREATED_DURING_TASK="true"
        fi
        echo "Found alternate screenshot: $LATEST_SCREENSHOT (${SCREENSHOT_SIZE_KB}KB)"
    fi
fi

# Create result JSON
echo "Creating result JSON..."
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)

cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "task_duration_seconds": $((TASK_END - TASK_START)),
    "slicer_was_running": $SLICER_RUNNING,
    "data_loaded": $DATA_LOADED,
    "ruler_exists": $RULER_EXISTS,
    "ruler_length_mm": $RULER_LENGTH_MM,
    "text_exists": $TEXT_EXISTS,
    "text_content": "$TEXT_CONTENT",
    "fiducial_count": $FIDUCIAL_COUNT,
    "screenshot_exists": $SCREENSHOT_EXISTS,
    "screenshot_size_kb": $SCREENSHOT_SIZE_KB,
    "screenshot_created_during_task": $SCREENSHOT_CREATED_DURING_TASK,
    "new_screenshots_count": $NEW_SCREENSHOTS,
    "expected_screenshot_path": "$EXPECTED_SCREENSHOT",
    "latest_screenshot_path": "$LATEST_SCREENSHOT",
    "final_screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/annotation_task_result.json 2>/dev/null || sudo rm -f /tmp/annotation_task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/annotation_task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/annotation_task_result.json
chmod 666 /tmp/annotation_task_result.json 2>/dev/null || sudo chmod 666 /tmp/annotation_task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

# Copy screenshots for verification
if [ -f "$EXPECTED_SCREENSHOT" ]; then
    cp "$EXPECTED_SCREENSHOT" /tmp/user_screenshot.png 2>/dev/null || true
elif [ -n "$LATEST_SCREENSHOT" ] && [ -f "$LATEST_SCREENSHOT" ]; then
    cp "$LATEST_SCREENSHOT" /tmp/user_screenshot.png 2>/dev/null || true
fi

# Copy Slicer annotation data if exists
if [ -f /tmp/slicer_annotation_data.json ]; then
    chmod 666 /tmp/slicer_annotation_data.json 2>/dev/null || true
fi

echo ""
echo "=== Export Complete ==="
echo "Result saved to /tmp/annotation_task_result.json"
cat /tmp/annotation_task_result.json
echo ""