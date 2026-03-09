#!/bin/bash
echo "=== Exporting Organize Planning Segments Result ==="

source /workspace/scripts/task_utils.sh

IRCADB_DIR="/home/ga/Documents/SlicerData/IRCADb"
OUTPUT_SCENE="$IRCADB_DIR/organized_planning.mrb"
GROUND_TRUTH_DIR="/var/lib/slicer/ground_truth"

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
echo "Task duration: $((TASK_END - TASK_START)) seconds"

# Take final screenshot
echo "Capturing final screenshot..."
take_screenshot /tmp/task_final.png ga
sleep 1

# ============================================================
# Check if Slicer is running and export current scene state
# ============================================================
SLICER_RUNNING="false"
if is_slicer_running; then
    SLICER_RUNNING="true"
    echo "Slicer is running, exporting scene state..."
    
    # Create export script
    cat > /tmp/export_segments.py << 'PYEOF'
import slicer
import os
import json

output_dir = "/home/ga/Documents/SlicerData/IRCADb"
result = {
    "segments": [],
    "segment_count": 0,
    "scene_saved": False
}

# Find segmentation nodes
seg_nodes = slicer.util.getNodesByClass("vtkMRMLSegmentationNode")
print(f"Found {len(seg_nodes)} segmentation node(s)")

for seg_node in seg_nodes:
    segmentation = seg_node.GetSegmentation()
    if segmentation:
        num_segments = segmentation.GetNumberOfSegments()
        result["segment_count"] = num_segments
        print(f"Segmentation '{seg_node.GetName()}' has {num_segments} segments")
        
        for i in range(num_segments):
            segment_id = segmentation.GetNthSegmentID(i)
            segment = segmentation.GetSegment(segment_id)
            if segment:
                name = segment.GetName()
                color = segment.GetColor()
                # Convert color from 0-1 to 0-255
                r = int(color[0] * 255)
                g = int(color[1] * 255)
                b = int(color[2] * 255)
                
                seg_info = {
                    "name": name,
                    "r": r,
                    "g": g,
                    "b": b,
                    "segment_id": segment_id
                }
                result["segments"].append(seg_info)
                print(f"  Segment '{name}': RGB({r}, {g}, {b})")

# Check if output scene exists
output_scene = os.path.join(output_dir, "organized_planning.mrb")
if os.path.exists(output_scene):
    result["scene_saved"] = True
    result["scene_size_bytes"] = os.path.getsize(output_scene)
    result["scene_mtime"] = int(os.path.getmtime(output_scene))
    print(f"Output scene exists: {result['scene_size_bytes']} bytes")

# Save results
result_path = "/tmp/segment_export.json"
with open(result_path, "w") as f:
    json.dump(result, f, indent=2)
print(f"Export saved to {result_path}")
PYEOF

    # Run export script in Slicer
    sudo -u ga DISPLAY=:1 /opt/Slicer/Slicer --no-splash --no-main-window --python-script /tmp/export_segments.py > /tmp/slicer_export.log 2>&1 &
    EXPORT_PID=$!
    
    # Wait for export (max 30 seconds)
    for i in $(seq 1 30); do
        if [ -f /tmp/segment_export.json ]; then
            echo "Export completed"
            break
        fi
        sleep 1
    done
    
    kill $EXPORT_PID 2>/dev/null || true
fi

# ============================================================
# Check output file
# ============================================================
OUTPUT_EXISTS="false"
OUTPUT_SIZE=0
OUTPUT_MTIME=0
FILE_CREATED_DURING_TASK="false"

if [ -f "$OUTPUT_SCENE" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c%s "$OUTPUT_SCENE" 2>/dev/null || echo "0")
    OUTPUT_MTIME=$(stat -c%Y "$OUTPUT_SCENE" 2>/dev/null || echo "0")
    
    # Check if file was created during task
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
        echo "Output file was created during task"
    else
        echo "WARNING: Output file existed before task start"
    fi
    
    echo "Output scene: $OUTPUT_SCENE ($OUTPUT_SIZE bytes)"
fi

# ============================================================
# Parse the MRB file to extract segment information
# ============================================================
SEGMENTS_JSON="[]"
SEGMENT_COUNT=0

# MRB is a zip file containing MRML XML
if [ -f "$OUTPUT_SCENE" ] && [ "$OUTPUT_SIZE" -gt 1000 ]; then
    echo "Parsing MRB file for segment data..."
    
    # Extract and parse MRML
    TEMP_DIR=$(mktemp -d)
    cd "$TEMP_DIR"
    
    unzip -q "$OUTPUT_SCENE" 2>/dev/null || true
    
    # Find the MRML file
    MRML_FILE=$(find . -name "*.mrml" | head -1)
    
    if [ -n "$MRML_FILE" ] && [ -f "$MRML_FILE" ]; then
        echo "Found MRML file: $MRML_FILE"
        
        # Parse segments using Python
        SEGMENTS_JSON=$(python3 << PYEOF
import xml.etree.ElementTree as ET
import json
import os

mrml_file = "$MRML_FILE"
segments = []

try:
    tree = ET.parse(mrml_file)
    root = tree.getroot()
    
    # Look for Segment elements within Segmentation nodes
    for seg_node in root.iter():
        if 'Segmentation' in seg_node.tag:
            # Find segment storage references
            pass
        
        # Look for segment definitions
        if seg_node.tag == 'Segment':
            name = seg_node.get('name', seg_node.get('Name', ''))
            color_str = seg_node.get('color', seg_node.get('Color', ''))
            
            if name:
                seg_info = {"name": name, "r": 128, "g": 128, "b": 128}
                
                # Parse color (format: "r;g;b" or "r g b" with values 0-1)
                if color_str:
                    try:
                        parts = color_str.replace(';', ' ').split()
                        if len(parts) >= 3:
                            r = int(float(parts[0]) * 255)
                            g = int(float(parts[1]) * 255)
                            b = int(float(parts[2]) * 255)
                            seg_info["r"] = r
                            seg_info["g"] = g
                            seg_info["b"] = b
                    except:
                        pass
                
                segments.append(seg_info)
    
    # Also check for vtkMRMLSegmentationNode with segment references
    for node in root.iter():
        if 'SegmentationNode' in str(node.tag) or 'Segmentation' in str(node.tag):
            # Look for nested segment definitions
            for child in node:
                if 'Segment' in str(child.tag):
                    name = child.get('name', child.get('Name', ''))
                    color_str = child.get('color', child.get('Color', ''))
                    
                    if name and not any(s['name'] == name for s in segments):
                        seg_info = {"name": name, "r": 128, "g": 128, "b": 128}
                        if color_str:
                            try:
                                parts = color_str.replace(';', ' ').split()
                                if len(parts) >= 3:
                                    seg_info["r"] = int(float(parts[0]) * 255)
                                    seg_info["g"] = int(float(parts[1]) * 255)
                                    seg_info["b"] = int(float(parts[2]) * 255)
                            except:
                                pass
                        segments.append(seg_info)

except Exception as e:
    print(f"Error parsing MRML: {e}", file=__import__('sys').stderr)

print(json.dumps(segments))
PYEOF
)
        SEGMENT_COUNT=$(echo "$SEGMENTS_JSON" | python3 -c "import json,sys; print(len(json.load(sys.stdin)))" 2>/dev/null || echo "0")
    fi
    
    # Cleanup
    cd /
    rm -rf "$TEMP_DIR"
fi

# If MRB parsing failed, try to use the Slicer export
if [ "$SEGMENT_COUNT" -eq 0 ] && [ -f /tmp/segment_export.json ]; then
    echo "Using Slicer export for segment data..."
    SEGMENTS_JSON=$(python3 -c "import json; data=json.load(open('/tmp/segment_export.json')); print(json.dumps(data.get('segments', [])))" 2>/dev/null || echo "[]")
    SEGMENT_COUNT=$(echo "$SEGMENTS_JSON" | python3 -c "import json,sys; print(len(json.load(sys.stdin)))" 2>/dev/null || echo "0")
fi

echo "Found $SEGMENT_COUNT segments"

# ============================================================
# Create result JSON
# ============================================================
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)

cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "slicer_was_running": $SLICER_RUNNING,
    "output_exists": $OUTPUT_EXISTS,
    "output_size_bytes": $OUTPUT_SIZE,
    "output_mtime": $OUTPUT_MTIME,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "segment_count": $SEGMENT_COUNT,
    "segments": $SEGMENTS_JSON,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/segment_task_result.json 2>/dev/null || sudo rm -f /tmp/segment_task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/segment_task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/segment_task_result.json
chmod 666 /tmp/segment_task_result.json 2>/dev/null || sudo chmod 666 /tmp/segment_task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Result saved to /tmp/segment_task_result.json"
cat /tmp/segment_task_result.json
echo ""

# Close Slicer
echo "Closing 3D Slicer..."
close_slicer

echo "=== Export Complete ==="